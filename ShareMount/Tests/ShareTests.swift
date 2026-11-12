import XCTest

final class ShareTests: XCTestCase {

    private func share(_ location: String) -> Share {
        Share(displayName: "Test", location: location)
    }

    func testAcceptsCommonLocationFormats() {
        for location in ["smb://192.168.1.10/Media", "192.168.1.10/Media",
                         "//192.168.1.10/Media", "\\\\192.168.1.10\\Media",
                         "  SMB://192.168.1.10/Media  "] {
            let s = share(location)
            XCTAssertEqual(s.url?.absoluteString, "smb://192.168.1.10/Media", location)
            XCTAssertEqual(s.host, "192.168.1.10", location)
            XCTAssertEqual(s.shareName, "Media", location)
        }
    }

    func testShareNameWithSpacesIsEncoded() {
        let s = share("smb://nas.local/My Share")
        XCTAssertEqual(s.url?.absoluteString, "smb://nas.local/My%20Share")
        XCTAssertEqual(s.shareName, "My Share")
    }

    func testAlreadyEncodedLocationIsNotDoubleEncoded() {
        let s = share("smb://nas.local/My%20Share")
        XCTAssertEqual(s.url?.absoluteString, "smb://nas.local/My%20Share")
        XCTAssertEqual(s.shareName, "My Share")
    }

    func testUserInLocation() {
        let s = share("smb://alice@nas.local/Media")
        XCTAssertEqual(s.host, "nas.local")
        XCTAssertEqual(s.shareName, "Media")
    }

    func testInvalidLocations() {
        XCTAssertNil(share("").url)
        XCTAssertNil(share("   ").url)
        XCTAssertNil(share("smb://").url)
        XCTAssertNil(share("smb://nas.local").shareName)
    }

    func testNormalizedHost() {
        XCTAssertEqual(Share.normalizedHost("NAS.local."), "nas.local")
        XCTAssertEqual(Share.normalizedHost("NAS._smb._tcp.local"), "nas.local")
        XCTAssertEqual(Share.normalizedHost("[fe80::1]"), "fe80::1")
    }
}

final class ShareRefersToTests: XCTestCase {
    func testRefersTo() {
        let share = Share(displayName: "x", location: "smb://NAS.local/My Share")
        XCTAssertTrue(share.refersTo(host: "nas.local", shareName: "my share"))
        XCTAssertFalse(share.refersTo(host: "nas2.local", shareName: "My Share"))
    }
}

final class ShareCodingTests: XCTestCase {
    /// Settings saved before `autoConnect` existed must still load.
    func testDecodesSettingsWithoutAutoConnect() throws {
        let json = #"[{"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","displayName":"Media","location":"nas/Media"}]"#
        let shares = try JSONDecoder().decode([Share].self, from: Data(json.utf8))
        XCTAssertEqual(shares.count, 1)
        XCTAssertEqual(shares[0].displayName, "Media")
        XCTAssertTrue(shares[0].autoConnect)   // on by default
    }

    func testRoundTripKeepsAutoConnect() throws {
        let share = Share(displayName: "Media", location: "nas/Media", autoConnect: false)
        let decoded = try JSONDecoder().decode(Share.self, from: JSONEncoder().encode(share))
        XCTAssertEqual(decoded, share)
    }
}
