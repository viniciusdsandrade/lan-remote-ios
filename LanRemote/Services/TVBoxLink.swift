import Foundation
import Network

// Turning the TV on. The LG NetCast cuts its network in standby (Wake-on-LAN does nothing), so the
// app asks the TV Box plugged into it (Android TV) to do it: when the box wakes up it switches the
// TV on through HDMI-CEC ("One Touch Play"), which LG calls SIMPLINK and must be enabled on the TV.
// The box itself sleeps deeply too, but it does answer Wake-on-LAN on its Wi-Fi MAC.

/// The Android TV box used to switch the TV on.
struct AndroidTVBox: Codable, Equatable, Identifiable, Sendable {
    var name: String            // Bonjour name, e.g. "TV Box Xiaomi"
    var host: String            // last known IPv4 address
    var paired: Bool
    var mac: String? = nil      // Wi-Fi MAC for Wake-on-LAN, when known for sure (typed by the user)
    var bluetoothMAC: String? = nil   // from the Bonjour TXT record ("bt="); the Wi-Fi MAC is next to it

    var id: String { name }

    /// Addresses worth sending a magic packet to. iOS can't read the ARP table, so without a MAC
    /// typed in by the user the app tries the neighbours of the Bluetooth MAC (Wi-Fi and Bluetooth
    /// MACs of one device are consecutive; the order varies). Extra packets are harmless.
    var wakeMACs: [String] {
        if let mac, let normalized = MACAddress.normalize(mac) { return [normalized] }
        guard let bluetoothMAC, let bt = MACAddress.normalize(bluetoothMAC) else { return [] }
        return [MACAddress.offset(bt, by: -1), MACAddress.offset(bt, by: 1), bt].compactMap { $0 }
    }

    static let defaultsKey = "com.lanremote.ios.androidtvbox"

    static func load() -> AndroidTVBox? {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey) else { return nil }
        return try? JSONDecoder().decode(AndroidTVBox.self, from: data)
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: Self.defaultsKey)
        }
    }

    static func forget() {
        UserDefaults.standard.removeObject(forKey: defaultsKey)
    }
}

enum TVPowerState: Equatable, Sendable {
    case unknown      // first check still running
    case on
    case off          // not answering: standby, for this TV
    case turningOn
}

enum BoxPairingStage: Equatable, Sendable {
    case idle
    case searching
    case requestingCode
    case waitingForCode
    case confirming
    case failed(String)
}

// MARK: - Discovery

enum TVBoxDiscovery {
    static let serviceType = "_androidtvremote2._tcp"

    /// Android TV devices announcing the remote service on the local network.
    static func find(timeout: TimeInterval = 3) async -> [AndroidTVBox] {
        let queue = DispatchQueue(label: "tvbox.discovery")
        let found: [(name: String, bluetoothMAC: String?)] = await withCheckedContinuation { continuation in
            let descriptor = NWBrowser.Descriptor.bonjourWithTXTRecord(type: serviceType, domain: nil)
            let browser = NWBrowser(for: descriptor, using: .tcp)
            var names = Set<String>()
            var bluetoothMACs: [String: String] = [:]
            browser.browseResultsChangedHandler = { results, _ in
                for result in results {
                    guard case let .service(name, _, _, _) = result.endpoint else { continue }
                    names.insert(name)
                    if case let .bonjour(txt) = result.metadata,
                       let mac = txt.dictionary["bt"].flatMap(MACAddress.normalize) {
                        bluetoothMACs[name] = mac
                    }
                }
            }
            browser.start(queue: queue)
            queue.asyncAfter(deadline: .now() + timeout) {
                browser.cancel()
                continuation.resume(returning: names.sorted().map { ($0, bluetoothMACs[$0]) })
            }
        }
        var boxes: [AndroidTVBox] = []
        for entry in found {
            if let address = await resolve(entry.name) {
                boxes.append(AndroidTVBox(name: entry.name, host: address, paired: false, bluetoothMAC: entry.bluetoothMAC))
            }
        }
        return boxes
    }

    /// IPv4 address behind a Bonjour service name (connects briefly to read the resolved endpoint).
    private static func resolve(_ name: String, timeout: TimeInterval = 3) async -> String? {
        let parameters = NWParameters.tcp
        if let ip = parameters.defaultProtocolStack.internetProtocol as? NWProtocolIP.Options {
            ip.version = .v4
        }
        let connection = NWConnection(to: .service(name: name, type: serviceType, domain: "local.", interface: nil),
                                      using: parameters)
        let queue = DispatchQueue(label: "tvbox.resolve")
        return await withCheckedContinuation { continuation in
            var finished = false
            func finish(_ address: String?) {   // always called on `queue`
                guard !finished else { return }
                finished = true
                connection.cancel()
                continuation.resume(returning: address)
            }
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    if case let .hostPort(host, _)? = connection.currentPath?.remoteEndpoint,
                       case let .ipv4(address) = host {
                        finish(address.rawValue.map { String($0) }.joined(separator: "."))
                    } else {
                        finish(nil)
                    }
                case .failed, .cancelled: finish(nil)
                default: break
                }
            }
            connection.start(queue: queue)
            queue.asyncAfter(deadline: .now() + timeout) { finish(nil) }
        }
    }
}

// MARK: - Power on and box pairing

