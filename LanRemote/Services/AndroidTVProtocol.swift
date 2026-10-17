import Foundation
import CryptoKit

// Platform-independent pieces of the Android TV Remote protocol v2 (the one the Google TV app
// speaks), used to talk to the TV Box plugged into the LG: errors, protobuf framing, DER helpers for
// the client certificate, pairing math, MAC addresses and Wake-on-LAN packets. No networking here,
// so everything in this file is unit-testable; AndroidTVRemote.swift has the network side.

enum AndroidTVError: LocalizedError, Equatable {
    case certificate(String)
    case connection(String)
    case secureChannel
    case timeout
    case rejected(String)
    case wrongCode
    case notPaired
    case asleep

    var errorDescription: String? {
        switch self {
        case .certificate(let why): return "Não consegui preparar o certificado do app (\(why))."
        case .connection(let why): return "Não consegui falar com a TV Box (\(why))."
        case .secureChannel: return "A TV Box recusou a conexão segura."
        case .timeout: return "A TV Box não respondeu a tempo."
        case .rejected(let why): return "A TV Box recusou o pedido (\(why))."
        case .wrongCode: return "Código incorreto. Confira os 6 caracteres na tela da TV."
        case .notPaired: return "O app ainda não está pareado com a TV Box."
        case .asleep: return "A TV Box está em repouso e não acordou pelo Wi-Fi."
        }
    }
}

/// Android key codes the app sends to the box.
enum AndroidKey: Int, Sendable {
    case power = 26
}

// MARK: - Minimal protobuf

struct ProtoWriter {
    private(set) var data = Data()

    mutating func varint(_ value: UInt64) {
        var v = value
        while v >= 0x80 {
            data.append(UInt8(truncatingIfNeeded: v) | 0x80)
            v >>= 7
        }
        data.append(UInt8(v))
    }

    mutating func int(_ field: Int, _ value: Int) {
        varint(UInt64(field << 3))
        varint(UInt64(bitPattern: Int64(value)))
    }

    mutating func bytes(_ field: Int, _ value: Data) {
        varint(UInt64(field << 3 | 2))
        varint(UInt64(value.count))
        data.append(value)
    }

    mutating func string(_ field: Int, _ value: String) { bytes(field, Data(value.utf8)) }

    mutating func message(_ field: Int, _ build: (inout ProtoWriter) -> Void) {
        var inner = ProtoWriter()
        build(&inner)
        bytes(field, inner.data)
    }

    /// The message with its length in front, the way both ports of the box expect it.
    static func framed(_ payload: Data) -> Data {
        var prefix = ProtoWriter()
        prefix.varint(UInt64(payload.count))
        return prefix.data + payload
    }
}

/// Integer (wire type 0) and length-delimited (wire type 2) fields of a message; last one wins.
struct ProtoMessage {
    private var ints: [Int: UInt64] = [:]
    private var blobs: [Int: Data] = [:]

    init(_ raw: Data) throws {
        let data = Data(raw)   // re-based copy: indices start at 0
        var i = 0
        func varint() throws -> UInt64 {
            var result: UInt64 = 0
            var shift: UInt64 = 0
            while i < data.count, shift < 64 {
                let byte = data[i]
                i += 1
                result |= UInt64(byte & 0x7F) << shift
                if byte & 0x80 == 0 { return result }
                shift += 7
            }
            throw AndroidTVError.rejected("mensagem malformada")
        }
        while i < data.count {
            let key = try varint()
            let field = Int(key >> 3)
            switch key & 7 {
            case 0: ints[field] = try varint()
            case 1: i += 8
            case 2:
                let length = Int(try varint())
                guard length >= 0, i + length <= data.count else { throw AndroidTVError.rejected("mensagem truncada") }
                blobs[field] = data.subdata(in: i..<(i + length))
                i += length
            case 5: i += 4
            default: throw AndroidTVError.rejected("tipo de campo desconhecido")
            }
        }
    }

    func has(_ field: Int) -> Bool { ints[field] != nil || blobs[field] != nil }
    func int(_ field: Int) -> Int { Int(truncatingIfNeeded: ints[field] ?? 0) }
    func message(_ field: Int) -> ProtoMessage? { blobs[field].flatMap { try? ProtoMessage($0) } }
    func string(_ field: Int) -> String? { blobs[field].flatMap { String(data: $0, encoding: .utf8) } }
}

// MARK: - DER

/// Just enough DER to write a self-signed certificate and read an RSA public key.
enum DER {
    static func item(tag: UInt8, _ content: Data) -> Data {
        var out = Data([tag])
        out.append(length(content.count))
        out.append(content)
        return out
    }

