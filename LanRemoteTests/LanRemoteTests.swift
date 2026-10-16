import XCTest
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
}
