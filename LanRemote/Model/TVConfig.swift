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

    /// Starting point before the first pairing: no key, session or MAC ship with the app.
    static var `default`: TVConfig {
        TVConfig(
            host: "192.0.2.100",
            port: 8080,
            protocolType: "roap",
            model: "xxLN5700-SA_11",
            name: "[TV][LG]xxLN5700-SA",
            pairingKey: nil,
            session: nil,
            mac: nil
        )
    }
    
    static func load(from defaults: UserDefaults = .standard) -> TVConfig {
        if let data = defaults.data(forKey: defaultsKey),
           let config = try? JSONDecoder().decode(TVConfig.self, from: data) {
            return config
        }
        if let legacy = legacyConfig(in: defaults) {
            legacy.save(to: defaults)
            return legacy
        }
        return .default
    }

    /// A configuration saved by an older build under another key prefix (installing over an older
    /// bundle id keeps its UserDefaults). Without it the app started from the factory default, with no
    /// pairing key and an IP outside the LAN, and never found the TV. Adopted once: `load` saves it
    /// under `defaultsKey`, so the old key is never read again.
    static func legacyConfig(in defaults: UserDefaults) -> TVConfig? {
        let candidates = defaults.dictionaryRepresentation()
            .filter { $0.key.hasSuffix(".config") && $0.key != defaultsKey }
            .sorted { $0.key < $1.key }
            .compactMap { entry -> TVConfig? in
                guard let data = entry.value as? Data,
                      let config = try? JSONDecoder().decode(TVConfig.self, from: data),
                      !config.host.isEmpty else { return nil }
                return config
            }
        return candidates.first { $0.pairingKey?.isEmpty == false } ?? candidates.first
    }

    func save(to defaults: UserDefaults = .standard) {
        if let data = try? JSONEncoder().encode(self) {
            defaults.set(data, forKey: Self.defaultsKey)
        }
    }
}