extension LGTVClient {
    var canTurnOnTV: Bool { box?.paired == true }

    func turnOn() {
        guard powerState != .turningOn, let box, box.paired else { return }
        Task { await performTurnOn(using: box) }
    }

    private func performTurnOn(using box: AndroidTVBox) async {
        powerState = .turningOn
        powerOnError = nil
        powerOnStep = "Acordando a \(box.name) pelo Wi-Fi…"
        HapticManager.shared.buttonPress()
        do {
            try await AndroidTVRemote.switchTVOn(host: box.host, wakeMACs: box.wakeMACs)
        } catch AndroidTVError.notPaired {
            self.box?.paired = false
            self.box?.save()
            failTurnOn("A TV Box não reconhece mais este iPhone. Pareie de novo em Ajustes.")
            return
        } catch AndroidTVError.asleep {
            failTurnOn(box.wakeMACs.isEmpty
                ? "A TV Box está em repouso e o app não sabe o MAC do Wi-Fi dela para acordá-la. Informe em Ajustes."
                : "A TV Box não acordou pelo Wi-Fi. Se o IP dela mudou, ligue a TV uma vez pelo controle e o app atualiza o endereço.")
            return
        } catch {
            failTurnOn("\(error.localizedDescription) Ela está ligada na tomada e no Wi-Fi?")
            return
        }

        // The picture comes back in seconds; the NetCast network takes almost a minute more.
        powerOnStep = "A TV está acendendo. O controle volta a responder em até 1 minuto…"
        let deadline = Date().addingTimeInterval(90)
        while Date() < deadline {
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            await refreshStatus()
            if powerState == .on {
                powerOnStep = ""
                HapticManager.shared.success()
                return
            }
        }
        failTurnOn("A TV Box recebeu o pedido, mas a TV não respondeu. Confira se o SIMPLINK está ligado na TV "
                   + "e o controle HDMI (CEC) na TV Box.")
    }

    private func failTurnOn(_ message: String) {
        powerState = .off
        powerOnStep = ""
        powerOnError = message
        HapticManager.shared.error()
    }

    /// While the TV is on the box is awake and findable: keep its address and Bluetooth MAC fresh,
    /// so a DHCP change doesn't leave the phone waking the wrong address later.
    func refreshBoxAddressIfNeeded() {
        guard let box, box.paired, powerState == .on,
              Date().timeIntervalSince(lastBoxRefresh) > 300 else { return }
        lastBoxRefresh = Date()
        Task {
            guard let fresh = await TVBoxDiscovery.find(timeout: 2).first(where: { $0.name == box.name }),
                  var current = self.box, current.name == fresh.name else { return }
            current.host = fresh.host
            current.bluetoothMAC = fresh.bluetoothMAC ?? current.bluetoothMAC
            if current != self.box {
                self.box = current
                current.save()
            }
        }
    }

    // MARK: Pairing with the box (once)

    func searchBoxes() {
        boxPairingStage = .searching
        Task {
            discoveredBoxes = await TVBoxDiscovery.find()
            boxPairingStage = .idle
        }
    }

    /// Makes the box show a 6-character code on the TV screen.
    func requestBoxCode(for candidate: AndroidTVBox) {
        activePairing?.cancel()
        boxCodeError = nil
        boxPairingStage = .requestingCode
        Task {
            do {
                let pairing = try AndroidTVPairing(host: candidate.host)
                try await pairing.start()
                activePairing = pairing
                pairingCandidate = candidate
                boxPairingStage = .waitingForCode
                HapticManager.shared.success()
            } catch {
                boxPairingStage = .failed(error.localizedDescription)
                HapticManager.shared.error()
            }
        }
    }

    func confirmBoxCode(_ code: String) {
        guard let pairing = activePairing, var candidate = pairingCandidate else { return }
        boxCodeError = nil
        boxPairingStage = .confirming
        Task {
            do {
                try await pairing.finish(code: code)
                candidate.paired = true
                candidate.mac = box?.mac   // keep a MAC the user typed earlier
                candidate.save()
                box = candidate
                activePairing = nil
                pairingCandidate = nil
                powerOnError = nil
                boxPairingStage = .idle
                HapticManager.shared.success()
            } catch AndroidTVError.wrongCode {
                // The checksum in the code catches typos before anything is sent; the box keeps waiting.
                boxCodeError = AndroidTVError.wrongCode.localizedDescription
                boxPairingStage = .waitingForCode
                HapticManager.shared.warning()
            } catch {
                pairing.cancel()
                activePairing = nil
                boxPairingStage = .failed(error.localizedDescription)
                HapticManager.shared.error()
            }
        }
    }

    func cancelBoxPairing() {
        activePairing?.cancel()
        activePairing = nil
        pairingCandidate = nil
        boxPairingStage = .idle
    }

    /// Stores the Wi-Fi MAC the user typed (or clears it when empty); returns false if it's not a MAC.
    @discardableResult
    func setBoxMAC(_ text: String) -> Bool {
        guard var current = box else { return false }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            current.mac = nil
        } else if let normalized = MACAddress.normalize(trimmed) {
            current.mac = normalized
        } else {
            return false
        }
        box = current
        current.save()
        return true
    }

    func forgetBox() {
        cancelBoxPairing()
        AndroidTVBox.forget()
        AndroidTVIdentity.reset()
        box = nil
    }
}
