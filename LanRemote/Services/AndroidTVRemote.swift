import Foundation
import Network
import Security

// Network side of the Android TV Remote protocol v2, spoken by the TV Box plugged into the LG.
// The LG NetCast turns its network off in standby, so the only way to switch it on from the phone
// is asking the box to do it over HDMI-CEC (SIMPLINK).
//
// Ports: 6467 = pairing (once, with the code shown on screen), 6466 = remote control.
// Both are TLS with a self-signed client certificate; messages are protobuf, each one prefixed
// by its length as a varint.

// MARK: - TLS channel with length-prefixed messages

final class TLSChannel {
    private let host: String
    private let port: UInt16
    private let identity: SecIdentity
    private let queue = DispatchQueue(label: "androidtv.tls")
    private var connection: NWConnection?
    private var buffer = Data()
    private(set) var serverCertificate: SecCertificate?

    init(host: String, port: UInt16, identity: SecIdentity) {
        self.host = host
        self.port = port
        self.identity = identity
    }

    func open(timeout: TimeInterval = 6) async throws {
        let tls = NWProtocolTLS.Options()
        let options = tls.securityProtocolOptions
        if let localIdentity = sec_identity_create(identity) {
            sec_protocol_options_set_local_identity(options, localIdentity)
        }
        // The box uses a self-signed certificate; trust comes from pairing, not from a CA.
        sec_protocol_options_set_verify_block(options, { [weak self] _, trust, complete in
            let secTrust = sec_trust_copy_ref(trust).takeRetainedValue()
            self?.serverCertificate = (SecTrustCopyCertificateChain(secTrust) as? [SecCertificate])?.first
            complete(true)
        }, queue)
        let tcp = NWProtocolTCP.Options()
        tcp.connectionTimeout = Int(timeout)
        let connection = NWConnection(host: NWEndpoint.Host(host), port: NWEndpoint.Port(rawValue: port)!,
                                      using: NWParameters(tls: tls, tcp: tcp))
        self.connection = connection

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            var finished = false
            func finish(_ result: Result<Void, Error>) {   // always called on `queue`
                guard !finished else { return }
                finished = true
                connection.stateUpdateHandler = nil
                if case .failure = result { connection.cancel() }
                continuation.resume(with: result)
            }
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready: finish(.success(()))
                case .waiting(.tls), .failed(.tls):
                    finish(.failure(AndroidTVError.secureChannel))
                case .waiting(let error), .failed(let error):
                    finish(.failure(AndroidTVError.connection(Self.describe(error))))
                case .cancelled: finish(.failure(AndroidTVError.connection("conexão cancelada")))
                default: break
                }
            }
            connection.start(queue: queue)
            queue.asyncAfter(deadline: .now() + timeout) { finish(.failure(AndroidTVError.timeout)) }
        }
    }

    func send(_ payload: Data) async throws {
        guard let connection else { throw AndroidTVError.connection("canal fechado") }
        let data = ProtoWriter.framed(payload)
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connection.send(content: data, completion: .contentProcessed { error in
                if let error {
                    continuation.resume(throwing: AndroidTVError.connection(Self.describe(error)))
                } else {
                    continuation.resume()
                }
            })
        }
    }

    /// Next complete message, waiting at most `timeout` seconds.
    func receive(timeout: TimeInterval = 8) async throws -> Data {
        let deadline = Date().addingTimeInterval(timeout)
        while true {
            if let message = takeMessage() { return message }
            let remaining = deadline.timeIntervalSinceNow
            guard remaining > 0 else { throw AndroidTVError.timeout }
            buffer.append(try await receiveChunk(timeout: remaining))
        }
    }

    func close() {
        connection?.cancel()
        connection = nil
    }

    private func takeMessage() -> Data? {
        var length = 0
        var shift = 0
        var index = buffer.startIndex
        while index < buffer.endIndex, shift < 35 {
            let byte = buffer[index]
            index += 1
            length |= Int(byte & 0x7F) << shift
            if byte & 0x80 == 0 {
                guard buffer.distance(from: index, to: buffer.endIndex) >= length else { return nil }
                let end = index + length
                let message = buffer.subdata(in: index..<end)
                buffer = buffer.subdata(in: end..<buffer.endIndex)
                return message
            }
            shift += 7
        }
        return nil
    }

    private func receiveChunk(timeout: TimeInterval) async throws -> Data {
        guard let connection else { throw AndroidTVError.connection("canal fechado") }
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data, Error>) in
            var finished = false
            func finish(_ result: Result<Data, Error>) {   // always called on `queue`
                guard !finished else { return }
                finished = true
                continuation.resume(with: result)
            }
            connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { data, _, isComplete, error in
                if let data, !data.isEmpty {
                    finish(.success(data))
                } else if case .tls = error {
                    finish(.failure(AndroidTVError.secureChannel))
                } else if let error {
                    finish(.failure(AndroidTVError.connection(Self.describe(error))))
                } else if isComplete {
                    finish(.failure(AndroidTVError.connection("a TV Box encerrou a conexão")))
                } else {
                    finish(.success(Data()))
                }
            }
            queue.asyncAfter(deadline: .now() + timeout) { finish(.failure(AndroidTVError.timeout)) }
        }
    }

    private static func describe(_ error: NWError) -> String {
        switch error {
        case .posix(let code) where code == .ECONNREFUSED: return "conexão recusada"
        case .posix(let code) where code == .EHOSTUNREACH || code == .EHOSTDOWN: return "aparelho fora da rede"
        case .posix(let code) where code == .ETIMEDOUT: return "tempo esgotado"
        case .dns: return "nome não encontrado na rede"
        default: return error.localizedDescription
        }
    }
}

