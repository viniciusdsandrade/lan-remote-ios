import Foundation

// MARK: - TV Configuration Model

struct TVConfig: Codable, Equatable, Sendable {
    var host: String
    var port: Int
    var protocolType: String
    var model: String?
    var name: String?
    var pairingKey: String?
    var session: String?
    var mac: String?
    
    enum CodingKeys: String, CodingKey {
        case host
        case port
        case protocolType = "protocol"
        case model
        case name
        case pairingKey = "pairing_key"
        case session
        case mac
    }
    
    static let defaultsKey = "com.lanremote.ios.config"
    
    static var `default`: TVConfig {
        TVConfig(
            host: "192.168.1.100",
            port: 8080,
            protocolType: "roap",
            model: "47LN5700-SA_11",
            name: "[TV][LG]47LN5700-SA",
            pairingKey: "123456",
            session: "123456789",
            mac: "0a:03:0b:0c:0d:05"
        )
    }
    
    static func load() -> TVConfig {
        if let data = UserDefaults.standard.data(forKey: defaultsKey),
           let config = try? JSONDecoder().decode(TVConfig.self, from: data) {
            return config
        }
        return .default
    }
    
    func save() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: Self.defaultsKey)
        }
    }
}
