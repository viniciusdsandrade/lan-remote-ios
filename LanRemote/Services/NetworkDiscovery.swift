import Foundation
import Network
import Combine

// MARK: - Discovered TV Model

struct DiscoveredTV: Identifiable, Equatable, Hashable, Sendable {
    var id: String { "\(ip):\(port)" }
    let ip: String
    let port: Int
    let model: String
    let name: String
    let protocolType: String
}

// MARK: - Network Discovery Service

@MainActor
final class NetworkDiscovery: ObservableObject {
    @Published var discoveredDevices: [DiscoveredTV] = []
    @Published var isScanning: Bool = false
    @Published var scanProgress: Double = 0.0
    @Published var statusText: String = "Pronto para buscar"
    
    private var scanTask: Task<Void, Never>?
    
    // Common subnets for quick scan fallback
    private let commonSubnets = ["192.168.1", "192.168.0", "10.0.0"]
    
    func startScan(targetSubnet: String? = nil) {
        guard !isScanning else { return }
        isScanning = true
        scanProgress = 0.0
        statusText = "Buscando TVs LG na rede..."
        discoveredDevices.removeAll()
        
        scanTask = Task { [weak self] in
            guard let self = self else { return }
            
            // 1. First probe the currently configured TV to verify fast reachability
            let current = TVConfig.load()
            await self.probeHost(current.host, port: current.port)
            
            // 2. Scan priority subnet (e.g. current IP's subnet or 192.168.1)
            let subnet = targetSubnet ?? self.detectSubnetPrefix(from: current.host) ?? "192.168.1"
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
    
    private func detectSubnetPrefix(from host: String) -> String? {
        let parts = host.split(separator: ".")
        if parts.count == 4 {
            return "\(parts[0]).\(parts[1]).\(parts[2])"
        }
        return nil
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
                    group.addTask {
                        return await self.checkIfLGTV(host: host, port: 8080)
                    }
                }
                
                for await device in group {
                    if let device = device {
                        if !self.discoveredDevices.contains(where: { $0.ip == device.ip }) {
                            self.discoveredDevices.append(device)
                        }
                    }
                }
            }
            
            self.scanProgress = Double(batchEnd) / Double(totalHosts)
            self.statusText = "Varrendo \(subnetPrefix).x (\(batchEnd)/\(totalHosts))..."
        }
    }
    
    private func probeHost(_ host: String, port: Int) async {
        if let device = await checkIfLGTV(host: host, port: port) {
            if !self.discoveredDevices.contains(where: { $0.ip == device.ip }) {
                self.discoveredDevices.append(device)
            }
        }
    }
    
    nonisolated private func checkIfLGTV(host: String, port: Int) async -> DiscoveredTV? {
        guard let url = URL(string: "http://\(host):\(port)/roap/api/data?target=version_info") else {
            return nil
        }
        
        var req = URLRequest(url: url)
        req.timeoutInterval = 1.2
        req.setValue("Close", forHTTPHeaderField: "Connection")
        req.setValue("lg_roap_control/1.0.0 (iOS)", forHTTPHeaderField: "User-Agent")
        
        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            if let http = resp as? HTTPURLResponse, (http.statusCode == 200 || http.statusCode == 401) {
                // If 200 or 401, it's definitely an LG NetCast TV responding to ROAP API
                var model = "LG NetCast TV"
                if let str = String(data: data, encoding: .utf8),
                   let parsedModel = LGTVClient.extractXMLTag(from: str, tag: "model_name") {
                    model = parsedModel
                }
                return DiscoveredTV(
                    ip: host,
                    port: port,
                    model: model,
                    name: "LG TV (\(host))",
                    protocolType: "roap"
                )
            }
        } catch {
            // Not reachable
        }
        return nil
    }
}