// MARK: - Pairing (port 6467)

/// One pairing attempt: `start()` makes the box show a 6-character code on the TV,
/// `finish(code:)` sends the proof derived from it.
final class AndroidTVPairing {
    private let host: String
    private let identity: SecIdentity
    private var channel: TLSChannel?

    init(host: String) throws {
        self.host = host
        self.identity = try AndroidTVIdentity.load()
    }

    func start() async throws {
        let channel = TLSChannel(host: host, port: 6467, identity: identity)
        try await channel.open()
        self.channel = channel
        try await send { $0.message(10) { request in        // pairing_request
            request.string(1, "atvremote")                  // service_name
            request.string(2, "LanRemote (iPhone)")         // client_name, shown on the TV
        } }
        try await expect(11)                                // pairing_request_ack
        try await send { $0.message(20) { option in          // pairing_option
            option.message(1) { encoding in                  // input_encodings: hexadecimal, 6 symbols
                encoding.int(1, 3)
                encoding.int(2, 6)
            }
            option.int(3, 1)                                 // preferred_role: input
        } }
        try await expect(20)
        try await send { $0.message(30) { configuration in   // pairing_configuration
            configuration.message(1) { encoding in
                encoding.int(1, 3)
                encoding.int(2, 6)
            }
            configuration.int(2, 1)                          // client_role: input
        } }
        try await expect(31)                                // configuration_ack: code is on screen now
    }

    func finish(code: String) async throws {
        guard let parsed = AndroidTVPairingMath.parse(code: code) else { throw AndroidTVError.wrongCode }
        guard let serverCertificate = channel?.serverCertificate else { throw AndroidTVError.connection("canal fechado") }
        let client = try AndroidTVIdentity.rsaComponents(try AndroidTVIdentity.certificate(of: identity))
        let server = try AndroidTVIdentity.rsaComponents(serverCertificate)
        let secret = AndroidTVPairingMath.secret(client: client, server: server, nonce: parsed.nonce)
        // The first byte of the code is a checksum of the rest: catches typos before the box does.
        guard secret.first == parsed.checksum else { throw AndroidTVError.wrongCode }
        try await send { $0.message(40) { $0.bytes(1, secret) } }   // pairing_secret
        try await expect(41)                                         // secret_ack
        cancel()
    }

    func cancel() {
        channel?.close()
        channel = nil
    }

    private func send(_ build: (inout ProtoWriter) -> Void) async throws {
        guard let channel else { throw AndroidTVError.connection("canal fechado") }
        var message = ProtoWriter()
        message.int(1, 2)      // protocol_version
        message.int(2, 200)    // status: OK
        build(&message)
        try await channel.send(message.data)
    }

    private func expect(_ field: Int) async throws {
        guard let channel else { throw AndroidTVError.connection("canal fechado") }
        let reply = try ProtoMessage(await channel.receive())
        switch reply.int(2) {
        case 200: break
        case 402: throw AndroidTVError.wrongCode
        case let status: throw AndroidTVError.rejected("status \(status)")
        }
        guard reply.has(field) else { throw AndroidTVError.rejected("resposta inesperada") }
    }
}

