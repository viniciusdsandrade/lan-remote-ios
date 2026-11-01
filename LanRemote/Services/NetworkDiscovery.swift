import Foundation
import Network
import Combine
import Darwin

// MARK: - Discovered TV Model

struct DiscoveredTV: Identifiable, Equatable, Hashable, Sendable {
    var id: String { "\(ip):\(port)" }
    let ip: String
    let port: Int
    let model: String
    let name: String
    let protocolType: String
    let uuid: String?

    init(ip: String, port: Int, model: String, name: String, protocolType: String, uuid: String? = nil) {
        self.ip = ip
        self.port = port
        self.model = model
        self.name = name
        self.protocolType = protocolType
        self.uuid = uuid
    }
}

// MARK: - The iPhone's own network

/// An IPv4 network this device is on through Wi-Fi or Ethernet (`en*`), read with getifaddrs.
/// Addresses are in host byte order.
struct LocalIPv4Network: Equatable, Sendable {
    let interface: String
    let address: UInt32
    let netmask: UInt32

    init(interface: String, address: UInt32, netmask: UInt32) {
        self.interface = interface
        self.address = address
        self.netmask = netmask
    }

    /// Parses dotted quads, as in tests: `LocalIPv4Network("en0", "192.0.2.5", "255.255.255.0")`.
    init?(_ interface: String, _ address: String, _ netmask: String) {
        guard let address = LGTVDiscovery.ipv4Value(address),
              let netmask = LGTVDiscovery.ipv4Value(netmask) else { return nil }
        self.init(interface: interface, address: address, netmask: netmask)
    }

    var prefixLength: Int { netmask.nonzeroBitCount }
}

/// Why the app can't reach anything on the LAN, whatever the TV is doing.
enum NetworkBlock: Equatable, Sendable {
    /// The iPhone has no IPv4 address on Wi-Fi (or Ethernet): off Wi-Fi, or only on cellular.
    case offWiFi
    /// iOS refuses the app local network access (Settings › Privacy & Security › Local Network).
    case localNetworkDenied
}

// MARK: - LG TV Discovery & Relocation Engine

enum LGTVDiscovery {
    static let ssdpPort: UInt16 = 1900
    static let bcastPort: UInt16 = 1990
    static let defaultPort: Int = 8080

    /// Search for the TV's DLNA renderer, a server of its own on the TV. Every answer to a UDAP search
    /// (udap:rootservice) puts LG's discovery popup on screen instead: "model_XX", a phone pointing at
    /// the TV and a "Pairing Key" field (UDAP 2.0 spec, "Host screen after discovery response").
    static let dlnaSearch = "M-SEARCH * HTTP/1.1\r\nHOST: 239.255.255.250:1900\r\nMAN: \"ssdp:discover\"\r\nMX: 2\r\nST: urn:schemas-upnp-org:device:MediaRenderer:1\r\nUSER-AGENT: iOS/1.0 UPnP/1.1 lg_roap_control/1.0.0\r\n\r\n"

    /// Ports that LG NetCast TVs never open (their firewall drops SYNs there), whereas routers,
    /// access points, computers and phones commonly listen on at least one of them.
    private static let foreignServicePorts: [UInt16] = [80, 443, 22, 53, 445, 62078]

