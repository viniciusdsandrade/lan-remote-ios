import Foundation
import Security

// The app's own TLS client certificate for the Android TV Remote protocol. The box remembers it at
// pairing time, so it has to survive restarts: the RSA key lives in the app's Keychain and the
// self-signed certificate is built by hand (iOS has no openssl) and stored next to it.

enum AndroidTVIdentity {
    static let label = "com.lanremote.ios.androidtv"
    private static let keyTag = Data("com.lanremote.ios.androidtv.key".utf8)
    private static let commonName = "LanRemote"

    /// The identity, created on first use.
    static func load() throws -> SecIdentity {
        if let identity = existing() { return identity }
        try create()
        guard let identity = existing() else {
            throw AndroidTVError.certificate("identidade não encontrada no Keychain")
        }
        return identity
    }

    static func existing() -> SecIdentity? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassIdentity,
            kSecAttrLabel as String: label,
            kSecReturnRef as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess, let item else { return nil }
        return (item as! SecIdentity)
    }

    /// Forgets the certificate and key; the next pairing starts from scratch.
    static func reset() {
        SecItemDelete([kSecClass as String: kSecClassCertificate, kSecAttrLabel as String: label] as CFDictionary)
        SecItemDelete([kSecClass as String: kSecClassKey, kSecAttrApplicationTag as String: keyTag] as CFDictionary)
    }

    static func certificate(of identity: SecIdentity) throws -> SecCertificate {
        var certificate: SecCertificate?
        guard SecIdentityCopyCertificate(identity, &certificate) == errSecSuccess, let certificate else {
            throw AndroidTVError.certificate("certificado ilegível")
        }
        return certificate
    }

    static func rsaComponents(_ certificate: SecCertificate) throws -> (modulus: Data, exponent: Data) {
        guard let key = SecCertificateCopyKey(certificate),
              let der = SecKeyCopyExternalRepresentation(key, nil) as Data? else {
            throw AndroidTVError.certificate("chave pública ilegível")
        }
        return try RSAPublicKey.components(fromPKCS1: der)
    }

    private static func create() throws {
        reset()
        let attributes: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
            kSecAttrKeySizeInBits as String: 2048,
            kSecPrivateKeyAttrs as String: [
                kSecAttrIsPermanent as String: true,
                kSecAttrApplicationTag as String: keyTag,
                kSecAttrLabel as String: label,
                kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
            ],
        ]
        var error: Unmanaged<CFError>?
        guard let privateKey = SecKeyCreateRandomKey(attributes as CFDictionary, &error),
              let publicKey = SecKeyCopyPublicKey(privateKey),
              let publicKeyDER = SecKeyCopyExternalRepresentation(publicKey, &error) as Data? else {
            let reason = (error?.takeRetainedValue()).map { "\($0)" } ?? "sem detalhes"
            throw AndroidTVError.certificate("não consegui gerar a chave RSA: \(reason)")
        }

        var serial = Data(count: 16)
        serial.withUnsafeMutableBytes { _ = SecRandomCopyBytes(kSecRandomDefault, 16, $0.baseAddress!) }
        let now = Date()
        let der = try X509.selfSigned(commonName: commonName, publicKeyPKCS1: publicKeyDER, serial: serial,
                                      notBefore: now.addingTimeInterval(-86_400),
                                      notAfter: now.addingTimeInterval(3650 * 86_400)) { tbs in
            guard let signature = SecKeyCreateSignature(privateKey, .rsaSignatureMessagePKCS1v15SHA256,
                                                        tbs as CFData, &error) as Data? else {
                throw AndroidTVError.certificate("não consegui assinar o certificado")
            }
            return signature
        }
        guard let certificate = SecCertificateCreateWithData(nil, der as CFData) else {
            throw AndroidTVError.certificate("certificado gerado é inválido")
        }
        let add: [String: Any] = [
            kSecClass as String: kSecClassCertificate,
            kSecValueRef as String: certificate,
            kSecAttrLabel as String: label,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]
        let status = SecItemAdd(add as CFDictionary, nil)
        guard status == errSecSuccess || status == errSecDuplicateItem else {
            throw AndroidTVError.certificate("Keychain recusou o certificado (\(status))")
        }
    }
}