// MARK: - Remote control (port 6466)

enum AndroidTVRemote {
    /// Connects, completes the handshake and presses `keys` in order. Returns whether the box
    /// reported its screen as on before the keys were sent (nil if it didn't say).
    @discardableResult
    static func press(_ keys: [AndroidKey], host: String) async throws -> Bool? {
        try await press(codes: keys.map(\.rawValue), host: host)
    }

    /// Same as `press(_:host:)` with raw Android key codes.
    @discardableResult
    static func press(codes keys: [Int], host: String) async throws -> Bool? {
        let identity = try AndroidTVIdentity.load()
        let channel = TLSChannel(host: host, port: 6466, identity: identity)
        do {
            try await channel.open()
        } catch AndroidTVError.secureChannel {
            throw AndroidTVError.notPaired
        }
        defer { channel.close() }

        // Handshake: the box sends remote_configure and remote_set_active and waits for our echo.
        // Right after it, it usually says whether its screen is on (remote_start).
        var configured = false
        var active = false
        var screenOn: Bool?
        let handshakeDeadline = Date().addingTimeInterval(8)
        var settleDeadline: Date?
        while true {
            if configured && active {
                let settle = settleDeadline ?? Date().addingTimeInterval(1)
                settleDeadline = settle
                if screenOn != nil || Date() >= settle { break }
            }
            let remaining = (settleDeadline ?? handshakeDeadline).timeIntervalSinceNow
            guard remaining > 0 else { throw AndroidTVError.timeout }
            let raw: Data
            do {
                raw = try await channel.receive(timeout: remaining)
            } catch AndroidTVError.timeout where settleDeadline != nil {
                break
            } catch AndroidTVError.secureChannel {
                throw AndroidTVError.notPaired
            } catch AndroidTVError.connection where !configured {
                throw AndroidTVError.notPaired   // the box drops unknown certificates right away
            }
            let message = try ProtoMessage(raw)
            if message.has(1) {                                // remote_configure
                try await send(channel) { $0.message(1) { configure in
                    configure.int(1, 622)                          // features: key, ime, power, volume, app link
                    configure.message(2) { info in
                        info.string(1, "iPhone")
                        info.string(2, "Apple")
                        info.int(3, 1)
                        info.string(4, "1")
                        info.string(5, "lanremote")
                        info.string(6, "1.0.0")
                    }
                } }
                configured = true
            } else if message.has(2) {                         // remote_set_active
                try await send(channel) { $0.message(2) { $0.int(1, 622) } }
                active = true
            } else if let ping = message.message(8) {          // remote_ping_request
                try await send(channel) { $0.message(9) { $0.int(1, ping.int(1)) } }
            } else if message.has(40) {                        // remote_start
                screenOn = message.message(40)?.int(1) == 1
            } else if message.has(3) {                         // remote_error
                throw AndroidTVError.rejected("erro remoto")
            }
        }

        for key in keys {
            try await send(channel) { $0.message(10) { inject in   // remote_key_inject
                inject.int(1, key)
                inject.int(2, 3)                                   // direction: short press
            } }
            try await Task.sleep(nanoseconds: 300_000_000)
        }
        return screenOn
    }

    /// Switches the TV on through the box. Waking the box makes Android TV send HDMI-CEC
    /// "One Touch Play", which turns the TV on and selects the box's input. (KEYCODE_TV_POWER would
    /// be the direct way, but the Xiaomi box ignores it, and KEYCODE_WAKEUP doesn't wake it.)
    ///
    /// A few seconds after the TV goes to standby the box follows it into sleep and closes the
    /// remote service. Wake-on-LAN brings its network back for a few seconds (the port answers in
    /// about 1 s), which is enough to press POWER. Magic packets are re-sent while polling so that
    /// even if the first packet only triggers ARP resolution on a cold ARP cache, the next packet
    /// goes straight through once the box answers ARP in "Sempre conectado" mode.
    static func switchTVOn(host: String, wakeMACs: [String]) async throws {
        await WakeOnLAN.send(macs: wakeMACs, to: host)
        guard await waitUntilReachable(host, wakeMACs: wakeMACs, timeout: wakeMACs.isEmpty ? 5 : 10) else {
            throw AndroidTVError.asleep
        }
        if try await press(codes: [], host: host) == true {
            // Box awake while the TV is off: only a fresh wake-up sends One Touch Play, so put it
            // to sleep first and wake it again.
            try await press([.power], host: host)
            try await Task.sleep(nanoseconds: 3_000_000_000)
            await WakeOnLAN.send(macs: wakeMACs, to: host)
            _ = await waitUntilReachable(host, wakeMACs: wakeMACs, timeout: 12)
        }
        try await press([.power], host: host)
    }

