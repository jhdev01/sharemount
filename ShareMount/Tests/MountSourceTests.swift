import XCTest

final class MountSourceTests: XCTestCase {

    private func share(_ location: String) -> Share {
        Share(displayName: "Test", location: location)
    }

    func testParsesDeviceNames() {
        let plain = MountSource(mntFromName: "//192.168.1.10/Media")
        XCTAssertEqual(plain?.host, "192.168.1.10")
        XCTAssertEqual(plain?.shareName, "Media")

        let withUser = MountSource(mntFromName: "//alice@NAS.local/Media")
        XCTAssertEqual(withUser?.host, "nas.local")

        let withDomain = MountSource(mntFromName: "//CORP;alice@fileserver:445/Docs/sub")
        XCTAssertEqual(withDomain?.host, "fileserver")
        XCTAssertEqual(withDomain?.shareName, "Docs")
    }

    func testRejectsNonSMBDevices() {
        XCTAssertNil(MountSource(mntFromName: "/dev/disk3s1"))
        XCTAssertNil(MountSource(mntFromName: "map auto_home"))
        XCTAssertNil(MountSource(mntFromName: "//hostonly"))
    }

    func testHostMustMatchExactly() {
        // Regression: "192.168.1.1" used to match mounts from "192.168.1.10".
        let source = MountSource(mntFromName: "//alice@192.168.1.10/Media")!
        XCTAssertFalse(source.matches(share("192.168.1.1/Media")))
        XCTAssertTrue(source.matches(share("192.168.1.10/Media")))
    }

    func testShareNameMatchIsCaseInsensitiveAndDecoded() {
        let source = MountSource(mntFromName: "//alice@nas.local/my%20share")!
        XCTAssertTrue(source.matches(share("smb://nas.local/My Share")))
        XCTAssertFalse(source.matches(share("smb://nas.local/My Share 2")))
    }

    func testBonjourNameMatchesLocalName() {
        let source = MountSource(mntFromName: "//alice@NAS._smb._tcp.local/Media")!
        XCTAssertTrue(source.matches(share("nas.local/Media")))
    }
}
