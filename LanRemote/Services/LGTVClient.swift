import Foundation
import Combine
import UIKit

// MARK: - LG TV ROAP Client for iOS

@MainActor
final class LGTVClient: ObservableObject {
    @Published var config: TVConfig
    @Published var isConnected: Bool = false
    @Published var isMuted: Bool = false
    @Published var volumeLevel: Int = 10
    @Published var inputSourceName: String = "---"
    @Published var channelMajor: String = ""
    @Published var statusMessage: String = "Pronto"
    @Published var lastSentKey: String = ""
    @Published var isSending: Bool = false
    @Published var isRefreshing: Bool = false
    
    private var pollTimer: Timer?
    private var lastSendTime: DispatchTime = .now()
    private let minGapSeconds: Double = 0.30
    
    init(config: TVConfig? = nil) {
        self.config = config ?? TVConfig.load()
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
        config.host = newHost.trimmingCharacters(in: .whitespacesAndNewlines)
        config.port = port
        saveConfig()
        Task {
            await refreshStatus()
        }
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
        
        // Critical: LG 47LN5700 fw 05.02.11 requirement:
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
        let code = key.rawValue
        let label = key.label
        lastSentKey = label
        statusMessage = "Enviando \(label)..."
        isSending = true
        
        // Trigger specific haptic feedback based on key type
        triggerHaptic(for: key)
        
        Task { [weak self] in
            guard let self = self else { return }
            
            // Debounce timing: Ensure min gap between key transmissions to avoid TV packet drop
            let now = DispatchTime.now()
            let elapsed = Double(now.uptimeNanoseconds - self.lastSendTime.uptimeNanoseconds) / 1_000_000_000.0
            if elapsed < self.minGapSeconds {
                let waitNanos = UInt64((self.minGapSeconds - elapsed) * 1_000_000_000)
                try? await Task.sleep(nanoseconds: waitNanos)
            }
            self.lastSendTime = DispatchTime.now()
            
            await self.performSendKey(code: code, label: label)
        }
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
    
    private func performSendKey(code: Int, label: String, retryCount: Int = 0) async {
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
        
        guard let req = createRequest(path: path, method: "POST", body: xml) else {
            self.statusMessage = "URL inválida"
            self.isSending = false
            return
        }
        
        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            if let httpResp = resp as? HTTPURLResponse {
                if httpResp.statusCode == 200 {
                    self.isConnected = true
                    self.statusMessage = "\(label) enviado"
                    self.isSending = false
                    
                    // Trigger status refresh shortly after volume/channel commands
                    if code == TVKey.volumeUp.rawValue || code == TVKey.volumeDown.rawValue || code == TVKey.mute.rawValue {
                        try? await Task.sleep(nanoseconds: 350_000_000)
                        await self.refreshStatus()
                    }
                    return
                } else if httpResp.statusCode == 401 && retryCount == 0 {
                    // Session expired or unauthenticated; attempt re-pairing
                    self.statusMessage = "Re-autenticando com a TV..."
                    let success = await self.pairWithSavedKey()
                    if success {
                        await self.performSendKey(code: code, label: label, retryCount: 1)
                        return
                    }
                } else {
                    let respStr = String(data: data, encoding: .utf8) ?? ""
                    self.statusMessage = "Erro TV (HTTP \(httpResp.statusCode)): \(respStr)"
                }
            }
        } catch {
            self.isConnected = false
            self.statusMessage = "Sem conexão (\(error.localizedDescription))"
        }
        self.isSending = false
    }
    
    // MARK: - Status Queries
    
    func refreshStatus() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        
        let session = config.session ?? ""
        let basePath = config.protocolType == "udap" ? "/udap/api/data" : "/roap/api/data"
        let volPath = "\(basePath)?target=volume_info&session=\(session)"
        
        if let volReq = createRequest(path: volPath) {
            do {
                let (data, resp) = try await URLSession.shared.data(for: volReq)
                if let httpResp = resp as? HTTPURLResponse, httpResp.statusCode == 200 {
                    self.isConnected = true
                    if let str = String(data: data, encoding: .utf8) {
                        if let muteVal = Self.extractXMLTag(from: str, tag: "mute") {
                            self.isMuted = (muteVal.lowercased() == "true")
                        }
                        if let lvlVal = Self.extractXMLTag(from: str, tag: "level"), let lvl = Int(lvlVal) {
                            self.volumeLevel = lvl
                        }
                    }
                } else if let httpResp = resp as? HTTPURLResponse, httpResp.statusCode == 401 {
                    _ = await self.pairWithSavedKey()
                }
            } catch {
                self.isConnected = false
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
    
    func confirmPairing(key: String) async -> (success: Bool, message: String) {
        let cleanKey = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard cleanKey.count >= 6 else {
            HapticManager.shared.warning()
            return (false, "Chave deve conter 6 dígitos.")
        }
        
        let path = config.protocolType == "udap" ? "/udap/api/pairing" : "/roap/api/auth"
        let xml: String
        if config.protocolType == "udap" {
            xml = "<?xml version=\"1.0\" encoding=\"utf-8\"?><envelope><api type=\"pairing\"><name>hello</name><value>\(cleanKey)</value><port>\(config.port)</port></api></envelope>"
        } else {
            xml = "<?xml version=\"1.0\" encoding=\"utf-8\"?><auth><type>AuthReq</type><value>\(cleanKey)</value></auth>"
        }
        
        guard let req = createRequest(path: path, method: "POST", body: xml) else {
            return (false, "URL inválida")
        }
        
        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            if let httpResp = resp as? HTTPURLResponse {
                if httpResp.statusCode == 200 {
                    self.config.pairingKey = cleanKey
                    if let str = String(data: data, encoding: .utf8) {
                        if let session = Self.extractXMLTag(from: str, tag: "session") {
                            self.config.session = session
                        }
                    }
                    self.saveConfig()
                    self.isConnected = true
                    HapticManager.shared.success()
                    await self.refreshStatus()
                    return (true, "Pareamento concluído com sucesso!")
                } else if httpResp.statusCode == 401 {
                    HapticManager.shared.error()
                    return (false, "Código incorreto! Confira os dígitos na tela da TV.")
                } else {
                    HapticManager.shared.error()
                    return (false, "Erro HTTP \(httpResp.statusCode)")
                }
            }
        } catch {
            HapticManager.shared.error()
            return (false, "Erro de rede: \(error.localizedDescription)")
        }
        return (false, "Erro inesperado")
    }
    
    private func pairWithSavedKey() async -> Bool {
        guard let key = config.pairingKey, !key.isEmpty else { return false }
        let res = await confirmPairing(key: key)
        return res.success
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