    /// Polls the remote port until the box accepts TCP connections, re-sending Wake-on-LAN on each
    /// miss so a cold ARP cache that resolves after the first probe still receives the magic packet.
    static func waitUntilReachable(_ host: String, wakeMACs: [String] = [], timeout: TimeInterval) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if await accepts(host, port: 6466, within: 0.6) { return true }
            if !wakeMACs.isEmpty {
                await WakeOnLAN.send(macs: wakeMACs, to: host)
            }
            try? await Task.sleep(nanoseconds: 300_000_000)
        }
        return false
    }

    private static func accepts(_ host: String, port: UInt16, within timeout: TimeInterval) async -> Bool {
        let connection = NWConnection(host: NWEndpoint.Host(host), port: NWEndpoint.Port(rawValue: port)!, using: .tcp)
        let queue = DispatchQueue(label: "androidtv.probe")
        return await withCheckedContinuation { continuation in
            var finished = false
            func finish(_ open: Bool) {   // always called on `queue`
                guard !finished else { return }
                finished = true
                connection.cancel()
                continuation.resume(returning: open)
            }
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready: finish(true)
                case .waiting, .failed, .cancelled: finish(false)
                default: break
                }
            }
            connection.start(queue: queue)
            queue.asyncAfter(deadline: .now() + timeout) { finish(false) }
        }
    }

    private static func send(_ channel: TLSChannel, _ build: (inout ProtoWriter) -> Void) async throws {
        var message = ProtoWriter()
        build(&message)
        try await channel.send(message.data)
    }
}

// MARK: - Wake-on-LAN over UDP

extension WakeOnLAN {
    /// Sends magic packets for each MAC to `host` (unicast + best-effort subnet/limited broadcast).
    static func send(macs: [String], to host: String) async {
        let packets = macs.compactMap { magicPacket(mac: $0) }
        guard !packets.isEmpty else { return }
        sendPOSIX(packets: packets, host: host)
        for packet in packets {
            for port: UInt16 in [9, 7] {
                await sendUDP(packet, host: host, port: port)
            }
        }
    }

    /// Best-effort BSD UDP send to unicast, /24 broadcast and 255.255.255.255. On platforms or
    /// entitlements where broadcast is restricted, the kernel ignores those targets and unicast still runs.
    private static func sendPOSIX(packets: [Data], host: String) {
        let fd = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        guard fd >= 0 else { return }
        defer { Darwin.close(fd) }
        var yes: Int32 = 1
        _ = setsockopt(fd, SOL_SOCKET, SO_BROADCAST, &yes, socklen_t(MemoryLayout<Int32>.size))

        let targets = Self.targets(for: host)
        for packet in packets {
            for target in targets {
                for port: UInt16 in [9, 7] {
                    var destination = sockaddr_in()
                    destination.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
                    destination.sin_family = sa_family_t(AF_INET)
                    destination.sin_port = port.bigEndian
                    guard inet_pton(AF_INET, target, &destination.sin_addr) == 1 else { continue }
                    packet.withUnsafeBytes { bytes in
                        withUnsafePointer(to: &destination) { pointer in
                            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                                _ = sendto(fd, bytes.baseAddress, bytes.count, 0, $0,
                                           socklen_t(MemoryLayout<sockaddr_in>.size))
                            }
                        }
                    }
                }
            }
        }
    }

    private static func sendUDP(_ data: Data, host: String, port: UInt16) async {
        let connection = NWConnection(host: NWEndpoint.Host(host), port: NWEndpoint.Port(rawValue: port)!, using: .udp)
        let queue = DispatchQueue(label: "wol.udp")
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            var finished = false
            func finish() {   // always called on `queue`
                guard !finished else { return }
                finished = true
                connection.cancel()
                continuation.resume()
            }
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    connection.send(content: data, completion: .contentProcessed { _ in finish() })
                case .waiting, .failed, .cancelled:
                    finish()
                default: break
                }
            }
            connection.start(queue: queue)
            queue.asyncAfter(deadline: .now() + 2) { finish() }
        }
    }
}
