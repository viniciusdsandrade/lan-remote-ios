import Foundation
import Combine
import UIKit

// MARK: - LG TV ROAP Client for iOS

@MainActor
final class LGTVClient: ObservableObject {
    @Published var config: TVConfig
    @Published var powerState: TVPowerState = .unknown
    /// On, but its control server isn't taking requests (see `checkTVPing`): a key pressed meanwhile is
    /// dropped, not kept for later.
    @Published var notAnswering: Bool = false
    /// Another device on the LAN answered at the TV's IP right after the TV was active there.
    @Published var ipConflict: Bool = false
    /// The app can't reach the LAN at all (off Wi-Fi, or local network access denied by iOS), so the
    /// TV's state is unknown rather than off.
    @Published var networkBlock: NetworkBlock?
    /// The TV answers but refuses the app (HTTP 401) and the saved pairing key, if any, doesn't work.
    @Published var needsPairing: Bool = false
    @Published var isMuted: Bool = false
    @Published var volumeLevel: Int = 10
    @Published var inputSourceName: String = "---"
    @Published var channelMajor: String = ""
    @Published var isRefreshing: Bool = false

    // Turning the TV on through the TV Box (see TVBoxLink.swift)
    @Published var box: AndroidTVBox? = AndroidTVBox.load()
    @Published var powerOnStep: String = ""
    @Published var powerOnError: String?
    @Published var attentionPulse: Int = 0          // bumped when a key is pressed with the TV off
    @Published var boxPairingStage: BoxPairingStage = .idle
    @Published var discoveredBoxes: [AndroidTVBox] = []
    @Published var boxCodeError: String?
    var activePairing: AndroidTVPairing?
    var pairingCandidate: AndroidTVBox?
    var lastBoxRefresh = Date.distantPast

    var isConnected: Bool { powerState == .on }

    private var pollTimer: Timer?

    // Keys go out at once or not at all: see `sendKey`.
    private struct PendingKey {
        let key: TVKey
        var pressed: ContinuousClock.Instant
    }
    private var pendingKeys: [PendingKey] = []
    private var sendingKeys = false
    /// The last key the TV may have run, and when its answer came (or was given up on).
    private var lastKey: (key: TVKey, answered: ContinuousClock.Instant)?
    private var volumeFollowUp: Task<Void, Never>?
    /// How long after the tap a key may still leave for the TV. One that can't go by then is dropped: a
    /// volume step landing after the finger left the button is worse than a tap that did nothing.
    var keyFreshness: TimeInterval = 0.8
    /// Rest the TV needs between two keys, counted from the previous key's answer: it discards a key
    /// that comes too soon after another, and 0.3 s is the spacing checked on the xxLN5700 for all of them.
    var keyRest: TimeInterval = 0.30
    /// The same between two volume steps, the keys tapped in a row. Measured on the xxLN5700: steps
    /// 90 ms apart or more all registered, steps 55 ms apart lost one.
    var volumeRest: TimeInterval = 0.15
    /// How long the TV has to answer a key it received before the app moves on to the next one.
    var keyAnswerTimeout: TimeInterval = 2.0
    /// Takes one key's request to the TV (see `TVKeyLink`). Tests put their own in.
    var keyTransport: @Sendable (URLRequest, _ connectWithin: TimeInterval, _ answerWithin: TimeInterval) async -> KeyDelivery = {
        await TVKeyLink.deliver($0, connectWithin: $1, answerWithin: $2)
    }
    var pingProbe: @Sendable (String) async -> Bool = { await LGTVDiscovery.answersPing($0) }
    var foreignHostProbe: @Sendable (String) async -> Bool = { await LGTVDiscovery.hasForeignService($0) }
    var locateProbe: @Sendable (TVConfig) async -> String? = { await LGTVDiscovery.locate(matching: $0) }
    var networkBlockProbe: @Sendable (String, Int) async -> NetworkBlock? = { await LGTVDiscovery.networkBlock(near: $0, port: $1) }
    private var poweredOffAt: Date?
    private var lastAnsweredAt: Date?
    private let ipConflictWindow: TimeInterval = 120
    private var lastAutomaticSearch: Date = .distantPast

