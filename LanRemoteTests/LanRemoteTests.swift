import XCTest
import Security
@testable import LanRemote

final class LanRemoteTests: XCTestCase {

    // MARK: - TVKey Tests

    func testTVKeyCodes() {
        XCTAssertEqual(TVKey.power.rawValue, 1)
        XCTAssertEqual(TVKey.digit0.rawValue, 2)
        XCTAssertEqual(TVKey.digit9.rawValue, 11)
        XCTAssertEqual(TVKey.up.rawValue, 12)
        XCTAssertEqual(TVKey.down.rawValue, 13)
        XCTAssertEqual(TVKey.left.rawValue, 14)
        XCTAssertEqual(TVKey.right.rawValue, 15)
        XCTAssertEqual(TVKey.ok.rawValue, 20)
        XCTAssertEqual(TVKey.home.rawValue, 21)
        XCTAssertEqual(TVKey.menu.rawValue, 22)
        XCTAssertEqual(TVKey.back.rawValue, 23)
        XCTAssertEqual(TVKey.volumeUp.rawValue, 24)
        XCTAssertEqual(TVKey.volumeDown.rawValue, 25)
        XCTAssertEqual(TVKey.mute.rawValue, 26)
        XCTAssertEqual(TVKey.channelUp.rawValue, 27)
        XCTAssertEqual(TVKey.channelDown.rawValue, 28)
        XCTAssertEqual(TVKey.blue.rawValue, 29)
        XCTAssertEqual(TVKey.exit.rawValue, 412)
    }

    func testTVKeyLabels() {
        XCTAssertEqual(TVKey.power.label, "Power")
        XCTAssertEqual(TVKey.ok.label, "OK")
        XCTAssertEqual(TVKey.volumeUp.label, "Vol +")
        XCTAssertEqual(TVKey.volumeDown.label, "Vol -")
        XCTAssertEqual(TVKey.mute.label, "Mudo")
        XCTAssertEqual(TVKey.back.label, "Voltar")
        XCTAssertEqual(TVKey.exit.label, "Sair")
    }

    func testTVKeyIsDigit() {
        XCTAssertTrue(TVKey.digit0.isDigit)
        XCTAssertTrue(TVKey.digit5.isDigit)
        XCTAssertTrue(TVKey.digit9.isDigit)
        XCTAssertFalse(TVKey.ok.isDigit)
        XCTAssertFalse(TVKey.power.isDigit)
        XCTAssertFalse(TVKey.volumeUp.isDigit)
    }

    func testTVKeyIcons() {
        XCTAssertEqual(TVKey.power.iconName, "power")
        XCTAssertEqual(TVKey.home.iconName, "house.fill")
        XCTAssertEqual(TVKey.mute.iconName, "speaker.slash.fill")
        XCTAssertEqual(TVKey.input.iconName, "tv.and.mediabox")
    }

    // MARK: - TVConfig Tests

    func testTVConfigDefaultValues() {
        let config = TVConfig.default
        XCTAssertEqual(config.host, "192.168.1.100")
        XCTAssertEqual(config.port, 8080)
        XCTAssertEqual(config.protocolType, "roap")
        XCTAssertEqual(config.model, "47LN5700-SA_11")
        XCTAssertEqual(config.pairingKey, "123456")
        XCTAssertEqual(config.session, "123456789")
    }

