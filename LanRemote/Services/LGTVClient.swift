import Foundation
import Combine
import UIKit

// MARK: - LG TV ROAP Client for iOS

@MainActor
final class LGTVClient: ObservableObject {
    @Published var config: TVConfig
    @Published var powerState: TVPowerState = .unknown
    /// On, but its control server isn't taking requests (see `checkTVPing`): recent keys wait briefly.
    @Published var notAnswering: Bool = false
    /// Another device on the LAN answered at the TV's IP right after the TV was active there.
    @Published var ipConflict: Bool = false
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
    private var lastSendTime: DispatchTime = .now()
    private let minGapSeconds: Double = 0.30
    private var pendingKeys: [(code: Int, label: String, pressed: Date)] = []
    private var sendingKeys = false
    /// How long a key waits for the control server to come back before it is dropped (short enough
    /// never to surprise the user a minute later with stale volume or navigation presses).
    var keyPatience: TimeInterval = 15
    var pingProbe: @Sendable (String) async -> Bool = { await LGTVDiscovery.answersPing($0) }
    var foreignHostProbe: @Sendable (String) async -> Bool = { await LGTVDiscovery.hasForeignService($0) }
    var locateProbe: @Sendable (TVConfig) async -> String? = { await LGTVDiscovery.locate(matching: $0) }
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
                await self?.refreshStatus()
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

    // MARK: - Command Execution with Debounce

    func sendKey(_ key: TVKey) {
        guard powerState != .off, powerState != .turningOn else {
            // Nothing to send to; point the user at the "turn on" banner instead of failing silently.
            attentionPulse += 1
            HapticManager.shared.warning()
            return
        }

        // Trigger specific haptic feedback based on key type
        triggerHaptic(for: key)

        pendingKeys.append((key.rawValue, key.label, Date()))
        guard !sendingKeys else { return }
        sendingKeys = true
        Task { [weak self] in await self?.sendPendingKeys() }
    }

    /// Sends the keys one at a time, in the order they were pressed: a key waiting for the TV holds
    /// the ones pressed after it, and any key that waited longer than `keyPatience` is dropped.
    private func sendPendingKeys() async {
        while !pendingKeys.isEmpty {
            guard powerState != .off else {
                pendingKeys.removeAll()
                break
            }
            let key = pendingKeys.removeFirst()
            guard Date().timeIntervalSince(key.pressed) < keyPatience else {
                NSLog("LG TV: tecla %@ descartada, esperou mais de %.0f s na fila", key.label, keyPatience)
                continue
            }

            // Debounce timing: Ensure min gap between key transmissions to avoid TV packet drop
            let now = DispatchTime.now()
            let elapsed = Double(now.uptimeNanoseconds - lastSendTime.uptimeNanoseconds) / 1_000_000_000.0
            if elapsed < minGapSeconds {
                let waitNanos = UInt64((minGapSeconds - elapsed) * 1_000_000_000)
                try? await Task.sleep(nanoseconds: waitNanos)
            }
            lastSendTime = DispatchTime.now()

            await performSendKey(code: key.code, label: key.label, pressed: key.pressed)
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

    private func performSendKey(code: Int, label: String, pressed: Date,
                                allowAuthRetry: Bool = true, allowRelocate: Bool = true) async {
        let session = config.session ?? ""
        let xml: String
        let path: String

        if config.protocolType == "udap" {
            path = "/udap/api/command"
            xml = "<?xml version=\"1.0\" encoding=\"utf-8\"?><envelope><api type=\"command\"><name>HandleKeyInput</name><value>\(code)</value></api></envelope>"
        } else {
            path = "/roap/api/command"
            xml = "<?xml version=\"1.0\" encoding=\"utf-8\"?><command><session>\(session)</session><type>HandleKeyInput</type><value>\(code)</value></command>"
        }

        guard let req = createRequest(path: path, method: "POST", body: xml) else { return }

        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            if let httpResp = resp as? HTTPURLResponse {
                if httpResp.statusCode == 200 {
                    // The power key only switches the TV off: its network goes down right after.
                    if code == TVKey.power.rawValue {
                        notAnswering = false
                        ipConflict = false
                        self.powerState = .off
                        poweredOffAt = Date()
                        lastAnsweredAt = nil
                    } else {
                        markAnswering()
                        self.powerState = .on
                    }

                    // Trigger status refresh shortly after volume/channel commands
                    if code == TVKey.volumeUp.rawValue || code == TVKey.volumeDown.rawValue || code == TVKey.mute.rawValue {
                        Task { [weak self] in
                            try? await Task.sleep(nanoseconds: 350_000_000)
                            await self?.refreshStatus()
                        }
                    }
                    return
                } else if httpResp.statusCode == 401 && allowAuthRetry {
                    // Session expired or unauthenticated; attempt re-pairing
                    markAnswering()
                    let success = await self.pairWithSavedKey()
                    if success {
                        await self.performSendKey(code: code, label: label, pressed: pressed,
                                                  allowAuthRetry: false, allowRelocate: false)
                        return
                    }
                } else {
                    let respStr = String(data: data, encoding: .utf8) ?? ""
                    NSLog("LG TV rejected key %@ (HTTP %d): %@", label, httpResp.statusCode, respStr)
                }
            }
        } catch {
            if allowRelocate, await relocateTVIfNeeded() {
                await performSendKey(code: code, label: label, pressed: pressed,
                                     allowAuthRetry: allowAuthRetry, allowRelocate: false)
                return
            }
            switch await checkTVPing() {
            case .aliveSameTV:
                markNotAnswering(conflict: false)
            case .ipConflict:
                markNotAnswering(conflict: true)
            case .unreachable:
                markUnreachable()
                return
            }
            guard Date().timeIntervalSince(pressed) < keyPatience else {
                NSLog("LG TV: tecla %@ descartada, a TV ficou %.0f s sem aceitar comandos", label, keyPatience)
                return
            }
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            await performSendKey(code: code, label: label, pressed: pressed,
                                 allowAuthRetry: allowAuthRetry, allowRelocate: false)
        }
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
        poweredOffAt = nil
        lastAnsweredAt = Date()
    }

    /// No answer from the TV, not even to ping: standby (unless we are switching it on).
    private func markUnreachable() {
        notAnswering = false
        ipConflict = false
        if powerState != .turningOn {
            powerState = .off
        }
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
                        if await self.pairWithSavedKey() {
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
                    markUnreachable()
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

    private func pairWithSavedKey() async -> Bool {
        guard let key = config.pairingKey?.trimmingCharacters(in: .whitespacesAndNewlines),
              key.count >= 6 else { return false }
        return await authenticateWithKey(key).success
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
