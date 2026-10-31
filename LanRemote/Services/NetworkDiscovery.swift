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

// MARK: - LG TV Discovery & Relocation Engine

enum LGTVDiscovery {
    static let ssdpPort: UInt16 = 1900
    static let bcastPort: UInt16 = 1990
    static let defaultPort: Int = 8080

    /// Search for the TV's DLNA renderer, a server of its own on the TV. Every answer to a UDAP search
    /// (udap:rootservice) puts LG's discovery popup on screen instead: "model_XX", a phone pointing at
    /// the TV and a "Pairing Key" field (UDAP 2.0 spec, "Host screen after discovery response").
    static let dlnaSearch = "M-SEARCH * HTTP/1.1\r\nHOST: 239.255.255.250:1900\r\nMAN: \"ssdp:discover\"\r\nMX: 2\r\nST: urn:schemas-upnp-org:device:MediaRenderer:1\r\nUSER-AGENT: iOS/1.0 UPnP/1.1 lg_roap_control/1.0.0\r\n\r\n"

    /// Quick probe to check if a TV answers HTTP on `host:port`.
    static func probeHost(_ host: String, port: Int = defaultPort, timeout: TimeInterval = 1.0) async -> Bool {
        guard let url = URL(string: "http://\(host):\(port)/roap/api/data?target=volume_info") else { return false }
        var req = URLRequest(url: url)
        req.timeoutInterval = timeout
        req.setValue("Close", forHTTPHeaderField: "Connection")
        req.setValue("lg_roap_control/1.0.0 (iOS)", forHTTPHeaderField: "User-Agent")
        do {
            let (_, resp) = try await URLSession.shared.data(for: req)
            guard let http = resp as? HTTPURLResponse else { return false }
            return http.statusCode == 200 || http.statusCode == 401
        } catch {
            return false
        }
    }

    /// Where the LG TV matching `config` answers without a search: the configured IP (iOS doesn't let
    /// apps read the ARP cache, which the Mac app checks too). A quick probe.
    static func probeKnownHosts(of config: TVConfig) async -> String? {
        let port = config.port > 0 ? config.port : defaultPort
        return await probeHost(config.host, port: port) ? config.host : nil
    }

    /// Locates the LG TV matching `config` by DLNA discovery, or fast subnet sweep.
    /// It runs by itself whenever the TV stops answering, so it never uses the UDAP search.
    static func locate(matching config: TVConfig) async -> String? {
        let port = config.port > 0 ? config.port : defaultPort

        // 1. SSDP DLNA M-SEARCH
        if let host = match(config, in: await search(timeout: 2.0)) {
            return host
        }

        // 2. Fallback subnet sweep (if SSDP was blocked by Wi-Fi AP isolation or multicast filter)
        let prefix = detectSubnetPrefix(from: config.host) ?? "192.168.1"
        if let sweepMatch = await quickSubnetSweep(prefix: prefix, port: port) {
            return sweepMatch
        }

        return nil
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

    /// Fast parallel check across common host range on subnet.
    static func quickSubnetSweep(prefix: String, port: Int = defaultPort) async -> String? {
        // Sweep common DHCP range first (2 to 50, then 51 to 254)
        let priorityHosts = (2...50).map { "\(prefix).\($0)" }
        let remainingHosts = (51...254).map { "\(prefix).\($0)" }

        for batch in [priorityHosts, remainingHosts] {
            let found: String? = await withTaskGroup(of: String?.self) { group -> String? in
                for host in batch {
                    group.addTask {
                        if await probeHost(host, port: port, timeout: 0.6) {
                            return host
                        }
                        return nil
                    }
                }
                for await result in group {
                    if let result = result {
                        group.cancelAll()
                        return result
                    }
                }
                return nil
            }
            if let found = found {
                return found
            }
        }
        return nil
    }

    /// Sends the SSDP searches (DLNA, or with `udap` M-SEARCH and B-SEARCH) and collects sender IP addresses.
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
            sendUDP(payload: msearchRootservice, to: "239.255.255.250", port: ssdpPort, fd: fd)
            sendUDP(payload: bsearchRootservice, to: "255.255.255.255", port: bcastPort, fd: fd)
        } else {
            sendUDP(payload: dlnaSearch, to: "239.255.255.250", port: ssdpPort, fd: fd)
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

    private static func sendUDP(payload: String, to host: String, port: UInt16, fd: Int32) {
        guard let data = payload.data(using: .utf8) else { return }
        var dest = sockaddr_in()
        dest.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        dest.sin_family = sa_family_t(AF_INET)
        dest.sin_port = port.bigEndian
        guard inet_pton(AF_INET, host, &dest.sin_addr) == 1 else { return }

        _ = data.withUnsafeBytes { bytes in
            withUnsafePointer(to: &dest) { ptr in
                ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                    sendto(fd, bytes.baseAddress, bytes.count, 0, sa, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
        }
    }

    /// Fetches details from rootservice.xml (with `udap`) or volume_info on the candidate IP.
    static func inspectTV(host: String, port: Int = defaultPort, udap: Bool) async -> DiscoveredTV? {
        // Try rootservice.xml with UDAP/2.0 User-Agent
        if udap, let url = URL(string: "http://\(host):\(port)/udap/api/data?target=rootservice.xml") {
            var req = URLRequest(url: url)
            req.timeoutInterval = 1.2
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
        if await probeHost(host, port: port, timeout: 1.0) {
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

    static func detectSubnetPrefix(from host: String) -> String? {
        let parts = host.split(separator: ".")
        if parts.count == 4 {
            return "\(parts[0]).\(parts[1]).\(parts[2])"
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

    func startScan(targetSubnet: String? = nil) {
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

            // 3. Fallback subnet sweep
            let subnet = targetSubnet ?? LGTVDiscovery.detectSubnetPrefix(from: current.host) ?? "192.168.1"
            await self.scanSubnet(subnet)

            self.isScanning = false
            self.scanProgress = 1.0
            if self.discoveredDevices.isEmpty {
                self.statusText = "Nenhuma TV encontrada automaticamente. Insira o IP manualmente."
            } else {
                self.statusText = "\(self.discoveredDevices.count) TV(s) encontrada(s)"
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

    private func scanSubnet(_ subnetPrefix: String) async {
        let totalHosts = 254
        let batchSize = 25

        for batchStart in stride(from: 1, to: totalHosts, by: batchSize) {
            if Task.isCancelled { break }
            let batchEnd = min(batchStart + batchSize - 1, totalHosts)

            await withTaskGroup(of: DiscoveredTV?.self) { group in
                for i in batchStart...batchEnd {
                    let host = "\(subnetPrefix).\(i)"
                    if self.discoveredDevices.contains(where: { $0.ip == host }) {
                        continue
                    }
                    group.addTask {
                        return await LGTVDiscovery.inspectTV(host: host, port: 8080, udap: true)
                    }
                }

                for await device in group {
                    if let device = device {
                        self.addDevice(device)
                    }
                }
            }

            self.scanProgress = Double(batchEnd) / Double(totalHosts)
            self.statusText = "Varrendo \(subnetPrefix).x (\(batchEnd)/\(totalHosts))..."
        }
    }
}