    func testTVConfigJSONCoding() throws {
        let json = """
        {
            "host": "192.168.1.50",
            "port": 8080,
            "protocol": "roap",
            "model": "47LN5700",
            "name": "Sala TV",
            "pairing_key": "123456",
            "session": "987654321",
            "mac": "AA:BB:CC:DD:EE:FF"
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(TVConfig.self, from: json)
        XCTAssertEqual(decoded.host, "192.168.1.50")
        XCTAssertEqual(decoded.port, 8080)
        XCTAssertEqual(decoded.protocolType, "roap")
        XCTAssertEqual(decoded.model, "47LN5700")
        XCTAssertEqual(decoded.name, "Sala TV")
        XCTAssertEqual(decoded.pairingKey, "123456")
        XCTAssertEqual(decoded.session, "987654321")
        XCTAssertEqual(decoded.mac, "AA:BB:CC:DD:EE:FF")

        let reencoded = try JSONEncoder().encode(decoded)
        let redecoded = try JSONDecoder().decode(TVConfig.self, from: reencoded)
        XCTAssertEqual(decoded, redecoded)
    }

    // MARK: - XML Parser Tests

    func testExtractXMLTag() {
        let xml = """
        <?xml version="1.0" encoding="utf-8"?>
        <envelope>
            <session>123456789</session>
            <level>  15  </level>
            <mute>true</mute>
            <inputSourceName>HDMI2</inputSourceName>
        </envelope>
        """

        XCTAssertEqual(LGTVClient.extractXMLTag(from: xml, tag: "session"), "123456789")
        XCTAssertEqual(LGTVClient.extractXMLTag(from: xml, tag: "level"), "15")
        XCTAssertEqual(LGTVClient.extractXMLTag(from: xml, tag: "mute"), "true")
        XCTAssertEqual(LGTVClient.extractXMLTag(from: xml, tag: "inputSourceName"), "HDMI2")
        XCTAssertNil(LGTVClient.extractXMLTag(from: xml, tag: "nonexistent"))
    }

    func testExtractXMLTagCaseInsensitive() {
        let xml = "<Session>999888</Session>"
        XCTAssertEqual(LGTVClient.extractXMLTag(from: xml, tag: "session"), "999888")
    }

    func testExtractXMLTagEmptyOrMalformed() {
        XCTAssertNil(LGTVClient.extractXMLTag(from: "", tag: "session"))
        XCTAssertNil(LGTVClient.extractXMLTag(from: "<session>incomplete", tag: "session"))
    }

    // MARK: - Request Builder & Critical Protocol Rules Tests

    @MainActor
    func testUserAgentDoesNotContainUDAPInROAPMode() {
        // Critical requirement discovered in firmware 05.02.11:
        // User-Agent must NOT contain "UDAP/2.0" when sending ROAP commands, otherwise TV responds 400 Bad Request
        let client = LGTVClient(config: TVConfig.default)
        guard let req = client.createRequest(path: "/roap/api/command", method: "POST", body: "<test/>") else {
            XCTFail("Request should not be nil")
            return
        }

        let ua = req.value(forHTTPHeaderField: "User-Agent") ?? ""
        XCTAssertFalse(ua.contains("UDAP/2.0"), "User-Agent must not contain UDAP/2.0 in ROAP mode")
        XCTAssertEqual(req.value(forHTTPHeaderField: "Content-Type"), "application/atom+xml")
    }

    @MainActor
    func testUserAgentInUDAPMode() {
        var config = TVConfig.default
        config.protocolType = "udap"
        let client = LGTVClient(config: config)
        guard let req = client.createRequest(path: "/udap/api/command", method: "POST", body: "<test/>") else {
            XCTFail("Request should not be nil")
            return
        }

        let ua = req.value(forHTTPHeaderField: "User-Agent") ?? ""
        XCTAssertTrue(ua.contains("UDAP/2.0"))
        XCTAssertEqual(req.value(forHTTPHeaderField: "Content-Type"), "text/xml; charset=utf-8")
    }

    // MARK: - Power state

    @MainActor
    func testKeysAreHeldBackWhileTVIsOff() {
        let client = LGTVClient(config: TVConfig.default)
        client.powerState = .off
        XCTAssertFalse(client.isConnected)
        XCTAssertEqual(client.attentionPulse, 0)
        client.sendKey(.volumeUp)
        XCTAssertEqual(client.attentionPulse, 1, "a key pressed with the TV off should nudge the power banner")
        client.powerState = .turningOn
        client.sendKey(.ok)
        XCTAssertEqual(client.attentionPulse, 2)
    }

    @MainActor
    func testCannotTurnOnWithoutPairedBox() {
        let client = LGTVClient(config: TVConfig.default)
        client.box = nil
        XCTAssertFalse(client.canTurnOnTV)
        client.box = AndroidTVBox(name: "TV Box", host: "192.168.1.101", paired: false)
        XCTAssertFalse(client.canTurnOnTV)
        client.box?.paired = true
        XCTAssertTrue(client.canTurnOnTV)
    }

    // MARK: - DiscoveredTV Model Tests

    func testDiscoveredTVModel() {
        let tv = DiscoveredTV(
            ip: "192.168.1.100",
            port: 8080,
            model: "47LN5700",
            name: "LG TV",
            protocolType: "roap"
        )

        XCTAssertEqual(tv.id, "192.168.1.100:8080")
        XCTAssertEqual(tv.ip, "192.168.1.100")
        XCTAssertEqual(tv.port, 8080)
    }

    // MARK: - Android TV protocol: protobuf

    func testProtobufRoundTrip() throws {
        var writer = ProtoWriter()
        writer.int(1, 2)
        writer.int(2, 200)
        writer.message(10) { request in
            request.string(1, "atvremote")
            request.string(2, "LanRemote (iPhone)")
        }
        writer.int(7, 300)   // two-byte varint

        let message = try ProtoMessage(writer.data)
        XCTAssertEqual(message.int(1), 2)
        XCTAssertEqual(message.int(2), 200)
        XCTAssertEqual(message.int(7), 300)
        XCTAssertFalse(message.has(3))
        let request = try XCTUnwrap(message.message(10))
        XCTAssertEqual(request.string(1), "atvremote")
        XCTAssertEqual(request.string(2), "LanRemote (iPhone)")
    }

    func testProtobufWireFormatMatchesSpec() {
        var writer = ProtoWriter()
        writer.int(1, 150)                      // field 1, varint 150 -> 08 96 01 (the protobuf docs example)
        XCTAssertEqual(writer.data, Data([0x08, 0x96, 0x01]))

        var framed = ProtoWriter()
        framed.varint(300)
        XCTAssertEqual(framed.data, Data([0xAC, 0x02]))
        XCTAssertEqual(ProtoWriter.framed(Data([0xAA, 0xBB])), Data([0x02, 0xAA, 0xBB]))
    }

    func testProtobufRejectsTruncatedMessage() {
        XCTAssertThrowsError(try ProtoMessage(Data([0x0A, 0x05, 0x01])))   // says 5 bytes, has 1
        XCTAssertThrowsError(try ProtoMessage(Data([0x08])))               // key without value
    }

    // MARK: - Android TV protocol: pairing math

    func testPairingCodeParsing() throws {
        let parsed = try XCTUnwrap(AndroidTVPairingMath.parse(code: " 8e5434 "))
        XCTAssertEqual(parsed.checksum, 0x8E)
        XCTAssertEqual(parsed.nonce, Data([0x54, 0x34]))
        XCTAssertNil(AndroidTVPairingMath.parse(code: "8E543"))     // too short
        XCTAssertNil(AndroidTVPairingMath.parse(code: "8E543G"))    // not hex
    }

    func testPairingSecretIsDeterministicAndNonceSensitive() {
        let client = (modulus: Data([0x01, 0x02, 0x03]), exponent: Data([0x01, 0x00, 0x01]))
        let server = (modulus: Data([0x09, 0x08, 0x07]), exponent: Data([0x01, 0x00, 0x01]))
        let a = AndroidTVPairingMath.secret(client: client, server: server, nonce: Data([0x54, 0x34]))
        let b = AndroidTVPairingMath.secret(client: client, server: server, nonce: Data([0x54, 0x34]))
        let c = AndroidTVPairingMath.secret(client: client, server: server, nonce: Data([0x54, 0x35]))
        XCTAssertEqual(a.count, 32)
        XCTAssertEqual(a, b)
        XCTAssertNotEqual(a, c)
        // Swapping the two keys must change the result: the box hashes client first, server second.
        let swapped = AndroidTVPairingMath.secret(client: server, server: client, nonce: Data([0x54, 0x34]))
        XCTAssertNotEqual(a, swapped)
    }

    // MARK: - Android TV protocol: DER and the client certificate

    func testDERPrimitives() {
        XCTAssertEqual(DER.integer(0), Data([0x02, 0x01, 0x00]))
        XCTAssertEqual(DER.integer(2), Data([0x02, 0x01, 0x02]))
        XCTAssertEqual(DER.integer(Data([0x80])), Data([0x02, 0x02, 0x00, 0x80]), "top bit set needs a leading zero")
        XCTAssertEqual(DER.integer(Data([0x00, 0x00, 0x7F])), Data([0x02, 0x01, 0x7F]), "leading zeros are dropped")
        XCTAssertEqual(DER.oid("1.2.840.113549.1.1.11"),
                       Data([0x06, 0x09, 0x2A, 0x86, 0x48, 0x86, 0xF7, 0x0D, 0x01, 0x01, 0x0B]))
        XCTAssertEqual(DER.oid("2.5.4.3"), Data([0x06, 0x03, 0x55, 0x04, 0x03]))
        XCTAssertEqual(DER.length(127), Data([0x7F]))
        XCTAssertEqual(DER.length(128), Data([0x81, 0x80]))
        XCTAssertEqual(DER.length(300), Data([0x82, 0x01, 0x2C]))
        XCTAssertEqual(DER.bitString(Data([0xFF])), Data([0x03, 0x02, 0x00, 0xFF]))
    }

    func testRSAPublicKeyComponents() throws {
        // RSAPublicKey ::= SEQUENCE { modulus INTEGER, publicExponent INTEGER }
        let der = DER.sequence([DER.integer(Data([0xC0, 0xFF, 0xEE])), DER.integer(65537)])
        let components = try RSAPublicKey.components(fromPKCS1: der)
        XCTAssertEqual(components.modulus, Data([0xC0, 0xFF, 0xEE]), "the sign byte must not leak into the modulus")
        XCTAssertEqual(components.exponent, Data([0x01, 0x00, 0x01]))
        XCTAssertThrowsError(try RSAPublicKey.components(fromPKCS1: Data([0x30, 0x00])))
    }

    func testSelfSignedCertificateIsValidX509() throws {
        // A real key makes this an end-to-end check of the DER writer through Security.framework.
        let attributes: [String: Any] = [kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
                                         kSecAttrKeySizeInBits as String: 2048]
        var error: Unmanaged<CFError>?
        let privateKey = try XCTUnwrap(SecKeyCreateRandomKey(attributes as CFDictionary, &error))
        let publicKey = try XCTUnwrap(SecKeyCopyPublicKey(privateKey))
        let publicDER = try XCTUnwrap(SecKeyCopyExternalRepresentation(publicKey, &error) as Data?)

        let der = try X509.selfSigned(commonName: "LanRemote", publicKeyPKCS1: publicDER, serial: Data([0x7A, 0x01]),
                                      notBefore: Date(), notAfter: Date().addingTimeInterval(86_400)) { tbs in
            try XCTUnwrap(SecKeyCreateSignature(privateKey, .rsaSignatureMessagePKCS1v15SHA256, tbs as CFData, &error) as Data?)
        }
        let certificate = try XCTUnwrap(SecCertificateCreateWithData(nil, der as CFData), "Security.framework must parse the certificate")
        XCTAssertEqual(SecCertificateCopySubjectSummary(certificate) as String?, "LanRemote")

        let embeddedKey = try XCTUnwrap(SecCertificateCopyKey(certificate))
        let embeddedDER = try XCTUnwrap(SecKeyCopyExternalRepresentation(embeddedKey, &error) as Data?)
        XCTAssertEqual(embeddedDER, publicDER, "the certificate must carry the generated public key")

        let components = try RSAPublicKey.components(fromPKCS1: embeddedDER)
        XCTAssertEqual(components.modulus.count, 256)
        XCTAssertEqual(components.exponent, Data([0x01, 0x00, 0x01]))
    }

    func testIdentityIsCreatedOnceAndReused() throws {
        AndroidTVIdentity.reset()
        let first = try AndroidTVIdentity.load()
        let second = try AndroidTVIdentity.load()
        let firstCertificate = try AndroidTVIdentity.certificate(of: first)
        let secondCertificate = try AndroidTVIdentity.certificate(of: second)
        XCTAssertEqual(SecCertificateCopyData(firstCertificate) as Data, SecCertificateCopyData(secondCertificate) as Data,
                       "the same certificate must come back, or the box would forget the pairing")
        let components = try AndroidTVIdentity.rsaComponents(firstCertificate)
        XCTAssertEqual(components.modulus.count, 256)
        AndroidTVIdentity.reset()
        XCTAssertNil(AndroidTVIdentity.existing())
    }

    // MARK: - MAC addresses and Wake-on-LAN

    func testMACNormalization() {
        XCTAssertEqual(MACAddress.normalize("02:00:00:00:00:F8"), "02:00:00:00:00:f8")
        XCTAssertEqual(MACAddress.normalize("02-00-00-00-00-f8"), "02:00:00:00:00:f8")
        XCTAssertEqual(MACAddress.normalize("0200000000f8"), "02:00:00:00:00:f8")
        XCTAssertEqual(MACAddress.normalize("a:3:b:c:d:5"), "0a:03:0b:0c:0d:05", "macOS arp drops leading zeros")
        XCTAssertNil(MACAddress.normalize("02:00:00:00:00"))
        XCTAssertNil(MACAddress.normalize("02:00:00:00:00:GG"))
        XCTAssertNil(MACAddress.normalize(""))
    }

    func testMACNeighbours() {
        XCTAssertEqual(MACAddress.offset("02:00:00:00:00:f9", by: -1), "02:00:00:00:00:f8")
        XCTAssertEqual(MACAddress.offset("02:00:00:00:00:ff", by: 1), "02:00:00:00:01:00", "carries into the next octet")
        XCTAssertEqual(MACAddress.offset("00:00:00:00:00:00", by: -1), nil)
    }

    func testMagicPacket() throws {
        let packet = try XCTUnwrap(WakeOnLAN.magicPacket(mac: "02:00:00:00:00:f8"))
        XCTAssertEqual(packet.count, 102)
        XCTAssertEqual(packet.prefix(6), Data(repeating: 0xFF, count: 6))
        let mac = Data([0x02, 0x00, 0x00, 0x00, 0x00, 0xF8])
        for i in 0..<16 {
            XCTAssertEqual(packet.subdata(in: (6 + i * 6)..<(12 + i * 6)), mac)
        }
        XCTAssertNil(WakeOnLAN.magicPacket(mac: "nope"))
    }

    // MARK: - TV Box model

    func testAndroidTVBoxWakeMACs() {
        var box = AndroidTVBox(name: "TV Box Xiaomi", host: "192.168.1.101", paired: true,
                               bluetoothMAC: "02:00:00:00:00:F9")
        XCTAssertEqual(box.wakeMACs, ["02:00:00:00:00:f8", "02:00:00:00:00:fa", "02:00:00:00:00:f9"],
                       "without a known Wi-Fi MAC, try the Bluetooth MAC's neighbours first")
        box.mac = "AA:BB:CC:DD:EE:FF"
        XCTAssertEqual(box.wakeMACs, ["aa:bb:cc:dd:ee:ff"], "a MAC typed by the user wins")
        XCTAssertEqual(AndroidTVBox(name: "x", host: "h", paired: false).wakeMACs, [])
    }

    func testAndroidTVBoxPersistence() {
        AndroidTVBox.forget()
        XCTAssertNil(AndroidTVBox.load())
        let box = AndroidTVBox(name: "TV Box Xiaomi", host: "192.168.1.101", paired: true,
                               mac: "02:00:00:00:00:f8", bluetoothMAC: "02:00:00:00:00:f9")
        box.save()
        XCTAssertEqual(AndroidTVBox.load(), box)
        AndroidTVBox.forget()
        XCTAssertNil(AndroidTVBox.load())
    }

    // MARK: - Button guide

    func testGuideCoversEveryHelpOnceWithCompleteText() {
        let items = GuideSection.all.flatMap(\.items)
        XCTAssertFalse(items.isEmpty)
        XCTAssertEqual(Set(items.map(\.id)).count, items.count, "each control appears once in the guide")
        for item in items {
            XCTAssertFalse(item.title.isEmpty, item.id)
            XCTAssertFalse(item.detail.isEmpty, item.id)
            XCTAssertFalse(item.symbol.isEmpty, item.id)
            XCTAssertNotNil(UIImage(systemName: item.symbol), "SF Symbol '\(item.symbol)' for \(item.id) must exist")
        }
        for help in [Help.powerOn, Help.powerOff, Help.input, Help.keypad, Help.mute, Help.liveTV, Help.quickMenu,
                     Help.home, Help.menu, Help.back, Help.exit, Help.guide, Help.apps, Help.aspect, Help.threeD,
                     Help.simplink, Help.previousChannel, Help.info] {
            XCTAssertFalse(help.label.isEmpty, "\(help.id) is shown on a button and needs a caption")
        }
    }
}
