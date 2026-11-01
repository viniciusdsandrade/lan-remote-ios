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

    // MARK: - Deaf HTTP server, ping, IP conflict and DHCP relocation

    func testLoopbackAnswersICMPPing() async {
        let alive = await LGTVDiscovery.answersPing("127.0.0.1", timeout: 0.6)
        XCTAssertTrue(alive, "unprivileged SOCK_DGRAM ICMP ping must answer on loopback")
    }

    @MainActor
    func testDeafControlServerQueueingAuthRetryAndIPConflict() async throws {
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

        // 2. Keys pressed while deaf wait and fire in exact FIFO order once HTTP returns (even across a 401)
        client.sendKey(.volumeUp)
        client.sendKey(.volumeUp)
        client.sendKey(.volumeDown)
        try await Task.sleep(nanoseconds: 1_200_000_000)
        XCTAssertTrue(DeafTVStub.keys.isEmpty, "no key leaves while the control server is deaf")

        DeafTVStub.set(.answering, requireAuthOnce: true)
        let deadline = Date().addingTimeInterval(6)
        while DeafTVStub.keys.count < 3, Date() < deadline {
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        XCTAssertEqual(DeafTVStub.keys, [24, 24, 25], "queued keys arrive in order once HTTP answers")
        XCTAssertGreaterThanOrEqual(DeafTVStub.pairings, 1, "expired session (401) re-pairs before resending")
        XCTAssertEqual(client.powerState, .on)
        XCTAssertFalse(client.notAnswering)

        // 3. Stale keys older than keyPatience are dropped instead of firing late
        DeafTVStub.clearKeys()
        DeafTVStub.set(.deaf)
        client.keyPatience = 1.1
        client.sendKey(.mute)
        client.sendKey(.home)
        try await Task.sleep(nanoseconds: 2_300_000_000)
        DeafTVStub.set(.answering)
        await client.refreshStatus()
        try await Task.sleep(nanoseconds: 400_000_000)
        XCTAssertTrue(DeafTVStub.keys.isEmpty, "stale keys older than keyPatience must be dropped")
        client.keyPatience = 15

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