    init(config: TVConfig? = nil, autoStart: Bool = true) {
        self.config = config ?? TVConfig.load()
        guard autoStart else { return }
        startPolling()
        Task {
            await self.refreshStatus()
        }
    }

    deinit {
        pollTimer?.invalidate()
    }

    // MARK: - Configuration Persistence

    func saveConfig() {
        config.save()
    }

    func updateHost(_ newHost: String, port: Int = 8080) {
        let trimmed = newHost.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed != config.host || port != config.port {
            lastAnsweredAt = nil
            notAnswering = false
            ipConflict = false
            needsPairing = false
        }
        config.host = trimmed
        config.port = port
        saveConfig()
        Task {
            await refreshStatus()
        }
    }

    // MARK: - TV Relocation (DHCP Migration)

    /// Attempts to relocate the TV when its IP address changed due to DHCP lease renewal.
    /// The configured IP is checked every time. Every failed request asks for this, and the TV often
    /// stalls for many seconds, so the search runs at most every 30 s.
    @discardableResult
    func relocateTVIfNeeded() async -> Bool {
        var found = await LGTVDiscovery.probeKnownHosts(of: config)
        if found == nil, Date().timeIntervalSince(lastAutomaticSearch) >= 30 {
            lastAutomaticSearch = Date()
            let currentConfig = config
            let locate = locateProbe
            found = await locate(currentConfig)
        }
        guard let newHost = found, newHost != config.host else {
            return false
        }
        NSLog("LG TV relocated from %@ to %@", config.host, newHost)
        self.config.host = newHost
        self.lastAnsweredAt = nil
        self.notAnswering = false
        self.ipConflict = false
        saveConfig()
        return true
    }

    // MARK: - Polling

