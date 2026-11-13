import XCTest
import Combine
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
        XCTAssertEqual(config.host, "192.0.2.100")
        XCTAssertEqual(config.port, 8080)
        XCTAssertEqual(config.protocolType, "roap")
        XCTAssertEqual(config.model, "xxLN5700-SA_11")
        XCTAssertNil(config.pairingKey, "no pairing key ships with the app: it comes from the TV screen")
        XCTAssertNil(config.session)
        XCTAssertNil(config.mac)
    }

    func testTVConfigJSONCoding() throws {
        let json = """
        {
            "host": "192.0.2.50",
            "port": 8080,
            "protocol": "roap",
            "model": "xxLN5700",
            "name": "Sala TV",
            "pairing_key": "123456",
            "session": "987654321",
            "mac": "aa:bb:cc:dd:ee:ff"
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(TVConfig.self, from: json)
        XCTAssertEqual(decoded.host, "192.0.2.50")
        XCTAssertEqual(decoded.port, 8080)
        XCTAssertEqual(decoded.protocolType, "roap")
        XCTAssertEqual(decoded.model, "xxLN5700")
        XCTAssertEqual(decoded.name, "Sala TV")
        XCTAssertEqual(decoded.pairingKey, "123456")
        XCTAssertEqual(decoded.session, "987654321")
        XCTAssertEqual(decoded.mac, "aa:bb:cc:dd:ee:ff")

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
        client.box = AndroidTVBox(name: "TV Box", host: "192.0.2.101", paired: false)
        XCTAssertFalse(client.canTurnOnTV)
        client.box?.paired = true
        XCTAssertTrue(client.canTurnOnTV)
    }

    // MARK: - DiscoveredTV Model Tests

    func testDiscoveredTVModel() {
        let tv = DiscoveredTV(
            ip: "192.0.2.100",
            port: 8080,
            model: "xxLN5700",
            name: "LG TV",
            protocolType: "roap"
        )

        XCTAssertEqual(tv.id, "192.0.2.100:8080")
        XCTAssertEqual(tv.ip, "192.0.2.100")
        XCTAssertEqual(tv.port, 8080)
        XCTAssertNil(tv.uuid)
    }

    func testConfigSavedByAnOlderBuildUnderAnotherKeyIsAdoptedOnce() throws {
        // Installing over an older bundle id keeps its UserDefaults, but the TV config sat under that
        // build's key: the app fell back to the factory default (no pairing key, IP outside the LAN).
        let suite = "lanremote.tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        var old = TVConfig.default
        old.host = "10.20.30.17"
        old.pairingKey = "123456"
        old.session = "123456789"
        defaults.set(try JSONEncoder().encode(old), forKey: "org.example.olderbuild.config")
        defaults.set(Data("not a config".utf8), forKey: "org.example.other.config")
        XCTAssertNil(defaults.data(forKey: TVConfig.defaultsKey))

        let loaded = TVConfig.load(from: defaults)
        XCTAssertEqual(loaded, old, "IP, pairing key and session come back")
        XCTAssertNotNil(defaults.data(forKey: TVConfig.defaultsKey), "saved under the current key")

        var current = loaded
        current.host = "10.20.30.10"
        current.save(to: defaults)
        XCTAssertEqual(TVConfig.load(from: defaults).host, "10.20.30.10", "the current key wins from then on")

        let empty = try XCTUnwrap(UserDefaults(suiteName: suite + ".empty"))
        defer { empty.removePersistentDomain(forName: suite + ".empty") }
        XCTAssertEqual(TVConfig.load(from: empty), .default)
    }

    // MARK: - Sweep of the iPhone's own subnet (on iOS, SSDP gets no answer without the multicast entitlement)

    func testSweepCoversTheDevicesSubnetEvenWithTheFactoryDefaultIP() throws {
        // The factory default 192.0.2.100 used to set the subnet swept (192.0.2.x), so a fresh install,
        // or one whose saved IP came from another network, never reached the TV.
        let wifi = try XCTUnwrap(LocalIPv4Network("en0", "10.20.30.40", "255.255.255.0"))
        let hosts = LGTVDiscovery.sweepHosts(around: TVConfig.default.host, networks: [wifi])
        XCTAssertEqual(hosts.count, 253, "every host of the /24 but the iPhone itself")
        XCTAssertEqual(hosts.first, "10.20.30.1")
        XCTAssertEqual(hosts.last, "10.20.30.254")
        XCTAssertTrue(hosts.contains("10.20.30.10"))
        XCTAssertFalse(hosts.contains("10.20.30.40"), "never the iPhone's own address")
        XCTAssertFalse(hosts.contains("10.20.30.0") || hosts.contains("10.20.30.255"), "no network or broadcast address")
        XCTAssertFalse(hosts.contains { $0.hasPrefix("192.0.2.") }, "the default IP is no LAN to sweep")
    }

    func testSweepAddsTheSavedIPsOtherLANAndCapsWideNetworks() throws {
        let wifi = try XCTUnwrap(LocalIPv4Network("en0", "10.20.30.40", "255.255.255.0"))
        let behindRouter = LGTVDiscovery.sweepHosts(around: "192.168.77.20", networks: [wifi])
        XCTAssertEqual(behindRouter.count, 253 + 254)
        XCTAssertEqual(behindRouter[252], "10.20.30.254", "the iPhone's own subnet first")
        XCTAssertEqual(behindRouter[253], "192.168.77.1")

        let sameLAN = LGTVDiscovery.sweepHosts(around: "10.20.30.99", networks: [wifi])
        XCTAssertEqual(sameLAN.count, 253, "a saved IP inside the swept network adds nothing")

        let wide22 = try XCTUnwrap(LocalIPv4Network("en0", "10.1.5.7", "255.255.252.0"))
        let hosts22 = LGTVDiscovery.sweepHosts(around: nil, networks: [wide22])
        XCTAssertEqual(hosts22.count, 1021, "a /22 is swept whole: 10.1.4.1 to 10.1.7.254")
        XCTAssertEqual(hosts22.first, "10.1.4.1")
        XCTAssertEqual(hosts22.last, "10.1.7.254")

        let wide16 = try XCTUnwrap(LocalIPv4Network("en0", "172.16.5.9", "255.255.0.0"))
        let hosts16 = LGTVDiscovery.sweepHosts(around: nil, networks: [wide16])
        XCTAssertEqual(hosts16.count, 253, "wider than /22: only the iPhone's own /24")
        XCTAssertEqual(hosts16.first, "172.16.5.1")

        XCTAssertTrue(LGTVDiscovery.sweepHosts(around: "invalid", networks: []).isEmpty)
    }

    func testLocalNetworksAreWiFiOrEthernetWithPrivateAddresses() {
        for network in LGTVDiscovery.localIPv4Networks() {
            XCTAssertTrue(network.interface.hasPrefix("en"), network.interface)
            XCTAssertTrue(LGTVDiscovery.isPrivate(network.address))
        }
        XCTAssertTrue(LGTVDiscovery.isPrivate(LGTVDiscovery.ipv4Value("10.0.0.1")!))
        XCTAssertTrue(LGTVDiscovery.isPrivate(LGTVDiscovery.ipv4Value("172.31.255.1")!))
        XCTAssertTrue(LGTVDiscovery.isPrivate(LGTVDiscovery.ipv4Value("192.168.0.1")!))
        XCTAssertFalse(LGTVDiscovery.isPrivate(LGTVDiscovery.ipv4Value("172.32.0.1")!))
        XCTAssertFalse(LGTVDiscovery.isPrivate(LGTVDiscovery.ipv4Value("192.0.2.100")!))
        XCTAssertFalse(LGTVDiscovery.isPrivate(LGTVDiscovery.ipv4Value("169.254.3.4")!))
        XCTAssertEqual(LGTVDiscovery.ipv4String(LGTVDiscovery.ipv4Value("10.20.30.40")!), "10.20.30.40")
    }

    func testConnectScanFindsTheOpenPortOnly() async throws {
        let listener = try LoopbackListener()
        defer { listener.close() }
        let open = await LGTVDiscovery.hostsAcceptingTCP(["127.0.0.1"], port: Int(listener.port), timeout: 1.0)
        XCTAssertEqual(open, ["127.0.0.1"])

        let closedPort = listener.port == 65535 ? listener.port - 1 : listener.port + 1
        let refused = await LGTVDiscovery.hostsAcceptingTCP(["127.0.0.1", "not-an-ip"], port: Int(closedPort), timeout: 1.0)
        XCTAssertTrue(refused.isEmpty, "refused connections and invalid addresses are not TVs")
    }

    func testFirstTVPicksTheHostAnsweringROAP() async {
        URLProtocol.registerClass(TVStub.self)
        defer { URLProtocol.unregisterClass(TVStub.self) }
        let tv = await LGTVDiscovery.firstTV(among: [TVStub.host], port: 8080, timeout: 1.0)
        XCTAssertEqual(tv, TVStub.host)
        let none = await LGTVDiscovery.firstTV(among: [], port: 8080)
        XCTAssertNil(none)
    }

    /// Opt-in check against the real TV on this LAN, the way an iPhone finds it (no SSDP):
    /// `TEST_RUNNER_LANREMOTE_LIVE_TV=1 xcodebuild test ... -only-testing:LanRemoteTests/LanRemoteTests/testLiveSweepFindsTheTVWithoutSSDP`
    func testLiveSweepFindsTheTVWithoutSSDP() async throws {
        guard ProcessInfo.processInfo.environment["LANREMOTE_LIVE_TV"] == "1" else {
            throw XCTSkip("needs a LG NetCast TV on the LAN: set LANREMOTE_LIVE_TV=1")
        }
        let started = Date()
        let host = await LGTVDiscovery.locate(matching: .default, ssdp: false)
        let elapsed = Date().timeIntervalSince(started)
        let found = try XCTUnwrap(host, "the sweep of the device's own subnet must find the TV")
        let answers = await LGTVDiscovery.probeHost(found)
        XCTAssertTrue(answers)
        XCTAssertLessThan(elapsed, 15)
        print("live sweep: TV found in \(String(format: "%.1f", elapsed)) s")
    }

    func testAutomaticSearchIsDLNAOnly() {
        // Every answer to a UDAP search puts LG's "Pairing Key" popup on the TV, and the automatic
        // relocation runs whenever the TV stops answering.
        let search = LGTVDiscovery.dlnaSearch
        XCTAssertTrue(search.hasPrefix("M-SEARCH * HTTP/1.1\r\n"))
        XCTAssertTrue(search.contains("ST: urn:schemas-upnp-org:device:MediaRenderer:1\r\n"))
        XCTAssertFalse(search.lowercased().contains("udap"))
        XCTAssertTrue(search.hasSuffix("\r\n\r\n"))
    }

    @MainActor
    func testConfiguredIPIsCheckedOnEveryFailureNotOnlyEvery30Seconds() async throws {
        // Every failed request asks for the relocation: the 30 s limit is for the search, while the
        // TV answering at its configured IP is checked every time.
        URLProtocol.registerClass(TVStub.self)
        defer { URLProtocol.unregisterClass(TVStub.self) }
        var config = TVConfig.default
        config.host = TVStub.host
        let client = LGTVClient(config: config)
        let deadline = Date().addingTimeInterval(5)
        while client.powerState == .unknown, Date() < deadline {   // the status check the client starts itself
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        let probes = TVStub.probes
        let first = await client.relocateTVIfNeeded()
        let second = await client.relocateTVIfNeeded()
        XCTAssertFalse(first, "the TV still answers at its IP")
        XCTAssertFalse(second)
        XCTAssertEqual(TVStub.probes - probes, 2)
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

    func testScreenTextHexCodesCoverOCRMixUps() {
        // The code read off the TV: "O" for 0, "B" for 8; other lines are not codes.
        let text = ScreenText(lines: ["lan remote (iphone)", "4f 2a 9c", "8e5434", "o1 b2 c3", "abcdefg"])
        let codes = text.hexCodes()
        XCTAssertTrue(codes.contains("4F2A9C"))
        XCTAssertTrue(codes.contains("8E5434"))
        XCTAssertTrue(codes.contains("BE5434"), "8 can be a misread B")
        XCTAssertTrue(codes.contains("01B2C3"), "O can be a misread 0")
        XCTAssertTrue(codes.contains("0182C3"), "B can be a misread 8")
        XCTAssertFalse(codes.contains { $0.count != 6 || !$0.allSatisfy(\.isHexDigit) })
        XCTAssertEqual(Set(codes).count, codes.count, "no duplicates")
        XCTAssertEqual(ScreenText(lines: ["nothing here"]).hexCodes(), [])
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

    func testWakeOnLANTargetsIncludeUnicastAndSubnetBroadcast() {
        XCTAssertEqual(WakeOnLAN.targets(for: "192.0.2.101"),
                       ["192.0.2.101", "192.0.2.255", "255.255.255.255"])
        XCTAssertEqual(WakeOnLAN.targets(for: "fe80::1"),
                       ["fe80::1", "255.255.255.255"])
    }

    // MARK: - TV Box model

    func testAndroidTVBoxWakeMACs() {
        var box = AndroidTVBox(name: "TV Box da sala", host: "192.0.2.101", paired: true,
                               bluetoothMAC: "02:00:00:00:00:F9")
        XCTAssertEqual(box.wakeMACs, ["02:00:00:00:00:f8", "02:00:00:00:00:fa", "02:00:00:00:00:f9"],
                       "without a known Wi-Fi MAC, try the Bluetooth MAC's neighbours first")
        box.mac = "aa:bb:cc:dd:ee:ff"
        XCTAssertEqual(box.wakeMACs, ["aa:bb:cc:dd:ee:ff"], "a MAC typed by the user wins")
        XCTAssertEqual(AndroidTVBox(name: "x", host: "h", paired: false).wakeMACs, [])
    }

    func testAndroidTVBoxPersistence() {
        AndroidTVBox.forget()
        XCTAssertNil(AndroidTVBox.load())
        let box = AndroidTVBox(name: "TV Box da sala", host: "192.0.2.101", paired: true,
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
        for statusHelp in [Help.notAnsweringStatus, Help.ipConflictStatus] {
            XCTAssertFalse(statusHelp.title.isEmpty)
            XCTAssertFalse(statusHelp.detail.isEmpty)
            XCTAssertNotNil(UIImage(systemName: statusHelp.symbol))
        }
    }

    func testHardwareVolumeButtonsAreNotIntercepted() throws {
        // Hardware volume buttons on the iPhone must adjust only the iPhone's own audio volume,
        // never sending TV volume commands or hijacking AVAudioSession/MPVolumeView.
        for help in [Help.volume, Help.volumeUp, Help.volumeDown] {
            XCTAssertNil(help.tip, "\(help.id) must not advertise hardware side buttons")
            XCTAssertFalse(help.detail.localizedCaseInsensitiveContains("lateral"),
                           "\(help.id) detail must not claim side buttons control the TV")
        }
        XCTAssertNil(NSClassFromString("LanRemote.VolumeButtonHandler"),
                     "VolumeButtonHandler must not exist in the app target")
        XCTAssertNil(NSClassFromString("LanRemote.HiddenVolumeViewRepresentable"),
                     "HiddenVolumeViewRepresentable must not exist in the app target")
    }

    // MARK: - Deaf HTTP server, ping, IP conflict and DHCP relocation

    func testLoopbackAnswersICMPPing() async {
        let alive = await LGTVDiscovery.answersPing("127.0.0.1", timeout: 0.6)
        XCTAssertTrue(alive, "unprivileged SOCK_DGRAM ICMP ping must answer on loopback")
    }

    @MainActor
    func testDeafControlServerDropsKeysAuthRetryAndIPConflict() async throws {
        URLProtocol.registerClass(DeafTVStub.self)
        defer { URLProtocol.unregisterClass(DeafTVStub.self) }
        DeafTVStub.reset()

        var config = TVConfig.default
        config.host = DeafTVStub.host
        config.pairingKey = "123456"
        config.session = "111222"

        let client = LGTVClient(config: config, autoStart: false)
        var pingAlive = true
        var foreignOpen = false
        client.keyTransport = keysThroughURLSession
        client.pingProbe = { _ in pingAlive }
        client.foreignHostProbe = { _ in foreignOpen }
        client.locateProbe = { _ in nil }
        client.networkBlockProbe = { _, _ in nil }

        // 1. Deaf HTTP server with active ping: stays On (notAnswering), never marked Off
        DeafTVStub.set(.deaf)
        await client.refreshStatus()
        XCTAssertEqual(client.powerState, .on)
        XCTAssertTrue(client.notAnswering)
        XCTAssertFalse(client.ipConflict)

        // 2. Keys pressed while deaf are dropped: they don't wait for the control server, and nothing
        //    fires late once HTTP answers again
        client.sendKey(.volumeUp)
        client.sendKey(.volumeUp)
        client.sendKey(.volumeDown)
        try await Task.sleep(nanoseconds: 600_000_000)
        XCTAssertTrue(DeafTVStub.keys.isEmpty, "no key leaves while the control server is deaf")

        DeafTVStub.set(.answering, requireAuthOnce: true)
        try await Task.sleep(nanoseconds: 1_200_000_000)
        XCTAssertTrue(DeafTVStub.keys.isEmpty, "keys pressed while it was deaf never fire late")

        // 3. With HTTP back a new key goes out at once, across an expired session (401)
        client.sendKey(.volumeUp)
        let deadline = Date().addingTimeInterval(3)
        while DeafTVStub.keys.isEmpty, Date() < deadline {
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTAssertEqual(DeafTVStub.keys, [24])
        XCTAssertGreaterThanOrEqual(DeafTVStub.pairings, 1, "expired session (401) re-pairs before resending")
        XCTAssertEqual(client.powerState, .on)
        XCTAssertFalse(client.notAnswering)
        // the volume query that follows a volume key must be over before the next steps drive the status
        try await Task.sleep(nanoseconds: 900_000_000)
        DeafTVStub.clearKeys()

        // 4. During turningOn, ping before port 8080 answers keeps turningOn until HTTP 200 arrives
        DeafTVStub.set(.deaf)
        client.powerState = .turningOn
        await client.refreshStatus()
        XCTAssertEqual(client.powerState, .turningOn)
        DeafTVStub.set(.answering)
        await client.refreshStatus()
        XCTAssertEqual(client.powerState, .on)
        XCTAssertFalse(client.notAnswering)

        // 5. Standby: no HTTP and no ping -> Off
        DeafTVStub.set(.deaf)
        pingAlive = false
        await client.refreshStatus()
        XCTAssertEqual(client.powerState, .off)
        XCTAssertFalse(client.notAnswering)

        // 6. Right after power key, ping while shutting down does not flip the TV back to On
        pingAlive = true
        DeafTVStub.set(.answering)
        await client.refreshStatus()
        client.sendKey(.power)
        let offDeadline = Date().addingTimeInterval(3)
        while client.powerState != .off, Date() < offDeadline {
            try await Task.sleep(nanoseconds: 40_000_000)
        }
        XCTAssertEqual(client.powerState, .off)
        DeafTVStub.set(.deaf)
        await client.refreshStatus()
        XCTAssertEqual(client.powerState, .off, "post-power-off grace window ignores residual ping")

        // 7. Active IP conflict: TV just answered, then HTTP fails while ping + foreign non-TV service answer
        let activeClient = LGTVClient(config: config, autoStart: false)
        activeClient.pingProbe = { _ in true }
        activeClient.foreignHostProbe = { _ in foreignOpen }
        activeClient.locateProbe = { _ in nil }
        activeClient.networkBlockProbe = { _, _ in nil }
        DeafTVStub.set(.answering)
        await activeClient.refreshStatus()
        XCTAssertEqual(activeClient.powerState, .on)

        DeafTVStub.set(.deaf)
        foreignOpen = true
        await activeClient.refreshStatus()
        XCTAssertEqual(activeClient.powerState, .on)
        XCTAssertTrue(activeClient.notAnswering)
        XCTAssertTrue(activeClient.ipConflict)

        // 8. Old IP reassigned by DHCP while TV was off (never answered recently): treated as Off, not TV
        let coldClient = LGTVClient(config: config, autoStart: false)
        coldClient.pingProbe = { _ in true }
        coldClient.foreignHostProbe = { _ in true }
        coldClient.locateProbe = { _ in nil }
        coldClient.networkBlockProbe = { _, _ in nil }
        await coldClient.refreshStatus()
        XCTAssertEqual(coldClient.powerState, .off)
        XCTAssertFalse(coldClient.notAnswering)
        XCTAssertFalse(coldClient.ipConflict)

        // 9. When DHCP moved the TV to another IP while the old IP conflicts, relocation migrates seamlessly
        let migratingClient = LGTVClient(config: config, autoStart: false)
        migratingClient.pingProbe = { _ in true }
        migratingClient.foreignHostProbe = { _ in true }
        migratingClient.locateProbe = { _ in DeafTVStub.relocatedHost }
        migratingClient.networkBlockProbe = { _, _ in nil }
        await migratingClient.refreshStatus()
        XCTAssertEqual(migratingClient.config.host, DeafTVStub.relocatedHost)
        XCTAssertEqual(migratingClient.powerState, .on)
        XCTAssertFalse(migratingClient.notAnswering)
        XCTAssertFalse(migratingClient.ipConflict)
    }

    @MainActor
    func testBlockedNetworkIsNotReportedAsTVOff() async throws {
        URLProtocol.registerClass(DeafTVStub.self)
        defer { URLProtocol.unregisterClass(DeafTVStub.self) }
        DeafTVStub.reset()

        var config = TVConfig.default
        config.host = DeafTVStub.host
        config.pairingKey = "123456"
        config.session = "111222"
        let client = LGTVClient(config: config, autoStart: false)
        var block: NetworkBlock? = .localNetworkDenied
        client.pingProbe = { _ in false }
        client.foreignHostProbe = { _ in false }
        client.locateProbe = { _ in nil }
        client.networkBlockProbe = { _, _ in block }

        // 1. Nothing answers and iOS denies local network access: unknown and blocked, not "off"
        DeafTVStub.set(.deaf)
        await client.refreshStatus()
        XCTAssertEqual(client.networkBlock, .localNetworkDenied)
        XCTAssertEqual(client.powerState, .unknown)
        XCTAssertFalse(client.notAnswering)

        // 2. Keys don't queue up behind a blocked network: the banner is pointed at instead
        let pulse = client.attentionPulse
        client.sendKey(.volumeUp)
        XCTAssertEqual(client.attentionPulse, pulse + 1)
        try await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertTrue(DeafTVStub.keys.isEmpty)

        // 3. URLSession's "offline" error (what a denial looks like) skips the pointless subnet search
        //    (a fresh client: its first failure would search otherwise)
        let searches = Counter()
        let fresh = LGTVClient(config: config, autoStart: false)
        fresh.pingProbe = { _ in false }
        fresh.foreignHostProbe = { _ in false }
        fresh.locateProbe = { _ in searches.increment(); return nil }
        fresh.networkBlockProbe = { _, _ in .offWiFi }
        DeafTVStub.set(.offline)
        await fresh.refreshStatus()
        XCTAssertEqual(fresh.networkBlock, .offWiFi)
        XCTAssertEqual(fresh.powerState, .unknown)
        XCTAssertEqual(searches.value, 0, "no sweep while the iPhone can't reach the LAN")

        // 4. Access back: the TV answers and the block clears
        block = nil
        DeafTVStub.set(.answering)
        await client.refreshStatus()
        XCTAssertNil(client.networkBlock)
        XCTAssertEqual(client.powerState, .on)

        // 5. Nothing answers but the network is fine: standby, as before
        DeafTVStub.set(.deaf)
        await client.refreshStatus()
        XCTAssertNil(client.networkBlock)
        XCTAssertEqual(client.powerState, .off)
    }

    @MainActor
    func testTVRefusingTheAppAsksForPairingInsteadOfNotAnswering() async throws {
        URLProtocol.registerClass(DeafTVStub.self)
        defer { URLProtocol.unregisterClass(DeafTVStub.self) }
        DeafTVStub.reset()

        var config = TVConfig.default
        config.host = DeafTVStub.host
        config.pairingKey = nil
        let client = LGTVClient(config: config, autoStart: false)
        client.pingProbe = { _ in true }
        client.foreignHostProbe = { _ in false }
        client.locateProbe = { _ in nil }
        client.networkBlockProbe = { _, _ in nil }

        // No key saved: the TV answered 401, so it is on and only pairing helps
        DeafTVStub.set(.refusing)
        await client.refreshStatus()
        XCTAssertEqual(client.powerState, .on)
        XCTAssertTrue(client.needsPairing)
        XCTAssertFalse(client.notAnswering, "the TV did answer: not \"sem resposta\"")

        // A saved key the TV rejects: same
        client.config.pairingKey = "123456"
        await client.refreshStatus()
        XCTAssertTrue(client.needsPairing)

        // Paired again: cleared
        DeafTVStub.set(.answering)
        await client.refreshStatus()
        XCTAssertFalse(client.needsPairing)
        XCTAssertEqual(client.powerState, .on)
    }

    // MARK: - Keys: at once or not at all

    @MainActor
    private func client(for tv: LoopbackTV) -> LGTVClient {
        var config = TVConfig.default
        config.host = "127.0.0.1"
        config.port = Int(tv.port)
        config.pairingKey = "123456"
        config.session = "111222"
        let client = LGTVClient(config: config, autoStart: false)
        client.pingProbe = { _ in true }
        client.foreignHostProbe = { _ in false }
        client.locateProbe = { _ in nil }
        client.networkBlockProbe = { _, _ in nil }
        return client
    }

    private func seconds(from start: ContinuousClock.Instant, to end: ContinuousClock.Instant) -> Double {
        start.duration(to: end) / .seconds(1)
    }

    @MainActor
    private func wait(upTo limit: Double, until condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(limit)
        while !condition(), ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    @MainActor
    func testVolumeTapsFasterThanTheTVTakesThemLeaveNothingToTrickleOut() async throws {
        // The complaint: tapping the volume a few times, it kept climbing for seconds after the finger
        // had stopped. Every tap waited in line, 0.3 s apart.
        let tv = try LoopbackTV(level: 20)
        defer { tv.stop() }
        let client = client(for: tv)
        XCTAssertEqual(client.volumeLevel, 10, "what the app shows before it ever asked the TV")

        // 14 taps in 1.3 s, about twice what the TV takes
        let firstTap = ContinuousClock.now
        var lastTap = firstTap
        for tap in 0..<14 {
            if tap > 0 { try await Task.sleep(for: .milliseconds(100)) }
            lastTap = .now
            client.sendKey(.volumeUp)
        }
        XCTAssertGreaterThan(client.volumeLevel, 10, "the level shown follows the taps while they come")
        try await Task.sleep(for: .milliseconds(1500))

        let arrivals = tv.arrivals
        XCTAssertTrue(arrivals.allSatisfy { $0.code == TVKey.volumeUp.rawValue })
        XCTAssertGreaterThanOrEqual(arrivals.count, 6, "the TV gets a step every 0.15 s or so, not every 0.3 s")
        XCTAssertLessThanOrEqual(arrivals.count, 10, "never more keys than the TV takes in that time")
        let first = try XCTUnwrap(arrivals.first), last = try XCTUnwrap(arrivals.last)
        XCTAssertLessThan(seconds(from: firstTap, to: first.at), 0.15, "the first tap goes out at once")
        XCTAssertLessThan(seconds(from: lastTap, to: last.at), 0.30,
                          "after the last tap only the one tap that was waiting may still go out")
        for (earlier, later) in zip(arrivals, arrivals.dropFirst()) {
            XCTAssertGreaterThanOrEqual(seconds(from: earlier.at, to: later.at), 0.14, "the TV gets its rest between steps")
        }
        XCTAssertEqual(tv.discarded, 0, "no step comes sooner than the TV takes it")
        XCTAssertEqual(tv.level, 20 + arrivals.count)
        XCTAssertEqual(client.volumeLevel, tv.level, "once the taps stop the TV is asked for its volume")
    }

    @MainActor
    func testEveryUnhurriedTapLandsAtOnce() async throws {
        let tv = try LoopbackTV()
        defer { tv.stop() }
        let client = client(for: tv)

        var taps: [ContinuousClock.Instant] = []
        for tap in 0..<5 {
            if tap > 0 { try await Task.sleep(for: .milliseconds(250)) }
            taps.append(.now)
            client.sendKey(tap.isMultiple(of: 2) ? .volumeDown : .volumeUp)
        }
        try await Task.sleep(for: .milliseconds(400))

        let arrivals = tv.arrivals
        XCTAssertEqual(arrivals.map(\.code), [25, 24, 25, 24, 25], "four taps a second all reach the TV")
        for (tap, arrival) in zip(taps, arrivals) {
            XCTAssertLessThan(seconds(from: tap, to: arrival.at), 0.12, "each of them right when it was tapped")
        }
    }

    @MainActor
    func testTapsOnADeafTVAreDroppedNeverSentLate() async throws {
        let tv = try LoopbackTV()
        defer { tv.stop() }
        let client = client(for: tv)

        // The control server stops taking connections, as the real one does for a while now and then
        tv.set(.deaf)
        for tap in 0..<3 {
            if tap > 0 { try await Task.sleep(for: .milliseconds(60)) }
            client.sendKey(.volumeUp)
        }
        try await Task.sleep(for: .milliseconds(1200))
        XCTAssertTrue(tv.arrivals.isEmpty)

        tv.set(.answering)
        try await Task.sleep(for: .milliseconds(1500))
        XCTAssertTrue(tv.arrivals.isEmpty, "taps the TV couldn't take are gone: none goes out once it listens again")

        let tap = ContinuousClock.now
        client.sendKey(.volumeUp)
        try await wait(upTo: 1) { !tv.arrivals.isEmpty }
        let arrival = try XCTUnwrap(tv.arrivals.first)
        XCTAssertLessThan(seconds(from: tap, to: arrival.at), 0.3, "and the next tap works at once")
        try await Task.sleep(for: .milliseconds(600))
        XCTAssertEqual(tv.arrivals.count, 1)
    }

    @MainActor
    func testADroppedConnectionRequestCostsAQuarterSecondNotAFullOne() async throws {
        // The TV drops a SYN now and then and the kernel repeats it only a second later; a fresh
        // connection attempt gets through as soon as the TV listens again.
        let tv = try LoopbackTV()
        defer { tv.stop() }
        let client = client(for: tv)

        tv.set(.deaf)
        let tap = ContinuousClock.now
        client.sendKey(.volumeUp)
        try await Task.sleep(for: .milliseconds(300))
        tv.set(.answering)
        try await wait(upTo: 1) { !tv.arrivals.isEmpty }

        let arrival = try XCTUnwrap(tv.arrivals.first, "the tap is still fresh: it must get through")
        let landed = seconds(from: tap, to: arrival.at)
        XCTAssertGreaterThan(landed, 0.3)
        XCTAssertLessThan(landed, 0.8, "by a fresh attempt, not by the kernel repeating the first SYN after 1 s")
        try await Task.sleep(for: .milliseconds(1300))
        XCTAssertEqual(tv.arrivals.count, 1, "several connection attempts, one key")
    }

    @MainActor
    func testAKeyTheTVMayHaveRunIsNeverSentAgain() async throws {
        let tv = try LoopbackTV()
        defer { tv.stop() }
        let client = client(for: tv)
        client.keyAnswerTimeout = 0.4

        // The TV takes the request and doesn't answer
        tv.set(.silent)
        client.sendKey(.volumeUp)
        try await wait(upTo: 1) { !tv.arrivals.isEmpty }
        XCTAssertEqual(tv.arrivals.count, 1)
        try await Task.sleep(for: .milliseconds(1000))
        tv.set(.answering)
        try await Task.sleep(for: .milliseconds(800))
        XCTAssertEqual(tv.arrivals.count, 1, "no second request for the same tap")
    }

    @MainActor
    func testExpiredSessionPairsAgainAndSendsTheKeyOnce() async throws {
        let tv = try LoopbackTV()
        defer { tv.stop() }
        let client = client(for: tv)

        tv.refuseNextKey()
        client.sendKey(.volumeUp)
        try await wait(upTo: 1.5) { !tv.arrivals.isEmpty }
        XCTAssertEqual(tv.arrivals.map(\.code), [24])
        XCTAssertEqual(tv.pairings, 1)
        XCTAssertEqual(client.config.session, "99887766")
        XCTAssertEqual(client.powerState, .on)
    }

    @MainActor
    func testDifferentKeysGoOutInOrderWithTheTVsRestAndStaleOnesAreDropped() async throws {
        let tv = try LoopbackTV()
        defer { tv.stop() }
        let client = client(for: tv)

        // A channel number typed quickly: every digit, in order, 0.3 s apart
        client.sendKey(.digit1)
        client.sendKey(.digit2)
        client.sendKey(.digit5)
        try await Task.sleep(for: .milliseconds(1100))
        var arrivals = tv.arrivals
        XCTAssertEqual(arrivals.map(\.code), [3, 4, 7])
        for (earlier, later) in zip(arrivals, arrivals.dropFirst()) {
            XCTAssertGreaterThanOrEqual(seconds(from: earlier.at, to: later.at), 0.29)
        }

        // A TV slow to answer: the key behind would only leave 0.9 s after its tap, so it doesn't
        tv.clear()
        tv.answerDelay = 0.6
        client.sendKey(.digit1)
        client.sendKey(.digit2)
        try await Task.sleep(for: .milliseconds(1700))
        arrivals = tv.arrivals
        XCTAssertEqual(arrivals.map(\.code), [3], "a key that can't leave within 0.8 s of its tap is dropped")
    }

    func testKeyRequestBytesAndAnswerParsing() async throws {
        var request = URLRequest(url: try XCTUnwrap(URL(string: "http://192.0.2.100:8080/roap/api/command")))
        request.httpMethod = "POST"
        request.setValue("lg_roap_control/1.0.0 (iOS)", forHTTPHeaderField: "User-Agent")
        request.setValue("application/atom+xml", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data("<command/>".utf8)
        let message = String(decoding: try XCTUnwrap(TVKeyLink.httpMessage(for: request)), as: UTF8.self)
        XCTAssertEqual(message, "POST /roap/api/command HTTP/1.1\r\nHost: 192.0.2.100:8080\r\n"
                       + "Content-Type: application/atom+xml\r\nUser-Agent: lg_roap_control/1.0.0 (iOS)\r\n"
                       + "Content-Length: 10\r\n\r\n<command/>")

        let query = URLRequest(url: try XCTUnwrap(URL(string: "http://192.0.2.100:8080/roap/api/data?target=volume_info&session=1")))
        let queryMessage = String(decoding: try XCTUnwrap(TVKeyLink.httpMessage(for: query)), as: UTF8.self)
        XCTAssertEqual(queryMessage, "GET /roap/api/data?target=volume_info&session=1 HTTP/1.1\r\nHost: 192.0.2.100:8080\r\n\r\n")

        XCTAssertEqual(TVKeyLink.httpStatus(of: Data("HTTP/1.1 200 OK\r\nContent-Length: 2\r\n\r\nok".utf8)), 200)
        XCTAssertEqual(TVKeyLink.httpStatus(of: Data("HTTP/1.1 401 Unauthorized\r\n".utf8)), 401)
        XCTAssertNil(TVKeyLink.httpStatus(of: Data("HTTP/1.1 20".utf8)), "the status line isn't in yet")
        XCTAssertNil(TVKeyLink.httpStatus(of: Data("garbage\r\n".utf8)))
        XCTAssertNil(TVKeyLink.httpStatus(of: Data()))
        XCTAssertTrue(TVKeyLink.isWhole(Data("HTTP/1.1 200 OK\r\ncontent-length: 2\r\n\r\nok".utf8)))
        XCTAssertTrue(TVKeyLink.isWhole(Data("HTTP/1.1 401 Unauthorized\r\nContent-Length: 0\r\n\r\n".utf8)))
        XCTAssertFalse(TVKeyLink.isWhole(Data("HTTP/1.1 200 OK\r\nContent-Length: 2\r\n\r\no".utf8)))
        XCTAssertFalse(TVKeyLink.isWhole(Data("HTTP/1.1 200 OK\r\nContent-Length: 2\r\n".utf8)))
        XCTAssertFalse(TVKeyLink.isWhole(Data("HTTP/1.1 200 OK\r\n\r\nbody until the TV closes".utf8)))

        // Nothing listening: no connection, so nothing was sent, and the answer comes at the deadline
        let listener = try LoopbackListener()
        let closedPort = listener.port
        listener.close()
        var closed = URLRequest(url: try XCTUnwrap(URL(string: "http://127.0.0.1:\(closedPort)/roap/api/command")))
        closed.httpMethod = "POST"
        closed.httpBody = Data("<command/>".utf8)
        let started = ContinuousClock.now
        let delivery = await TVKeyLink.deliver(closed, connectWithin: 0.4, answerWithin: 1)
        XCTAssertEqual(delivery, .notSent)
        XCTAssertLessThan(seconds(from: started, to: .now), 0.8)
    }

    @MainActor
    func testKeyRequestKeepsTheUserAgentRuleOnItsOwnConnection() throws {
        // Keys no longer go through URLSession: the bytes on the wire must still follow the firmware's
        // rule (no "UDAP/2.0" in the User-Agent of a ROAP request, or the TV answers 400).
        let client = LGTVClient(config: TVConfig.default, autoStart: false)
        let request = try XCTUnwrap(client.createRequest(path: "/roap/api/command", method: "POST", body: "<command/>"))
        let message = String(decoding: try XCTUnwrap(TVKeyLink.httpMessage(for: request)), as: UTF8.self)
        XCTAssertTrue(message.hasPrefix("POST /roap/api/command HTTP/1.1\r\nHost: 192.0.2.100:8080\r\n"))
        XCTAssertTrue(message.contains("\r\nUser-Agent: lg_roap_control/1.0.0 (iOS)\r\n"))
        XCTAssertFalse(message.contains("UDAP/2.0"))
        XCTAssertTrue(message.contains("\r\nContent-Type: application/atom+xml\r\n"))
        XCTAssertTrue(message.contains("\r\nConnection: Close\r\n"))
        XCTAssertTrue(message.hasSuffix("\r\nContent-Length: 10\r\n\r\n<command/>"))
    }

    /// Opt-in check on the real TV of what the user sees: tapping the volume fast, the TV follows at
    /// once and stops when the taps stop. It moves the volume a few steps and puts it back, and never
    /// takes it above `LANREMOTE_LIVE_MAX_VOLUME` (9 unless set), so it can run with people in the room:
    /// `TEST_RUNNER_LANREMOTE_LIVE_TV=1 TEST_RUNNER_LANREMOTE_LIVE_HOST=<ip> TEST_RUNNER_LANREMOTE_LIVE_KEY=<pairing key> xcodebuild test ... -only-testing:LanRemoteTests/LanRemoteTests/testLiveVolumeTapsStopWhenTheFingerStops`
    @MainActor
    func testLiveVolumeTapsStopWhenTheFingerStops() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard environment["LANREMOTE_LIVE_TV"] == "1", let host = environment["LANREMOTE_LIVE_HOST"],
              let pairingKey = environment["LANREMOTE_LIVE_KEY"] else {
            throw XCTSkip("needs the LG NetCast TV: set LANREMOTE_LIVE_TV=1, LANREMOTE_LIVE_HOST and LANREMOTE_LIVE_KEY")
        }
        var config = TVConfig.default
        config.host = host
        config.pairingKey = pairingKey
        config.session = environment["LANREMOTE_LIVE_SESSION"]
        let client = LGTVClient(config: config, autoStart: false)
        await client.refreshStatus()
        guard client.powerState == .on, !client.notAnswering, !client.needsPairing, !client.isMuted else {
            throw XCTSkip("the TV must be on, paired and not muted")
        }
        let before = client.volumeLevel
        // Up only while the whole burst fits under the ceiling (a tap is a step at most); otherwise down,
        // or a shorter burst.
        let ceiling = Int(environment["LANREMOTE_LIVE_MAX_VOLUME"] ?? "") ?? 9
        var taps = Int(environment["LANREMOTE_LIVE_TAPS"] ?? "") ?? 10
        let roomUp = max(ceiling - before, 0)
        let tapped: TVKey = taps <= roomUp || roomUp >= before ? .volumeUp : .volumeDown
        taps = min(taps, tapped == .volumeUp ? roomUp : before)
        guard taps >= 3 else {
            throw XCTSkip("no room to move the volume: it is at \(before) and must stay within 0...\(ceiling)")
        }
        let session = client.config.session ?? ""
        let volumeURL = try XCTUnwrap(URL(string: "http://\(host):\(config.port)/roap/api/data?target=volume_info&session=\(session)"))

        // Every step the TV takes, timed by its answer to the key: the level shown moves right then.
        // Nothing else asks the TV anything while the taps go, as when the app is in use.
        var answered: [ContinuousClock.Instant] = []
        let levelShown = client.$volumeLevel.dropFirst().sink { _ in answered.append(.now) }

        let pace = Int(environment["LANREMOTE_LIVE_PACE_MS"] ?? "") ?? 125
        let firstTap = ContinuousClock.now
        var lastTap = firstTap
        for tap in 0..<taps {
            if tap > 0 { try await Task.sleep(for: .milliseconds(pace)) }
            lastTap = .now
            client.sendKey(tapped)
        }

        // From the last tap on, the TV's own volume about ten times a second: does it keep moving?
        var readings: [(at: ContinuousClock.Instant, level: Int)] = []
        await withTaskGroup(of: (at: ContinuousClock.Instant, level: Int)?.self) { group in
            for _ in 0..<32 {
                group.addTask {
                    var request = URLRequest(url: volumeURL)
                    request.timeoutInterval = 0.6
                    request.setValue("Close", forHTTPHeaderField: "Connection")
                    request.setValue("lg_roap_control/1.0.0 (iOS)", forHTTPHeaderField: "User-Agent")
                    guard let (data, _) = try? await URLSession.shared.data(for: request),
                          let text = LGTVClient.extractXMLTag(from: String(decoding: data, as: UTF8.self), tag: "level"),
                          let level = Int(text) else { return nil }
                    return (.now, level)
                }
                try? await Task.sleep(for: .milliseconds(95))
                if ContinuousClock.now > lastTap + .milliseconds(450) { levelShown.cancel() }
            }
            for await reading in group {
                if let reading { readings.append(reading) }
            }
        }
        levelShown.cancel()
        readings.sort { $0.at < $1.at }

        // Put the volume back, unhurried, whatever the checks below say
        for _ in 0..<4 {
            try await Task.sleep(for: .milliseconds(900))
            await client.refreshStatus()
            let off = client.volumeLevel - before
            if off == 0 { break }
            for _ in 0..<abs(off) {
                client.sendKey(off > 0 ? .volumeDown : .volumeUp)
                try await Task.sleep(for: .milliseconds(450))
            }
        }
        try await Task.sleep(for: .milliseconds(900))
        await client.refreshStatus()
        XCTAssertEqual(client.volumeLevel, before, "the test must leave the volume as it found it")

        let settled = try XCTUnwrap(readings.last, "the TV never told its volume")
        var lastMove: ContinuousClock.Instant?
        for (earlier, later) in zip(readings, readings.dropFirst()) where earlier.level != later.level {
            lastMove = later.at
        }
        let tail = lastMove.map { seconds(from: lastTap, to: $0) } ?? 0
        let firstAnswer = try XCTUnwrap(answered.first, "the TV took no key")
        let lastAnswer = try XCTUnwrap(answered.last)
        let times = answered.map { String(format: "%.2f", seconds(from: firstTap, to: $0)) }.joined(separator: " ")
        let after = readings.map { String(format: "%+.2f:%d", seconds(from: lastTap, to: $0.at), $0.level) }.joined(separator: " ")
        print("live volume: \(taps) taps in \(String(format: "%.2f", seconds(from: firstTap, to: lastTap))) s -> "
              + "\(answered.count) keys answered at [\(times)] s; the last one \(String(format: "%+.2f", seconds(from: lastTap, to: lastAnswer))) s "
              + "after the last tap; TV volume \(before) -> \(settled.level), last move \(String(format: "%+.2f", tail)) s after the last tap; "
              + "readings after the last tap [\(after)]")
        XCTAssertGreaterThanOrEqual(answered.count, 2)
        XCTAssertLessThanOrEqual(settled.level, max(ceiling, before), "never above the ceiling")
        XCTAssertLessThan(seconds(from: firstTap, to: firstAnswer), 0.35, "the first tap reaches the TV at once")
        XCTAssertLessThan(seconds(from: lastTap, to: lastAnswer), 0.45, "only the tap that was waiting goes out after the last one")
        XCTAssertLessThan(tail, 0.6, "the TV's volume stops moving when the taps stop")
        XCTAssertEqual(abs(settled.level - before), answered.count, "the TV took every step it answered: none came too soon for it")
    }
}

private final class DeafTVStub: URLProtocol {
    enum Mode { case deaf, answering, offline, refusing }
    static let host = "192.0.2.78"
    static let relocatedHost = "192.0.2.79"

    private static let lock = NSLock()
    private static var _mode: Mode = .deaf
    private static var _requireAuthOnce = false
    private static var _keys: [Int] = []
    private static var _pairings = 0

    static var keys: [Int] { lock.withLock { _keys } }
    static var pairings: Int { lock.withLock { _pairings } }

    static func reset() {
        lock.withLock {
            _mode = .deaf
            _requireAuthOnce = false
            _keys.removeAll()
            _pairings = 0
        }
    }

    static func clearKeys() {
        lock.withLock {
            _keys.removeAll()
            _pairings = 0
        }
    }

    static func set(_ mode: Mode, requireAuthOnce: Bool = false) {
        lock.withLock {
            _mode = mode
            _requireAuthOnce = requireAuthOnce
        }
    }

    override class func canInit(with request: URLRequest) -> Bool {
        let h = request.url?.host
        return h == host || h == relocatedHost
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url else { return }
        let isRelocated = (url.host == Self.relocatedHost)
        let mode = Self.lock.withLock { Self._mode }
        if !isRelocated, mode == .deaf {
            client?.urlProtocol(self, didFailWithError: URLError(.timedOut))
            return
        }
        if !isRelocated, mode == .offline {
            client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
            return
        }
        if !isRelocated, mode == .refusing {
            let resp = HTTPURLResponse(url: url, statusCode: 401, httpVersion: "HTTP/1.1", headerFields: nil)!
            client?.urlProtocol(self, didReceive: resp, cacheStoragePolicy: .notAllowed)
            client?.urlProtocolDidFinishLoading(self)
            return
        }

        if url.path.hasSuffix("/auth") || url.path.hasSuffix("/pairing") {
            Self.lock.withLock { Self._pairings += 1 }
            let xml = "<envelope><session>99887766</session></envelope>"
            let resp = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil)!
            client?.urlProtocol(self, didReceive: resp, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data(xml.utf8))
            client?.urlProtocolDidFinishLoading(self)
            return
        }

        let needs401 = !isRelocated && Self.lock.withLock { () -> Bool in
            if Self._requireAuthOnce {
                Self._requireAuthOnce = false
                return true
            }
            return false
        }
        if needs401 {
            let resp = HTTPURLResponse(url: url, statusCode: 401, httpVersion: "HTTP/1.1", headerFields: nil)!
            client?.urlProtocol(self, didReceive: resp, cacheStoragePolicy: .notAllowed)
            client?.urlProtocolDidFinishLoading(self)
            return
        }

        if url.path.hasSuffix("/command"), let code = Self.keyCode(in: Self.body(of: request)) {
            Self.lock.withLock { Self._keys.append(code) }
        }
        let xml = "<envelope><ROAPError>200</ROAPError><data><level>14</level><mute>false</mute></data></envelope>"
        let resp = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil)!
        client?.urlProtocol(self, didReceive: resp, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(xml.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    private static func body(of request: URLRequest) -> String {
        if let body = request.httpBody { return String(decoding: body, as: UTF8.self) }
        guard let stream = request.httpBodyStream else { return "" }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 1024)
        while stream.hasBytesAvailable {
            let n = stream.read(&buffer, maxLength: buffer.count)
            guard n > 0 else { break }
            data.append(buffer, count: n)
        }
        return String(decoding: data, as: UTF8.self)
    }

    private static func keyCode(in xml: String) -> Int? {
        guard let start = xml.range(of: "<value>"), let end = xml.range(of: "</value>") else { return nil }
        return Int(xml[start.upperBound..<end.lowerBound])
    }
}

/// A TV at `host`, inside the test: 401 to the quick probe (`volume_info` with no session), as a NetCast
/// answers it, and 200 to the client's own status queries. Nothing reaches the network, so the SSDP
/// search never runs either.
private final class TVStub: URLProtocol {
    static let host = "192.0.2.77"
    private static let lock = NSLock()
    private static var probeCount = 0
    static var probes: Int { lock.withLock { probeCount } }

    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.host == host
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url else { return }
        let isProbe = url.query == "target=volume_info"
        if isProbe {
            Self.lock.withLock { Self.probeCount += 1 }
        }
        let response = HTTPURLResponse(url: url, statusCode: isProbe ? 401 : 200, httpVersion: "HTTP/1.1", headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

/// A TCP listener on 127.0.0.1 at a port the kernel picks, for the connect scan.
private final class LoopbackListener {
    let fd: Int32
    let port: UInt16

    init() throws {
        let socketFD = socket(AF_INET, SOCK_STREAM, IPPROTO_TCP)
        guard socketFD >= 0 else { throw POSIXError(.EMFILE) }
        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = 0
        addr.sin_addr.s_addr = inet_addr("127.0.0.1")
        let bound = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(socketFD, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
        }
        guard bound == 0, listen(socketFD, 8) == 0 else {
            Darwin.close(socketFD)
            throw POSIXError(.EADDRINUSE)
        }
        var actual = sockaddr_in()
        var len = socklen_t(MemoryLayout<sockaddr_in>.size)
        _ = withUnsafeMutablePointer(to: &actual) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(socketFD, $0, &len) }
        }
        fd = socketFD
        port = UInt16(bigEndian: actual.sin_port)
    }

    func close() { Darwin.close(fd) }
}

private final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    var value: Int { lock.withLock { count } }
    func increment() { lock.withLock { count += 1 } }
}

/// Sends a key's request through URLSession, where the URLProtocol stubs of these tests answer it.
private let keysThroughURLSession: @Sendable (URLRequest, TimeInterval, TimeInterval) async -> KeyDelivery = { request, _, _ in
    guard let (_, response) = try? await URLSession.shared.data(for: request) else { return .notSent }
    return .answered(status: (response as? HTTPURLResponse)?.statusCode ?? 0)
}

/// A TV on 127.0.0.1 with a real TCP server, so keys reach it through the app's own connection code
/// (the URLProtocol stubs only see URLSession). It answers like the NetCast control server, notes when
/// each key arrived, discards a key repeated too soon as the real TV does, and can stop answering the
/// two ways the real one does: connection requests dropped (`deaf`: with its accept queue full the
/// kernel drops SYNs, without a refusal) or requests taken and never answered (`silent`).
private final class LoopbackTV: @unchecked Sendable {
    enum Mode { case answering, deaf, silent }

    let port: UInt16
    /// How soon a repeated key is discarded: on the xxLN5700, between 55 ms (lost) and 90 ms (kept).
    static let debounce: Duration = .milliseconds(90)

    private let listenFD: Int32
    private let lock = NSLock()
    private var mode: Mode = .answering
    private var stopped = false
    private var plugs: [Int32] = []
    private var held: [Int32] = []
    private var _arrivals: [(code: Int, at: ContinuousClock.Instant)] = []
    private var _discarded = 0
    private var _level: Int
    private var _pairings = 0
    private var _refuseNextKey = false
    private var _answerDelay: Double = 0

    var arrivals: [(code: Int, at: ContinuousClock.Instant)] { lock.withLock { _arrivals } }
    var discarded: Int { lock.withLock { _discarded } }
    var level: Int { lock.withLock { _level } }
    var pairings: Int { lock.withLock { _pairings } }
    var answerDelay: Double {
        get { lock.withLock { _answerDelay } }
        set { lock.withLock { _answerDelay = newValue } }
    }

    init(level: Int = 10) throws {
        _level = level
        let socketFD = socket(AF_INET, SOCK_STREAM, IPPROTO_TCP)
        guard socketFD >= 0 else { throw POSIXError(.EMFILE) }
        var on: Int32 = 1
        setsockopt(socketFD, SOL_SOCKET, SO_REUSEADDR, &on, socklen_t(MemoryLayout<Int32>.size))
        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = 0
        addr.sin_addr.s_addr = inet_addr("127.0.0.1")
        let bound = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(socketFD, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
        }
        // A queue of one: a single idle connection fills it, and the kernel drops the next SYNs.
        guard bound == 0, listen(socketFD, 1) == 0 else {
            Darwin.close(socketFD)
            throw POSIXError(.EADDRINUSE)
        }
        _ = fcntl(socketFD, F_SETFL, fcntl(socketFD, F_GETFL, 0) | O_NONBLOCK)
        var actual = sockaddr_in()
        var len = socklen_t(MemoryLayout<sockaddr_in>.size)
        _ = withUnsafeMutablePointer(to: &actual) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(socketFD, $0, &len) }
        }
        listenFD = socketFD
        port = UInt16(bigEndian: actual.sin_port)
        Thread.detachNewThread { [self] in serve() }
    }

    func set(_ newMode: Mode) {
        let (old, release) = lock.withLock { () -> (Mode, [Int32]) in
            let old = mode
            mode = newMode
            guard newMode == .answering else { return (old, []) }
            defer { held.removeAll() }
            return (old, held)
        }
        release.forEach { Darwin.close($0) }
        if newMode == .deaf, old != .deaf { plug() }
        if newMode != .deaf, old == .deaf { unplug() }
    }

    /// The next key gets a 401, as when the TV was switched off and on and the session died.
    func refuseNextKey() { lock.withLock { _refuseNextKey = true } }

    func clear() {
        lock.withLock {
            _arrivals.removeAll()
            _discarded = 0
        }
    }

    func stop() {
        let open = lock.withLock { () -> [Int32] in
            stopped = true
            defer { plugs.removeAll(); held.removeAll() }
            return plugs + held
        }
        open.forEach { Darwin.close($0) }
    }

    /// Fills the accept queue with idle connections of its own; `serve` accepts nothing while deaf.
    private func plug() {
        for _ in 0..<16 {
            let fd = socket(AF_INET, SOCK_STREAM, IPPROTO_TCP)
            guard fd >= 0 else { return }
            _ = fcntl(fd, F_SETFL, fcntl(fd, F_GETFL, 0) | O_NONBLOCK)
            var addr = sockaddr_in()
            addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
            addr.sin_family = sa_family_t(AF_INET)
            addr.sin_port = port.bigEndian
            addr.sin_addr.s_addr = inet_addr("127.0.0.1")
            _ = withUnsafePointer(to: &addr) { ptr in
                ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
            }
            lock.withLock { plugs.append(fd) }
            var pfd = pollfd(fd: fd, events: Int16(POLLOUT), revents: 0)
            if poll(&pfd, 1, 150) <= 0 { return }   // no answer to this one: the queue is full
        }
    }

    private func unplug() {
        let open = lock.withLock { () -> [Int32] in
            defer { plugs.removeAll() }
            return plugs
        }
        open.forEach { Darwin.close($0) }
    }

    private func serve() {
        while true {
            let (done, fd) = lock.withLock { () -> (Bool, Int32) in
                if stopped { return (true, -1) }
                return (false, mode == .deaf ? -1 : accept(listenFD, nil, nil))
            }
            if done { break }
            guard fd >= 0 else {
                usleep(2_000)
                continue
            }
            handle(fd)
        }
        Darwin.close(listenFD)
    }

    private func handle(_ fd: Int32) {
        var on: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
        _ = fcntl(fd, F_SETFL, fcntl(fd, F_GETFL, 0) & ~O_NONBLOCK)
        guard let request = Self.readRequest(fd) else {   // one of the plugs, or a client that gave up
            Darwin.close(fd)
            return
        }
        let arrived = ContinuousClock.now
        let isKey = request.target.hasSuffix("/command")
        let code = Self.value(of: "value", in: request.body).flatMap { Int($0) }

        var status = 200
        var body = "<?xml version=\"1.0\" encoding=\"utf-8\"?><envelope><ROAPError>200</ROAPError><ROAPErrorDetail>OK</ROAPErrorDetail></envelope>"
        let (keep, delay) = lock.withLock { () -> (Bool, Double) in
            if mode == .silent {
                if isKey, let code { _arrivals.append((code, arrived)) }
                held.append(fd)
                return (true, 0)
            }
            if isKey, let code {
                if _refuseNextKey {
                    _refuseNextKey = false
                    status = 401
                } else {
                    if let last = _arrivals.last, last.code == code, last.at.duration(to: arrived) < Self.debounce {
                        _discarded += 1
                    } else if code == TVKey.volumeUp.rawValue {
                        _level += 1
                    } else if code == TVKey.volumeDown.rawValue {
                        _level -= 1
                    }
                    _arrivals.append((code, arrived))
                }
            } else if request.target.hasSuffix("/auth") {
                _pairings += 1
                body = "<?xml version=\"1.0\" encoding=\"utf-8\"?><envelope><ROAPError>200</ROAPError><session>99887766</session></envelope>"
            } else if request.target.contains("volume_info") {
                body = "<?xml version=\"1.0\" encoding=\"utf-8\"?><envelope><ROAPError>200</ROAPError><data><mute>false</mute><minLevel>0</minLevel><maxLevel>100</maxLevel><level>\(_level)</level></data></envelope>"
            } else if request.target.contains("cur_channel") {
                body = "<?xml version=\"1.0\" encoding=\"utf-8\"?><envelope><ROAPError>200</ROAPError><data><major>65520</major><inputSourceName>HDMI2</inputSourceName></data></envelope>"
            }
            return (false, _answerDelay)
        }
        if keep { return }
        if delay > 0 { usleep(useconds_t(delay * 1_000_000)) }

        if status != 200 { body = "" }
        let head = "HTTP/1.1 \(status) \(status == 200 ? "OK" : "Unauthorized")\r\nContent-Type: text/xml; charset=utf-8\r\n"
            + "Content-Length: \(body.utf8.count)\r\nConnection: close\r\n\r\n"
        let bytes = Array((head + body).utf8)
        var sent = 0
        while sent < bytes.count {
            let n = bytes[sent...].withUnsafeBytes { send(fd, $0.baseAddress, $0.count, 0) }
            guard n > 0 else { break }
            sent += n
        }
        Darwin.close(fd)
    }

    /// The request on `fd`: its target and body, once the head and the body it announces are in.
    private static func readRequest(_ fd: Int32) -> (target: String, body: String)? {
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        let deadline = ContinuousClock.now + .milliseconds(800)
        while ContinuousClock.now < deadline {
            if let headEnd = data.range(of: Data("\r\n\r\n".utf8)) {
                let head = String(decoding: data[data.startIndex..<headEnd.lowerBound], as: UTF8.self)
                let lines = head.components(separatedBy: "\r\n")
                let length = lines.dropFirst()
                    .first { $0.lowercased().hasPrefix("content-length:") }
                    .flatMap { Int($0.dropFirst("content-length:".count).trimmingCharacters(in: .whitespaces)) } ?? 0
                if data.distance(from: headEnd.upperBound, to: data.endIndex) >= length {
                    let parts = lines[0].split(separator: " ")
                    guard parts.count >= 2 else { return nil }
                    return (String(parts[1]), String(decoding: data[headEnd.upperBound...], as: UTF8.self))
                }
            }
            var pfd = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
            guard poll(&pfd, 1, 100) > 0 else { continue }
            let n = recv(fd, &buffer, buffer.count, 0)
            guard n > 0 else { return nil }
            data.append(buffer, count: n)
        }
        return nil
    }

    private static func value(of tag: String, in xml: String) -> String? {
        guard let start = xml.range(of: "<\(tag)>"), let end = xml.range(of: "</\(tag)>") else { return nil }
        return String(xml[start.upperBound..<end.lowerBound])
    }
}