    static func length(_ count: Int) -> Data {
        if count < 0x80 { return Data([UInt8(count)]) }
        var bytes: [UInt8] = []
        var v = count
        while v > 0 {
            bytes.insert(UInt8(v & 0xFF), at: 0)
            v >>= 8
        }
        return Data([0x80 | UInt8(bytes.count)] + bytes)
    }

    static func sequence(_ items: [Data]) -> Data { item(tag: 0x30, items.reduce(Data(), +)) }
    static func set(_ items: [Data]) -> Data { item(tag: 0x31, items.reduce(Data(), +)) }

    /// Unsigned big-endian integer; a leading zero keeps values with the top bit set positive.
    static func integer(_ value: Data) -> Data {
        var v = Data(value.drop { $0 == 0 })
        if v.isEmpty { v = Data([0]) }
        if v[v.startIndex] & 0x80 != 0 { v.insert(0, at: v.startIndex) }
        return item(tag: 0x02, v)
    }

    static func integer(_ value: Int) -> Data {
        var v = UInt64(value)
        var bytes: [UInt8] = []
        repeat {
            bytes.insert(UInt8(v & 0xFF), at: 0)
            v >>= 8
        } while v > 0
        return integer(Data(bytes))
    }

    static func oid(_ dotted: String) -> Data {
        let arcs = dotted.split(separator: ".").compactMap { UInt64($0) }
        var body = Data([UInt8(arcs[0] * 40 + arcs[1])])
        for arc in arcs.dropFirst(2) {
            var v = arc
            var bytes = [UInt8(v & 0x7F)]
            v >>= 7
            while v > 0 {
                bytes.insert(UInt8(v & 0x7F) | 0x80, at: 0)
                v >>= 7
            }
            body.append(contentsOf: bytes)
        }
        return item(tag: 0x06, body)
    }

    static let null = Data([0x05, 0x00])
    static func utf8String(_ text: String) -> Data { item(tag: 0x0C, Data(text.utf8)) }
    static func bitString(_ content: Data) -> Data { item(tag: 0x03, Data([0]) + content) }
    static func explicit(_ number: UInt8, _ content: Data) -> Data { item(tag: 0xA0 | number, content) }

    /// UTCTime (YYMMDDHHMMSSZ): fine for dates before 2050.
    static func utcTime(_ date: Date) -> Data {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyMMddHHmmss'Z'"
        return item(tag: 0x17, Data(formatter.string(from: date).utf8))
    }
}

struct DERReader {
    private let data: Data
    private var index = 0

    init(_ data: Data) { self.data = Data(data) }

    mutating func enter(tag: UInt8) throws { _ = try header(tag: tag) }

    mutating func read(tag: UInt8) throws -> Data {
        let length = try header(tag: tag)
        guard index + length <= data.count else { throw AndroidTVError.certificate("DER truncado") }
        defer { index += length }
        return data.subdata(in: index..<(index + length))
    }

    private mutating func header(tag: UInt8) throws -> Int {
        guard index + 2 <= data.count, data[index] == tag else { throw AndroidTVError.certificate("DER inesperado") }
        index += 1
        var length = Int(data[index])
        index += 1
        if length & 0x80 != 0 {
            let count = length & 0x7F
            guard count <= 4, index + count <= data.count else { throw AndroidTVError.certificate("DER inválido") }
            length = 0
            for _ in 0..<count {
                length = length << 8 | Int(data[index])
                index += 1
            }
        }
        return length
    }
}

// MARK: - X.509 and RSA

enum X509 {
    static let sha256WithRSA = DER.sequence([DER.oid("1.2.840.113549.1.1.11"), DER.null])
    static let rsaEncryption = DER.sequence([DER.oid("1.2.840.113549.1.1.1"), DER.null])

    /// A self-signed v3-less certificate (version 3, no extensions), the minimum the box accepts.
    /// `sign` receives the TBSCertificate and returns its PKCS#1 v1.5 SHA-256 signature.
    static func selfSigned(commonName: String, publicKeyPKCS1: Data, serial: Data, notBefore: Date,
                           notAfter: Date, sign: (Data) throws -> Data) rethrows -> Data {
        let name = DER.sequence([DER.set([DER.sequence([DER.oid("2.5.4.3"), DER.utf8String(commonName)])])])
        let publicKeyInfo = DER.sequence([rsaEncryption, DER.bitString(publicKeyPKCS1)])
        let tbs = DER.sequence([
            DER.explicit(0, DER.integer(2)),
            DER.integer(serial),
            sha256WithRSA,
            name,
            DER.sequence([DER.utcTime(notBefore), DER.utcTime(notAfter)]),
            name,
            publicKeyInfo,
        ])
        let signature = try sign(tbs)
        return DER.sequence([tbs, sha256WithRSA, DER.bitString(signature)])
    }
}