    func startPolling() {
        pollTimer?.invalidate()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 10.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                // The queries go to the same control server as the keys: not while keys are on their way.
                guard let self, !self.sendingKeys else { return }
                await self.refreshStatus()
            }
        }
    }

    func stopPolling() {
        pollTimer?.invalidate()
        pollTimer = nil
    }

    // MARK: - Network Request Helpers

    func createRequest(path: String, method: String = "GET", body: String? = nil) -> URLRequest? {
        guard let url = URL(string: "http://\(config.host):\(config.port)\(path)") else {
            return nil
        }
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.timeoutInterval = 3.5
        req.setValue("Close", forHTTPHeaderField: "Connection")
        req.setValue("no-cache", forHTTPHeaderField: "Cache-Control")

        // Critical: LG xxLN5700 fw 05.02.11 requirement:
        // User-Agent must NOT contain "UDAP/2.0" for ROAP, otherwise the TV responds HTTP 400 Bad Request
        if config.protocolType == "udap" {
            req.setValue("iOS/1.0 UDAP/2.0 lg_roap_control/1.0.0", forHTTPHeaderField: "User-Agent")
            req.setValue("text/xml; charset=utf-8", forHTTPHeaderField: "Content-Type")
        } else {
            req.setValue("lg_roap_control/1.0.0 (iOS)", forHTTPHeaderField: "User-Agent")
            req.setValue("application/atom+xml", forHTTPHeaderField: "Content-Type")
        }

        if let body = body {
            req.httpBody = body.data(using: .utf8)
        }
        return req
    }

    // MARK: - Keys: at once or not at all

    /// A tap reaches the TV right away or is dropped; it is never kept to be sent later. Keys used to
    /// wait in line 0.3 s apart (and up to 15 s for a TV that wasn't answering), so tapping the volume
    /// faster than that left it climbing for seconds after the finger had stopped.
    func sendKey(_ key: TVKey) {
        guard powerState != .off, powerState != .turningOn, networkBlock == nil else {
            // Nothing to send to; point the user at the "turn on" banner instead of failing silently.
            attentionPulse += 1
            HapticManager.shared.warning()
            return
        }

        // Taps of one key faster than the TV takes them don't pile up: the tap already waiting stands
        // for them (no click either, since no further key will go out for this one).
        if let waiting = pendingKeys.indices.last, pendingKeys[waiting].key == key {
            pendingKeys[waiting].pressed = .now
            return
        }

        // Trigger specific haptic feedback based on key type
        triggerHaptic(for: key)

        pendingKeys.append(PendingKey(key: key, pressed: .now))
        guard !sendingKeys else { return }
        sendingKeys = true
        Task { [weak self] in await self?.sendPendingKeys() }
    }

    /// Sends the waiting keys one at a time, in the order they were pressed, leaving the TV its rest
    /// between two of them. A key that hasn't left `keyFreshness` after its tap is dropped.
    private func sendPendingKeys() async {
        while let next = pendingKeys.first {
            guard powerState != .off, networkBlock == nil else {
                pendingKeys.removeAll()
                break
            }
            if let lastKey {
                let rest = Duration.seconds(next.key.isVolumeStep && lastKey.key.isVolumeStep ? volumeRest : keyRest)
                let rested = lastKey.answered.duration(to: .now)
                if rested < rest {
                    // Taps keep coming meanwhile, and the TV may go off: look at the line again after.
                    try? await Task.sleep(for: rest - rested)
                    continue
                }
            }
            let pending = pendingKeys.removeFirst()
            guard pending.pressed.duration(to: .now) < .seconds(keyFreshness) else {
                NSLog("LG TV: tecla %@ descartada, não saiu em %.1f s", pending.key.label, keyFreshness)
                continue
            }
            await deliver(pending)
        }
        sendingKeys = false
    }

    private func triggerHaptic(for key: TVKey) {
        switch key {
        case .power:
            HapticManager.shared.powerTap()
        case .ok:
            HapticManager.shared.okTap()
        case .up, .down, .left, .right:
            HapticManager.shared.directionTap()
        case .volumeUp, .volumeDown, .channelUp, .channelDown:
            HapticManager.shared.rockerTap()
        default:
            if key.isDigit {
                HapticManager.shared.digitTap()
            } else {
                HapticManager.shared.buttonPress()
            }
        }
    }

    private func keyRequest(for key: TVKey) -> URLRequest? {
        let code = key.rawValue
        if config.protocolType == "udap" {
            return createRequest(path: "/udap/api/command", method: "POST",
                                 body: "<?xml version=\"1.0\" encoding=\"utf-8\"?><envelope><api type=\"command\"><name>HandleKeyInput</name><value>\(code)</value></api></envelope>")
        }
        return createRequest(path: "/roap/api/command", method: "POST",
                             body: "<?xml version=\"1.0\" encoding=\"utf-8\"?><command><session>\(config.session ?? "")</session><type>HandleKeyInput</type><value>\(code)</value></command>")
    }

    /// One try for one tap, while it is fresh. Once the request has left it is never sent again: a key
    /// run twice, or seconds late, is worse than a tap that did nothing.
    private func deliver(_ pending: PendingKey, afterPairing: Bool = false) async {
        let key = pending.key
        let left = (Duration.seconds(keyFreshness) - pending.pressed.duration(to: .now)) / .seconds(1)
        guard left > 0, let request = keyRequest(for: key) else { return }

        switch await keyTransport(request, left, keyAnswerTimeout) {
        case .answered(status: 200):
            keyTaken(key)
        case .answered(status: 401) where !afterPairing:
            // Session expired or unauthenticated; attempt re-pairing
            markAnswering()
            switch await pairWithSavedKey() {
            case .paired:
                await deliver(pending, afterPairing: true)
            case .rejected:
                markNeedsPairing()
                NSLog("LG TV: tecla %@ recusada, o app precisa ser pareado com a TV", key.label)
            case .noAnswer:
                NSLog("LG TV: tecla %@ perdida, a TV não respondeu ao pareamento", key.label)
            }
        case .answered(let status):
            NSLog("LG TV rejected key %@ (HTTP %d)", key.label, status)
        case .notSent:
            // The tap did nothing and won't: say so, as when a key is pressed with the TV off.
            NSLog("LG TV: tecla %@ descartada, a TV não aceitou a conexão a tempo", key.label)
            HapticManager.shared.warning()
            checkOnTV()
        case .unanswered:
            // The TV may have run it: it gets its rest all the same.
            lastKey = (key, .now)
            NSLog("LG TV: tecla %@ enviada, sem resposta da TV em %.1f s", key.label, keyAnswerTimeout)
            checkOnTV()
        }
    }

    private func keyTaken(_ key: TVKey) {
        lastKey = (key, .now)
        // The power key only switches the TV off: its network goes down right after.
        if key == .power {
            notAnswering = false
            ipConflict = false
            powerState = .off
            poweredOffAt = Date()
            lastAnsweredAt = nil
            return
        }
        markAnswering()
        needsPairing = false
        powerState = .on

        // The level shown follows the steps the TV took; the TV itself is asked once the taps stop.
        switch key {
        case .volumeUp:
            volumeLevel = min(volumeLevel + 1, 100)
            followVolume()
        case .volumeDown:
            volumeLevel = max(volumeLevel - 1, 0)
            followVolume()
        case .mute:
            followVolume()
        default:
            break
        }
    }

    /// Asks the TV for its volume and mute once the taps stop, instead of after every step: the queries
    /// go to the same control server as the keys.
    private func followVolume() {
        volumeFollowUp?.cancel()
        volumeFollowUp = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            while !Task.isCancelled, let self, self.sendingKeys || self.isRefreshing {
                try? await Task.sleep(for: .milliseconds(100))
            }
            guard !Task.isCancelled else { return }
            await self?.refreshStatus()
        }
    }

    /// A key didn't get through: finds out why (standby, control server not answering, another IP,
    /// iPhone off the LAN) without holding the next taps back.
    private func checkOnTV() {
        Task { [weak self] in await self?.refreshStatus() }
    }

    private enum PingStatus {
        case unreachable
        case aliveSameTV
        case ipConflict
    }

    /// Distinguishes standby (network interface down, no ping) from an awake TV whose HTTP port timed
    /// out, and from an active LAN IP conflict where another device (with non-TV ports open) answers
    /// at the TV's IP right after the TV was responding there. Right after the power key the TV still
    /// answers ping briefly while shutting down.
    private func checkTVPing() async -> PingStatus {
        if let poweredOffAt, Date().timeIntervalSince(poweredOffAt) < 30 { return .unreachable }
        let host = config.host
        let probe = pingProbe
        let checkForeign = foreignHostProbe
        guard await probe(host) else { return .unreachable }
        if await checkForeign(host) {
            if let lastAnsweredAt, Date().timeIntervalSince(lastAnsweredAt) < ipConflictWindow {
                return .ipConflict
            }
            return .unreachable
        }
        return .aliveSameTV
    }

    private func markNotAnswering(conflict: Bool) {
        if conflict, !ipConflict {
            NSLog("LG TV: conflito de IP em %@ — outro aparelho respondeu no endereço da TV", config.host)
        } else if !conflict, !notAnswering {
            NSLog("LG TV: ligada (responde ao ping), mas sem aceitar comandos na porta %d", config.port)
        }
        notAnswering = true
        ipConflict = conflict
        if powerState != .turningOn {
            powerState = .on
            powerOnError = nil
        }
    }

    private func markAnswering() {
        if notAnswering {
            NSLog("LG TV: voltou a aceitar comandos")
        }
        notAnswering = false
        ipConflict = false
        networkBlock = nil
        poweredOffAt = nil
        lastAnsweredAt = Date()
    }

    /// No answer from the TV, not even to ping: standby (unless we are switching it on).
    private func markUnreachable() {
        notAnswering = false
        ipConflict = false
        needsPairing = false
        networkBlock = nil
        if powerState != .turningOn {
            powerState = .off
        }
    }

    /// Nothing answered at the TV's IP: standby, unless the iPhone can't reach the LAN at all, in which
    /// case "off" would send the user looking for a problem with the TV.
    private func resolveUnreachable() async {
        if let block = await networkBlockProbe(config.host, config.port) {
            markBlocked(block)
        } else {
            markUnreachable()
        }
    }

    /// A request failed in a way that points at the iPhone rather than the TV (no Wi-Fi address, or
    /// URLSession's "offline" error, which is what a local network denial looks like): checks for a
    /// block before relocating, since a sweep can't find anything then.
    private func networkBlockedFast(by error: Error) async -> Bool {
        let offline = (error as? URLError)?.code == .notConnectedToInternet
        guard offline || LGTVDiscovery.localIPv4Networks().isEmpty,
              let block = await networkBlockProbe(config.host, config.port) else { return false }
        markBlocked(block)
        return true
    }

    private func markBlocked(_ block: NetworkBlock) {
        if networkBlock != block {
            NSLog("LG TV: sem acesso à rede local (%@), estado da TV desconhecido",
                  block == .offWiFi ? "iPhone fora do Wi-Fi" : "permissão de Rede Local negada pelo iOS")
        }
        networkBlock = block
        notAnswering = false
        ipConflict = false
        needsPairing = false
        pendingKeys.removeAll()
        if powerState != .turningOn {
            powerState = .unknown
        }
    }

    /// The TV answered with 401 and no saved key works: it is on, and only pairing will get keys through.
    private func markNeedsPairing() {
        if !needsPairing {
            NSLog("LG TV: a TV recusou o app (HTTP 401) e não há chave de pareamento válida salva")
        }
        needsPairing = true
        notAnswering = false
        ipConflict = false
        networkBlock = nil
        powerState = .on
        powerOnError = nil
    }

    // MARK: - Status Queries

    /// What the TV is showing, as a JPEG (the screen_image query). Nil when the TV doesn't answer.
    func screenImage() async -> Data? {
        let basePath = config.protocolType == "udap" ? "/udap/api/data" : "/roap/api/data"
        if let request = createRequest(path: "\(basePath)?target=screen_image&session=\(config.session ?? "")"),
           let (data, response) = try? await URLSession.shared.data(for: request),
           (response as? HTTPURLResponse)?.statusCode == 200,
           data.starts(with: [0xFF, 0xD8]) {
            return data
        }
        if await relocateTVIfNeeded(),
           let retryReq = createRequest(path: "\(basePath)?target=screen_image&session=\(config.session ?? "")"),
           let (data, response) = try? await URLSession.shared.data(for: retryReq),
           (response as? HTTPURLResponse)?.statusCode == 200,
           data.starts(with: [0xFF, 0xD8]) {
            return data
        }
        return nil
    }

    func refreshStatus() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        await performStatusCheck(allowRelocate: true)
    }

    private func performStatusCheck(allowRelocate: Bool) async {
        var session = config.session ?? ""
        let basePath = config.protocolType == "udap" ? "/udap/api/data" : "/roap/api/data"
        let volPath = "\(basePath)?target=volume_info&session=\(session)"

        if let volReq = createRequest(path: volPath) {
            do {
                let (data, resp) = try await URLSession.shared.data(for: volReq)
                if let httpResp = resp as? HTTPURLResponse {
                    if httpResp.statusCode == 200 {
                        markAnswering()
                        self.needsPairing = false
                        self.powerState = .on
                        self.powerOnError = nil
                        if let str = String(data: data, encoding: .utf8) {
                            if let muteVal = Self.extractXMLTag(from: str, tag: "mute") {
                                self.isMuted = (muteVal.lowercased() == "true")
                            }
                            if let lvlVal = Self.extractXMLTag(from: str, tag: "level"), let lvl = Int(lvlVal) {
                                self.volumeLevel = lvl
                            }
                        }
                    } else if httpResp.statusCode == 401 {
                        markAnswering()
                        let pairing = await self.pairWithSavedKey()
                        if pairing == .rejected {
                            markNeedsPairing()
                            refreshBoxAddressIfNeeded()
                            return
                        }
                        if pairing == .paired {
                            session = config.session ?? ""
                            if let retryReq = createRequest(path: "\(basePath)?target=volume_info&session=\(session)"),
                               let (rData, rResp) = try? await URLSession.shared.data(for: retryReq),
                               (rResp as? HTTPURLResponse)?.statusCode == 200 {
                                self.powerState = .on
                                self.powerOnError = nil
                                if let str = String(data: rData, encoding: .utf8) {
                                    if let muteVal = Self.extractXMLTag(from: str, tag: "mute") {
                                        self.isMuted = (muteVal.lowercased() == "true")
                                    }
                                    if let lvlVal = Self.extractXMLTag(from: str, tag: "level"), let lvl = Int(lvlVal) {
                                        self.volumeLevel = lvl
                                    }
                                }
                            }
                        } else {
                            switch await checkTVPing() {
                            case .aliveSameTV:
                                markNotAnswering(conflict: false)
                            case .ipConflict:
                                markNotAnswering(conflict: true)
                            case .unreachable:
                                markUnreachable()
                            }
                            refreshBoxAddressIfNeeded()
                            return
                        }
                    } else {
                        if allowRelocate, await relocateTVIfNeeded() {
                            await performStatusCheck(allowRelocate: false)
                            return
                        }
                        if let lastAnsweredAt, Date().timeIntervalSince(lastAnsweredAt) < ipConflictWindow {
                            markNotAnswering(conflict: true)
                        } else {
                            markUnreachable()
                        }
                        refreshBoxAddressIfNeeded()
                        return
                    }
                }
            } catch {
                // Off Wi-Fi or local network denied: nothing on the LAN answers, so neither the
                // relocation nor the ping can tell anything about the TV.
                if await networkBlockedFast(by: error) {
                    return
                }
                // Check first whether DHCP moved the TV to another IP; otherwise use ping + foreign-port
                // probe to tell standby apart from a transient HTTP stall or an active LAN IP conflict.
                if allowRelocate, await relocateTVIfNeeded() {
                    await performStatusCheck(allowRelocate: false)
                    return
                }
                switch await checkTVPing() {
                case .aliveSameTV:
                    markNotAnswering(conflict: false)
                case .ipConflict:
                    markNotAnswering(conflict: true)
                case .unreachable:
                    await resolveUnreachable()
                }
                refreshBoxAddressIfNeeded()
                return   // no point asking for the channel as well
            }
        }

        // Also fetch current channel / input
        let chPath = "\(basePath)?target=cur_channel&session=\(session)"
        if let chReq = createRequest(path: chPath) {
            if let (chData, chResp) = try? await URLSession.shared.data(for: chReq),
               let chHttp = chResp as? HTTPURLResponse, chHttp.statusCode == 200,
               let str = String(data: chData, encoding: .utf8) {
                if let src = Self.extractXMLTag(from: str, tag: "inputSourceName"), !src.isEmpty {
                    self.inputSourceName = src
                }
                if let major = Self.extractXMLTag(from: str, tag: "major"), major != "65520", !major.isEmpty {
                    self.channelMajor = major
                }
            }
        }

        refreshBoxAddressIfNeeded()
    }

    // MARK: - Pairing & Discovery

    func requestPairingKeyOnTV() async -> (success: Bool, message: String) {
        let path = config.protocolType == "udap" ? "/udap/api/pairing" : "/roap/api/auth"
        let xml: String
        if config.protocolType == "udap" {
            xml = "<?xml version=\"1.0\" encoding=\"utf-8\"?><envelope><api type=\"pairing\"><name>showKey</name></api></envelope>"
        } else {
            xml = "<?xml version=\"1.0\" encoding=\"utf-8\"?><auth><type>AuthKeyReq</type></auth>"
        }

        guard let req = createRequest(path: path, method: "POST", body: xml) else {
            return (false, "URL inválida")
        }

        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            if let httpResp = resp as? HTTPURLResponse {
                if httpResp.statusCode == 200 {
                    HapticManager.shared.success()
                    return (true, "Código exibido na tela da TV! Digite os 6 números.")
                }
                let body = String(data: data, encoding: .utf8) ?? ""
                HapticManager.shared.error()
                return (false, "TV retornou status \(httpResp.statusCode): \(body)")
            }
        } catch {
            HapticManager.shared.error()
            return (false, "Falha ao conectar: \(error.localizedDescription)")
        }
        return (false, "Resposta desconhecida")
    }

    private func authenticateWithKey(_ cleanKey: String) async -> (success: Bool, statusCode: Int?, errorMessage: String?) {
        let path = config.protocolType == "udap" ? "/udap/api/pairing" : "/roap/api/auth"
        let xml: String
        if config.protocolType == "udap" {
            xml = "<?xml version=\"1.0\" encoding=\"utf-8\"?><envelope><api type=\"pairing\"><name>hello</name><value>\(cleanKey)</value><port>\(config.port)</port></api></envelope>"
        } else {
            xml = "<?xml version=\"1.0\" encoding=\"utf-8\"?><auth><type>AuthReq</type><value>\(cleanKey)</value></auth>"
        }

        guard let req = createRequest(path: path, method: "POST", body: xml) else {
            return (false, nil, "URL inválida")
        }

        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            if let httpResp = resp as? HTTPURLResponse {
                if httpResp.statusCode == 200 {
                    markAnswering()
                    self.needsPairing = false
                    self.config.pairingKey = cleanKey
                    if let str = String(data: data, encoding: .utf8),
                       let session = Self.extractXMLTag(from: str, tag: "session") {
                        self.config.session = session
                    }
                    self.saveConfig()
                    self.powerState = .on
                    self.powerOnError = nil
                    return (true, 200, nil)
                }
                return (false, httpResp.statusCode, nil)
            }
        } catch {
            return (false, nil, error.localizedDescription)
        }
        return (false, nil, "Erro inesperado")
    }

    func confirmPairing(key: String) async -> (success: Bool, message: String) {
        let cleanKey = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard cleanKey.count >= 6 else {
            HapticManager.shared.warning()
            return (false, "Chave deve conter 6 dígitos.")
        }

        let res = await authenticateWithKey(cleanKey)
        if res.success {
            HapticManager.shared.success()
            if !self.isRefreshing {
                await self.refreshStatus()
            }
            return (true, "Pareamento concluído com sucesso!")
        }
        HapticManager.shared.error()
        if res.statusCode == 401 {
            return (false, "Código incorreto! Confira os dígitos na tela da TV.")
        } else if let status = res.statusCode {
            return (false, "Erro HTTP \(status)")
        } else if let err = res.errorMessage {
            return (false, "Erro de rede: \(err)")
        }
        return (false, "Erro inesperado")
    }

    private enum SavedKeyPairing { case paired, rejected, noAnswer }

    /// Re-pairs with the saved key after a 401. `rejected` covers no key saved as well: either way only
    /// pairing again (code on the TV screen) gets the app in.
    private func pairWithSavedKey() async -> SavedKeyPairing {
        guard let key = config.pairingKey?.trimmingCharacters(in: .whitespacesAndNewlines),
              key.count >= 6 else { return .rejected }
        let result = await authenticateWithKey(key)
        if result.success { return .paired }
        return result.statusCode != nil ? .rejected : .noAnswer
    }

    // MARK: - Utilities

    nonisolated static func extractXMLTag(from xml: String, tag: String) -> String? {
        let pattern = "<\(tag)>\\s*([^<]+?)\\s*</\(tag)>"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let match = regex.firstMatch(in: xml, options: [], range: NSRange(xml.startIndex..., in: xml)),
              let range = Range(match.range(at: 1), in: xml) else {
            return nil
        }
        return String(xml[range]).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