    /// Quick probe to check if a TV answers HTTP ROAP on `host:port`.
    static func probeHost(_ host: String, port: Int = defaultPort, timeout: TimeInterval = 1.0) async -> Bool {
        guard let url = URL(string: "http://\(host):\(port)/roap/api/data?target=volume_info") else { return false }
        var req = URLRequest(url: url)
        req.timeoutInterval = timeout
        req.setValue("Close", forHTTPHeaderField: "Connection")
        req.setValue("lg_roap_control/1.0.0 (iOS)", forHTTPHeaderField: "User-Agent")
        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            guard let http = resp as? HTTPURLResponse else { return false }
            if http.statusCode == 401 { return true }
            guard http.statusCode == 200 else { return false }
            if data.isEmpty { return true }
            let body = String(data: data, encoding: .utf8) ?? ""
            return body.localizedCaseInsensitiveContains("ROAP")
                || body.localizedCaseInsensitiveContains("<envelope")
                || body.localizedCaseInsensitiveContains("<level>")
        } catch {
            return false
        }
    }

    /// Whether `host` answers an unprivileged ICMP Echo Request within `timeout`.
    /// In standby the NetCast TV powers its network interface down, so a ping reply tells an awake
    /// host whose HTTP port 8080 timed out apart from standby.
    static func answersPing(_ host: String, timeout: TimeInterval = 1.0) async -> Bool {
        await Task.detached(priority: .utility) {
            sendICMPPing(host: host, timeout: timeout)
        }.value
    }

    /// Whether `host` accepts TCP connections on non-TV ports (such as HTTP 80/443 on an AP or router).
    /// Since iOS apps cannot read the kernel ARP MAC table, an open non-TV service at the TV's IP
    /// tells a LAN IP conflict (or a DHCP lease reassigned while the TV was off) apart from the TV.
    static func hasForeignService(_ host: String, timeout: TimeInterval = 0.45) async -> Bool {
        await Task.detached(priority: .utility) {
            probeAnyTCPPort(host: host, ports: foreignServicePorts, timeout: timeout)
        }.value
    }

    private static func sendICMPPing(host: String, timeout: TimeInterval) -> Bool {
        var dest = sockaddr_in()
        dest.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        dest.sin_family = sa_family_t(AF_INET)
        guard inet_pton(AF_INET, host, &dest.sin_addr) == 1 else { return false }

        let fd = socket(AF_INET, SOCK_DGRAM, IPPROTO_ICMP)
        guard fd >= 0 else { return false }
        defer { Darwin.close(fd) }

        let ident = UInt16.random(in: 1...UInt16.max)
        let seq: UInt16 = 1
        let payload: [UInt8] = (0..<8).map { _ in UInt8.random(in: 0...255) }
        var packet = [UInt8](repeating: 0, count: 8 + payload.count)
        packet[0] = 8 // ICMP_ECHO
        packet[1] = 0
        packet[4] = UInt8(ident >> 8)
        packet[5] = UInt8(ident & 0xFF)
        packet[6] = UInt8(seq >> 8)
        packet[7] = UInt8(seq & 0xFF)
        for (idx, byte) in payload.enumerated() {
            packet[8 + idx] = byte
        }

        var sum: UInt32 = 0
        var idx = 0
        while idx + 1 < packet.count {
            sum &+= (UInt32(packet[idx]) << 8) | UInt32(packet[idx + 1])
            idx += 2
        }
        if idx < packet.count {
            sum &+= UInt32(packet[idx]) << 8
        }
        while (sum >> 16) != 0 {
            sum = (sum & 0xFFFF) &+ (sum >> 16)
        }
        let checksum = ~UInt16(sum & 0xFFFF)
        packet[2] = UInt8(checksum >> 8)
        packet[3] = UInt8(checksum & 0xFF)

        let sent = packet.withUnsafeBytes { bytes in
            withUnsafePointer(to: &dest) { ptr in
                ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                    sendto(fd, bytes.baseAddress, bytes.count, 0, sa, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
        }
        guard sent == packet.count else { return false }

        var buffer = [UInt8](repeating: 0, count: 256)
        let deadline = Date().addingTimeInterval(timeout)
        while true {
            let remaining = deadline.timeIntervalSinceNow
            guard remaining > 0 else { return false }

            var pfd = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
            let ready = poll(&pfd, 1, Int32(ceil(remaining * 1000)))
            if ready < 0 && errno == EINTR { continue }
            guard ready > 0 else { return false }

            var sender = sockaddr_in()
            var len = socklen_t(MemoryLayout<sockaddr_in>.size)
            let count = withUnsafeMutablePointer(to: &sender) { ptr in
                ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                    recvfrom(fd, &buffer, buffer.count, 0, sa, &len)
                }
            }
            guard count >= 8 + payload.count,
                  sender.sin_addr.s_addr == dest.sin_addr.s_addr else { continue }

            let icmpOffset: Int
            if (buffer[0] >> 4) == 4 {
                let ihl = Int(buffer[0] & 0x0F) * 4
                guard ihl >= 20, count >= ihl + 8 + payload.count else { continue }
                icmpOffset = ihl
            } else {
                icmpOffset = 0
            }

            let replyType = buffer[icmpOffset]
            let replyCode = buffer[icmpOffset + 1]
            let replySeq = (UInt16(buffer[icmpOffset + 6]) << 8) | UInt16(buffer[icmpOffset + 7])
            guard replyType == 0, replyCode == 0, replySeq == seq else { continue }
            if Array(buffer[(icmpOffset + 8)..<(icmpOffset + 8 + payload.count)]) == payload {
                return true
            }
        }
    }

    private static func probeAnyTCPPort(host: String, ports: [UInt16], timeout: TimeInterval) -> Bool {
        var baseAddr = sockaddr_in()
        baseAddr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        baseAddr.sin_family = sa_family_t(AF_INET)
        guard inet_pton(AF_INET, host, &baseAddr.sin_addr) == 1 else { return false }

        var openFds: [Int32] = []
        defer {
            for fd in openFds { Darwin.close(fd) }
        }

        for port in ports {
            let fd = socket(AF_INET, SOCK_STREAM, IPPROTO_TCP)
            guard fd >= 0 else { continue }
            let flags = fcntl(fd, F_GETFL, 0)
            _ = fcntl(fd, F_SETFL, flags | O_NONBLOCK)

            var addr = baseAddr
            addr.sin_port = port.bigEndian
            let rc = withUnsafePointer(to: &addr) { ptr in
                ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                    Darwin.connect(fd, sa, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
            if rc == 0 {
                Darwin.close(fd)
                return true
            }
            if errno == EINPROGRESS {
                openFds.append(fd)
            } else {
                Darwin.close(fd)
            }
        }

        let deadline = Date().addingTimeInterval(timeout)
        while !openFds.isEmpty {
            let remaining = deadline.timeIntervalSinceNow
            guard remaining > 0 else { return false }

            var pfds = openFds.map { pollfd(fd: $0, events: Int16(POLLOUT), revents: 0) }
            let ready = poll(&pfds, nfds_t(pfds.count), Int32(ceil(remaining * 1000)))
            if ready < 0 && errno == EINTR { continue }
            guard ready > 0 else { return false }

            var stillPending: [Int32] = []
            for pfd in pfds {
                if pfd.revents == 0 {
                    stillPending.append(pfd.fd)
                    continue
                }
                var soErr: Int32 = -1
                var soLen = socklen_t(MemoryLayout<Int32>.size)
                if (pfd.revents & Int16(POLLERR | POLLHUP | POLLNVAL)) == 0,
                   getsockopt(pfd.fd, SOL_SOCKET, SO_ERROR, &soErr, &soLen) == 0,
                   soErr == 0 {
                    Darwin.close(pfd.fd)
                    openFds = stillPending + pfds.drop(while: { $0.fd != pfd.fd }).dropFirst().map(\.fd)
                    return true
                }
                Darwin.close(pfd.fd)
            }
            openFds = stillPending
        }
        return false
    }

    /// Where the LG TV matching `config` answers without a search: the configured IP (iOS doesn't let
    /// apps read the ARP cache, which the Mac app checks too). A quick probe.
    static func probeKnownHosts(of config: TVConfig) async -> String? {
        let port = config.port > 0 ? config.port : defaultPort
        return await probeHost(config.host, port: port) ? config.host : nil
    }

    /// Locates the LG TV matching `config` by DLNA discovery, or by sweeping the iPhone's own subnet.
    /// It runs by itself whenever the TV stops answering, so it never uses the UDAP search.
    /// On an iPhone the sweep is what finds the TV: iOS refuses multicast and broadcast to apps without
    /// the multicast entitlement (Apple grants it on request only, never to a free developer account),
    /// so the SSDP search gets no answer there. `ssdp: false` skips it, as tests of the sweep do.
    static func locate(matching config: TVConfig, ssdp: Bool = true) async -> String? {
        let port = config.port > 0 ? config.port : defaultPort

        // 1. SSDP DLNA M-SEARCH
        if ssdp, let host = match(config, in: await search(timeout: 2.0)) {
            return host
        }

        // 2. Sweep of the subnet the iPhone is on (plus the saved IP's /24 when it is another LAN)
        let hosts = sweepHosts(around: config.host, networks: localIPv4Networks())
        for chunk in stride(from: 0, to: hosts.count, by: sweepChunk).map({ Array(hosts[$0..<min($0 + sweepChunk, hosts.count)]) }) {
            let open = await hostsAcceptingTCP(chunk, port: port)
            if let tv = await firstTV(among: open, port: port) {
                return tv
            }
        }
        return nil
    }

    // MARK: Subnet sweep

    /// Sockets connecting at once during a sweep: well under the 256 file descriptors an app gets by default.
    static let sweepChunk = 96
    /// How long a sweep waits for the TCP handshakes of one chunk. The TV's kernel answers the SYN even
    /// while its ROAP server stalls, so this only has to cover Wi-Fi latency and ARP.
    static let sweepConnectTimeout: TimeInterval = 1.2
    /// How long a host that accepted the connection on 8080 has to answer the ROAP probe.
    static let sweepProbeTimeout: TimeInterval = 2.5

    /// The IPv4 networks this device is on through Wi-Fi or Ethernet, with private addresses only
    /// (no cellular, VPN, AWDL, hotspot bridge or link-local address).
    static func localIPv4Networks() -> [LocalIPv4Network] {
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0, let first = head else { return [] }
        defer { freeifaddrs(head) }

        var networks: [LocalIPv4Network] = []
        for pointer in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let entry = pointer.pointee
            let flags = Int32(entry.ifa_flags)
            guard (flags & IFF_UP) != 0, (flags & IFF_RUNNING) != 0, (flags & IFF_LOOPBACK) == 0,
                  let addr = entry.ifa_addr, addr.pointee.sa_family == sa_family_t(AF_INET),
                  let mask = entry.ifa_netmask else { continue }
            let name = String(cString: entry.ifa_name)
            guard name.hasPrefix("en") else { continue }
            let address = addr.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { UInt32(bigEndian: $0.pointee.sin_addr.s_addr) }
            let netmask = mask.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { UInt32(bigEndian: $0.pointee.sin_addr.s_addr) }
            guard isPrivate(address) else { continue }
            let network = LocalIPv4Network(interface: name, address: address, netmask: netmask)
            if !networks.contains(network) { networks.append(network) }
        }
        return networks
    }

    /// The addresses a sweep tries, in order: every host of each network the device is on (the device's
    /// own /24 when the network is wider than /22), then the saved IP's /24 when it is a private network
    /// the device isn't on (a TV behind a second router). Deriving the subnet from the saved IP alone,
    /// as before, swept 192.0.2.x with the factory default and never reached the TV.
    static func sweepHosts(around savedHost: String?, networks: [LocalIPv4Network]) -> [String] {
        var ordered: [UInt32] = []
        var seen = Set<UInt32>()
        var own = Set<UInt32>()
        var covered: [(base: UInt32, mask: UInt32)] = []

        func add(base: UInt32, mask: UInt32) {
            covered.append((base, mask))
            let broadcast = base | ~mask
            guard broadcast > base + 1 else { return }
            for value in (base + 1)..<broadcast where !own.contains(value) && seen.insert(value).inserted {
                ordered.append(value)
            }
        }

        for network in networks { own.insert(network.address) }
        for network in networks {
            let mask: UInt32 = network.prefixLength >= 22 ? network.netmask : 0xFFFF_FF00
            add(base: network.address & mask, mask: mask)
        }
        if let savedHost, let saved = ipv4Value(savedHost), isPrivate(saved),
           !covered.contains(where: { saved & $0.mask == $0.base }) {
            add(base: saved & 0xFFFF_FF00, mask: 0xFFFF_FF00)
        }
        return ordered.map(ipv4String)
    }

    /// The hosts among `hosts` that accept a TCP connection on `port` within `timeout`: non-blocking
    /// connects in parallel, so a whole /24 takes a few seconds even with most addresses unused.
    static func hostsAcceptingTCP(_ hosts: [String], port: Int, timeout: TimeInterval = sweepConnectTimeout) async -> [String] {
        guard let port = UInt16(exactly: port) else { return [] }
        return await Task.detached(priority: .userInitiated) {
            connectScan(hosts, port: port, timeout: timeout)
        }.value
    }

    /// The first of `hosts` that answers the ROAP probe like an LG NetCast TV, probing them in parallel.
    static func firstTV(among hosts: [String], port: Int, timeout: TimeInterval = sweepProbeTimeout) async -> String? {
        guard !hosts.isEmpty else { return nil }
        return await withTaskGroup(of: String?.self) { group -> String? in
            for host in hosts {
                group.addTask { await probeHost(host, port: port, timeout: timeout) ? host : nil }
            }
            for await result in group {
                if let result {
                    group.cancelAll()
                    return result
                }
            }
            return nil
        }
    }

    private static func connectScan(_ hosts: [String], port: UInt16, timeout: TimeInterval) -> [String] {
        var open: [String] = []
        var pending: [(fd: Int32, host: String)] = []
        defer {
            for socketInFlight in pending { Darwin.close(socketInFlight.fd) }
        }

        for host in hosts {
            var addr = sockaddr_in()
            addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
            addr.sin_family = sa_family_t(AF_INET)
            addr.sin_port = port.bigEndian
            guard inet_pton(AF_INET, host, &addr.sin_addr) == 1 else { continue }
            let fd = socket(AF_INET, SOCK_STREAM, IPPROTO_TCP)
            guard fd >= 0 else { continue }
            var on: Int32 = 1
            setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
            _ = fcntl(fd, F_SETFL, fcntl(fd, F_GETFL, 0) | O_NONBLOCK)
            let rc = withUnsafePointer(to: &addr) { ptr in
                ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                    Darwin.connect(fd, sa, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
            if rc == 0 {
                open.append(host)
                Darwin.close(fd)
            } else if errno == EINPROGRESS {
                pending.append((fd, host))
            } else {
                Darwin.close(fd)
            }
        }

        let deadline = Date().addingTimeInterval(timeout)
        while !pending.isEmpty {
            let remaining = deadline.timeIntervalSinceNow
            guard remaining > 0 else { break }
            var pfds = pending.map { pollfd(fd: $0.fd, events: Int16(POLLOUT), revents: 0) }
            let ready = poll(&pfds, nfds_t(pfds.count), Int32(ceil(remaining * 1000)))
            if ready < 0 && errno == EINTR { continue }
            guard ready > 0 else { break }

            var stillPending: [(fd: Int32, host: String)] = []
            for (index, pfd) in pfds.enumerated() {
                guard pfd.revents != 0 else {
                    stillPending.append(pending[index])
                    continue
                }
                var soErr: Int32 = -1
                var soLen = socklen_t(MemoryLayout<Int32>.size)
                if (pfd.revents & Int16(POLLERR | POLLHUP | POLLNVAL)) == 0,
                   getsockopt(pfd.fd, SOL_SOCKET, SO_ERROR, &soErr, &soLen) == 0, soErr == 0 {
                    open.append(pending[index].host)
                }
                Darwin.close(pfd.fd)
            }
            pending = stillPending
        }
        return open
    }

    // MARK: What blocks the LAN

    /// Whether the app can't reach the LAN at all, so a TV that doesn't answer isn't necessarily off:
    /// no Wi-Fi address, or local network access denied by iOS. `host` should be on the LAN (the TV's
    /// IP); otherwise the first address of the iPhone's subnet stands in for it (usually the router).
    /// Denial shows at once as an unsatisfied path; when access is allowed this returns within `timeout`.
    static func networkBlock(near host: String, port: Int = defaultPort, timeout: TimeInterval = 0.5) async -> NetworkBlock? {
        let networks = localIPv4Networks()
        guard let network = networks.first else { return .offWiFi }
        var target = (host: host, port: port)
        if let value = ipv4Value(host), !networks.contains(where: { value & $0.netmask == $0.address & $0.netmask }) {
            let base = network.address & network.netmask
            let guess = base + 1 == network.address ? base + 2 : base + 1
            target = (ipv4String(guess), 80)
        }
        return await isLocalNetworkDenied(host: target.host, port: target.port, timeout: timeout) ? .localNetworkDenied : nil
    }

    static func isLocalNetworkDenied(host: String, port: Int, timeout: TimeInterval) async -> Bool {
        guard let nwPort = NWEndpoint.Port(rawValue: UInt16(clamping: port)) else { return false }
        let connection = NWConnection(host: NWEndpoint.Host(host), port: nwPort, using: .tcp)
        let queue = DispatchQueue(label: "lanremote.localnetwork-check")
        return await withCheckedContinuation { continuation in
            let lock = NSLock()
            var finished = false
            let finish: (Bool) -> Void = { denied in
                let first = lock.withLock { () -> Bool in
                    defer { finished = true }
                    return !finished
                }
                guard first else { return }
                connection.stateUpdateHandler = nil
                connection.cancel()
                continuation.resume(returning: denied)
            }
            let deniedNow: () -> Bool = {
                guard let path = connection.currentPath, path.status != .satisfied else { return false }
                return path.unsatisfiedReason == .localNetworkDenied
            }
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready, .cancelled: finish(false)
                case .waiting, .failed: finish(deniedNow())
                default: break
                }
            }
            connection.start(queue: queue)
            queue.asyncAfter(deadline: .now() + timeout) { finish(deniedNow()) }
        }
    }

    // MARK: IPv4 helpers

    static func ipv4Value(_ text: String) -> UInt32? {
        var addr = in_addr()
        guard inet_pton(AF_INET, text, &addr) == 1 else { return nil }
        return UInt32(bigEndian: addr.s_addr)
    }

    static func ipv4String(_ value: UInt32) -> String {
        "\(value >> 24).\((value >> 16) & 0xFF).\((value >> 8) & 0xFF).\(value & 0xFF)"
    }

    /// RFC 1918 ranges: 10/8, 172.16/12, 192.168/16.
    static func isPrivate(_ value: UInt32) -> Bool {
        (value & 0xFF00_0000) == 0x0A00_0000
            || (value & 0xFFF0_0000) == 0xAC10_0000
            || (value & 0xFFFF_0000) == 0xC0A8_0000
    }

    private static func match(_ config: TVConfig, in found: [DiscoveredTV]) -> String? {
        // Match by Model or Name
        if let model = config.model, !model.isEmpty,
           let match = found.first(where: { $0.model.localizedCaseInsensitiveContains(model) || model.localizedCaseInsensitiveContains($0.model) }) {
            return match.ip
        }
        if let name = config.name, !name.isEmpty,
           let match = found.first(where: { $0.name.localizedCaseInsensitiveContains(name) || name.localizedCaseInsensitiveContains($0.name) }) {
            return match.ip
        }

        // If only one LG NetCast TV was found on the local network, that's our TV
        if found.count == 1 {
            return found[0].ip
        }

        return nil
    }

    /// Searches for LG NetCast TVs on the local network via SSDP: the DLNA renderer search, or with
    /// `udap` the UDAP search in multicast and broadcast (which shows the discovery popup on the TV).
    static func search(timeout: TimeInterval = 2.0, udap: Bool = false) async -> [DiscoveredTV] {
        let candidateIPs = await Task.detached(priority: .userInitiated) {
            discoverCandidates(timeout: timeout, udap: udap)
        }.value

        var results: [DiscoveredTV] = []
        for ip in candidateIPs {
            if let tv = await inspectTV(host: ip, udap: udap) {
                if !results.contains(where: { $0.ip == tv.ip }) {
                    results.append(tv)
                }
            }
        }
        return results
    }

    /// Sends the SSDP searches (DLNA, or with `udap` M-SEARCH and B-SEARCH) and collects sender IP addresses.
    /// When iOS refuses every send (no multicast entitlement: sendto fails with EHOSTUNREACH), no answer
    /// can come, so it returns at once instead of waiting `timeout` for nothing.
    private static func discoverCandidates(timeout: TimeInterval, udap: Bool) -> [String] {
        let fd = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        guard fd >= 0 else { return [] }
        defer { Darwin.close(fd) }

        var yes: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_BROADCAST, &yes, socklen_t(MemoryLayout<Int32>.size))
        var ttl: u_char = 2
        setsockopt(fd, IPPROTO_IP, IP_MULTICAST_TTL, &ttl, socklen_t(MemoryLayout<u_char>.size))

        if udap {
            let msearchRootservice = "M-SEARCH * HTTP/1.1\r\nHOST: 239.255.255.250:1900\r\nMAN: \"ssdp:discover\"\r\nMX: 2\r\nST: udap:rootservice\r\nUSER-AGENT: iOS/1.0 UDAP/2.0 lg_roap_control/1.0.0\r\n\r\n"
            let bsearchRootservice = "B-SEARCH * HTTP/1.1\r\nHOST: 255.255.255.255:1990\r\nMAN: \"ssdp:discover\"\r\nMX: 2\r\nST: udap:rootservice\r\nUSER-AGENT: iOS/1.0 UDAP/2.0 lg_roap_control/1.0.0\r\n\r\n"
            let sentM = sendUDP(payload: msearchRootservice, to: "239.255.255.250", port: ssdpPort, fd: fd)
            let sentB = sendUDP(payload: bsearchRootservice, to: "255.255.255.255", port: bcastPort, fd: fd)
            guard sentM || sentB else { return [] }
        } else {
            guard sendUDP(payload: dlnaSearch, to: "239.255.255.250", port: ssdpPort, fd: fd) else { return [] }
        }

        var foundIPs = Set<String>()
        var buffer = [UInt8](repeating: 0, count: 2048)
        let deadline = Date().addingTimeInterval(timeout)

        while true {
            let remaining = deadline.timeIntervalSinceNow
            guard remaining > 0 else { break }

            var pfd = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
            let ready = poll(&pfd, 1, Int32(remaining * 1000))
            if ready < 0 && errno == EINTR { continue }
            guard ready > 0 else { break }

            var sender = sockaddr_in()
            var len = socklen_t(MemoryLayout<sockaddr_in>.size)
            let count = withUnsafeMutablePointer(to: &sender) { ptr in
                ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                    recvfrom(fd, &buffer, buffer.count, 0, sa, &len)
                }
            }
            guard count > 0 else { continue }

            var text = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
            inet_ntop(AF_INET, &sender.sin_addr, &text, socklen_t(INET_ADDRSTRLEN))
            let ip = String(cString: text)

            let replyStr = String(data: Data(buffer[0..<Int(count)]), encoding: .utf8) ?? ""
            if replyStr.contains("UDAP") || replyStr.contains("LN5700") || replyStr.contains("rootservice") || replyStr.contains("LG Electronics") {
                foundIPs.insert(ip)
            } else if replyStr.contains("HTTP/1.1 200") && (replyStr.contains("udap:rootservice") || replyStr.contains("MediaRenderer")) {
                foundIPs.insert(ip)
            }
        }

        return Array(foundIPs)
    }

    @discardableResult
    private static func sendUDP(payload: String, to host: String, port: UInt16, fd: Int32) -> Bool {
        guard let data = payload.data(using: .utf8) else { return false }
        var dest = sockaddr_in()
        dest.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        dest.sin_family = sa_family_t(AF_INET)
        dest.sin_port = port.bigEndian
        guard inet_pton(AF_INET, host, &dest.sin_addr) == 1 else { return false }

        let sent = data.withUnsafeBytes { bytes in
            withUnsafePointer(to: &dest) { ptr in
                ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                    sendto(fd, bytes.baseAddress, bytes.count, 0, sa, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
        }
        if sent < 0 {
            let code = errno
            NSLog("LG TV: o iOS recusou a busca SSDP para %@ (errno %d); a TV será procurada pela varredura da rede", host, code)
            return false
        }
        return true
    }

    /// Fetches details from rootservice.xml (with `udap`) or volume_info on the candidate IP.
    static func inspectTV(host: String, port: Int = defaultPort, udap: Bool, timeout: TimeInterval = 1.2) async -> DiscoveredTV? {
        // Try rootservice.xml with UDAP/2.0 User-Agent
        if udap, let url = URL(string: "http://\(host):\(port)/udap/api/data?target=rootservice.xml") {
            var req = URLRequest(url: url)
            req.timeoutInterval = timeout
            req.setValue("Close", forHTTPHeaderField: "Connection")
            req.setValue("iOS/1.0 UDAP/2.0 lg_roap_control/1.0.0", forHTTPHeaderField: "User-Agent")
            if let (data, resp) = try? await URLSession.shared.data(for: req),
               (resp as? HTTPURLResponse)?.statusCode == 200,
               let xml = String(data: data, encoding: .utf8) {
                let model = LGTVClient.extractXMLTag(from: xml, tag: "modelName") ?? "LG NetCast TV"
                let name = LGTVClient.extractXMLTag(from: xml, tag: "friendlyName") ?? "LG TV (\(host))"
                let uuid = LGTVClient.extractXMLTag(from: xml, tag: "uuid")
                return DiscoveredTV(
                    ip: host,
                    port: port,
                    model: model,
                    name: name,
                    protocolType: "roap",
                    uuid: uuid
                )
            }
        }

        // Fallback: check if volume_info endpoint exists (returns 200 or 401)
        if await probeHost(host, port: port, timeout: timeout) {
            return DiscoveredTV(
                ip: host,
                port: port,
                model: "LG NetCast TV",
                name: "LG TV (\(host))",
                protocolType: "roap",
                uuid: nil
            )
        }

        return nil
    }
}

// MARK: - Network Discovery Service

@MainActor
final class NetworkDiscovery: ObservableObject {
    @Published var discoveredDevices: [DiscoveredTV] = []
    @Published var isScanning: Bool = false
    @Published var scanProgress: Double = 0.0
    @Published var statusText: String = "Pronto para buscar"

    private var scanTask: Task<Void, Never>?

    func startScan() {
        guard !isScanning else { return }
        isScanning = true
        scanProgress = 0.0
        statusText = "Buscando TVs LG na rede..."
        discoveredDevices.removeAll()

        scanTask = Task { [weak self] in
            guard let self = self else { return }

            // 1. Fast probe: configured TV
            let current = TVConfig.load()
            if let dev = await LGTVDiscovery.inspectTV(host: current.host, port: current.port, udap: true) {
                self.addDevice(dev)
            }

            // 2. Fast SSDP scan (takes ~1.5 - 2s): DLNA first; the UDAP search (M-SEARCH and B-SEARCH
            // broadcast) puts LG's discovery popup on the TV, so it only runs when DLNA found nothing
            self.statusText = "Buscando via SSDP multicast..."
            var ssdpDevices = await LGTVDiscovery.search(timeout: 2.0)
            if ssdpDevices.isEmpty {
                ssdpDevices = await LGTVDiscovery.search(timeout: 2.0, udap: true)
            }
            for dev in ssdpDevices {
                self.addDevice(dev)
            }

            // 3. Sweep of the iPhone's own subnet: on an iPhone the SSDP searches get no answer (no
            // multicast entitlement), so this is what finds the TV
            let hosts = LGTVDiscovery.sweepHosts(around: current.host, networks: LGTVDiscovery.localIPv4Networks())
            await self.scanHosts(hosts)
            if Task.isCancelled { return }

            self.isScanning = false
            self.scanProgress = 1.0
            if !self.discoveredDevices.isEmpty {
                self.statusText = "\(self.discoveredDevices.count) TV(s) encontrada(s)"
            } else {
                switch await LGTVDiscovery.networkBlock(near: current.host, timeout: 1.0) {
                case .offWiFi:
                    self.statusText = "O iPhone está fora do Wi-Fi. Conecte-o à mesma rede da TV e busque de novo."
                case .localNetworkDenied:
                    self.statusText = "O iOS está bloqueando a rede local para o app: em Ajustes › Lan Remote, ligue Rede Local."
                case nil:
                    self.statusText = "Nenhuma TV encontrada automaticamente. Insira o IP manualmente."
                }
            }
        }
    }

    func stopScan() {
        scanTask?.cancel()
        scanTask = nil
        isScanning = false
        statusText = "Busca cancelada"
    }

    private func addDevice(_ device: DiscoveredTV) {
        if !discoveredDevices.contains(where: { $0.ip == device.ip }) {
            discoveredDevices.append(device)
            statusText = "\(discoveredDevices.count) TV(s) encontrada(s)"
        }
    }

    /// Connects to port 8080 on every host (a chunk at a time) and inspects the ones that accept.
    private func scanHosts(_ hosts: [String]) async {
        let port = LGTVDiscovery.defaultPort
        let chunk = LGTVDiscovery.sweepChunk
        var done = 0

        for start in stride(from: 0, to: hosts.count, by: chunk) {
            if Task.isCancelled { break }
            let batch = hosts[start..<min(start + chunk, hosts.count)]
                .filter { host in !self.discoveredDevices.contains(where: { $0.ip == host }) }
            let open = await LGTVDiscovery.hostsAcceptingTCP(batch, port: port)

            await withTaskGroup(of: DiscoveredTV?.self) { group in
                for host in open {
                    group.addTask {
                        await LGTVDiscovery.inspectTV(host: host, port: port, udap: true, timeout: LGTVDiscovery.sweepProbeTimeout)
                    }
                }
                for await device in group {
                    if let device {
                        self.addDevice(device)
                    }
                }
            }

            done = min(start + chunk, hosts.count)
            self.scanProgress = Double(done) / Double(max(hosts.count, 1))
            self.statusText = "Varrendo a rede Wi-Fi (\(done)/\(hosts.count))..."
        }
    }
}