enum RSAPublicKey {
    /// Modulus and exponent of a PKCS#1 `RSAPublicKey`, big-endian without leading zeros.
    static func components(fromPKCS1 der: Data) throws -> (modulus: Data, exponent: Data) {
        var reader = DERReader(der)
        try reader.enter(tag: 0x30)
        let modulus = try reader.read(tag: 0x02)
        let exponent = try reader.read(tag: 0x02)
        return (Data(modulus.drop { $0 == 0 }), Data(exponent.drop { $0 == 0 }))
    }
}

// MARK: - Pairing math

enum AndroidTVPairingMath {
    /// The 6-character code on the TV: first byte is a checksum, the other two are the nonce.
    static func parse(code raw: String) -> (checksum: UInt8, nonce: Data)? {
        let code = raw.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard code.count == 6, let checksum = UInt8(code.prefix(2), radix: 16),
              let nonce = Data(hex: String(code.suffix(4))) else { return nil }
        return (checksum, nonce)
    }

    /// SHA-256 over both RSA public keys and the nonce; its first byte must equal the checksum.
    static func secret(client: (modulus: Data, exponent: Data), server: (modulus: Data, exponent: Data),
                       nonce: Data) -> Data {
        var hash = SHA256()
        hash.update(data: client.modulus)
        hash.update(data: client.exponent)
        hash.update(data: server.modulus)
        hash.update(data: server.exponent)
        hash.update(data: nonce)
        return Data(hash.finalize())
    }
}

// MARK: - MAC addresses and Wake-on-LAN

enum MACAddress {
    /// "02:00:00:00:00:f8" from any usual spelling (colons, dashes, dots, none, single-digit octets).
    static func normalize(_ text: String) -> String? {
        let octets = text.trimmingCharacters(in: .whitespacesAndNewlines)
            .split(whereSeparator: { ":-.".contains($0) })
        let parts: [String]
        if octets.count == 6 {
            parts = octets.map(String.init)
        } else if octets.count == 1, octets[0].count == 12 {
            let hex = String(octets[0])
            parts = stride(from: 0, to: 12, by: 2).map {
                String(hex[hex.index(hex.startIndex, offsetBy: $0)..<hex.index(hex.startIndex, offsetBy: $0 + 2)])
            }
        } else {
            return nil
        }
        guard parts.allSatisfy({ (1...2).contains($0.count) && $0.allSatisfy(\.isHexDigit) }) else { return nil }
        return parts.map { $0.count == 1 ? "0\($0)" : $0 }.joined(separator: ":").lowercased()
    }

    static func bytes(_ mac: String) -> Data? {
        guard let normalized = normalize(mac) else { return nil }
        return Data(hex: normalized.replacingOccurrences(of: ":", with: ""))
    }

    /// The address `delta` steps away (Wi-Fi and Bluetooth MACs of one device are usually neighbours).
    static func offset(_ mac: String, by delta: Int) -> String? {
        guard let bytes = bytes(mac) else { return nil }
        var value = bytes.reduce(UInt64(0)) { $0 << 8 | UInt64($1) }
        guard Int64(value) + Int64(delta) >= 0 else { return nil }
        value = UInt64(Int64(value) + Int64(delta)) & 0xFFFF_FFFF_FFFF
        return (0..<6).reversed().map { String(format: "%02x", (value >> (UInt64($0) * 8)) & 0xFF) }
            .joined(separator: ":")
    }
}

enum WakeOnLAN {
    /// Six 0xFF bytes followed by the MAC sixteen times.
    static func magicPacket(mac: String) -> Data? {
        guard let address = MACAddress.bytes(mac) else { return nil }
        return Data(repeating: 0xFF, count: 6) + Data((0..<16).flatMap { _ in address })
    }

    /// Unicast address plus the /24 subnet broadcast and limited broadcast addresses.
    static func targets(for host: String) -> [String] {
        var result: [String] = []
        let trimmed = host.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            result.append(trimmed)
        }
        let octets = trimmed.split(separator: ".")
        if octets.count == 4, octets.allSatisfy({ UInt8($0) != nil }) {
            let subnetBroadcast = octets.prefix(3).joined(separator: ".") + ".255"
            if !result.contains(subnetBroadcast) {
                result.append(subnetBroadcast)
            }
        }
        if !result.contains("255.255.255.255") {
            result.append("255.255.255.255")
        }
        return result
    }
}

extension Data {
    init?(hex: String) {
        guard hex.count % 2 == 0 else { return nil }
        var bytes = [UInt8]()
        var index = hex.startIndex
        while index < hex.endIndex {
            let next = hex.index(index, offsetBy: 2)
            guard let byte = UInt8(hex[index..<next], radix: 16) else { return nil }
            bytes.append(byte)
            index = next
        }
        self.init(bytes)
    }

    var hexString: String { map { String(format: "%02x", $0) }.joined() }
}
