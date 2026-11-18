import XCTest

final class AwayRouteTests: XCTestCase {

    private let statusJSON = #"""
    {"Version":"1.76.1","BackendState":"Running",
     "Self":{"HostName":"Joeys-MacBook-Air","DNSName":"joeys-macbook-air.tail1234.ts.net.","TailscaleIPs":["100.101.1.2"],"Online":true},
     "Peer":{
       "nodekey:aaa":{"HostName":"Halderman-iMac","DNSName":"halderman-imac.tail1234.ts.net.","TailscaleIPs":["100.88.1.5","fd7a:115c::5"],"Online":true},
       "nodekey:bbb":{"HostName":"Office NAS","DNSName":"","TailscaleIPs":["100.70.2.9"],"Online":false}
     }}
    """#

    private var status: TailscaleStatus { TailscaleStatus.parse(Data(statusJSON.utf8))! }

    func testParsesStatus() {
        XCTAssertTrue(status.isRunning)
        XCTAssertEqual(status.Peer?.count, 2)
        XCTAssertFalse(TailscaleStatus.parse(Data(#"{"BackendState":"Stopped"}"#.utf8))!.isRunning)
    }

    func testFindsPeerByLocalHostName() {
        let share = Share(displayName: "5 TB", location: "smb://halderman-imac.local/5 TB")
        XCTAssertEqual(status.awayHost(for: share), "halderman-imac.tail1234.ts.net")
    }

    func testFindsPeerByFriendlyNameAndFallsBackToIP() {
        let share = Share(displayName: "Backups", location: "192.168.1.30/Backups", serverName: "Office NAS")
        XCTAssertEqual(status.awayHost(for: share), "100.70.2.9")
    }

    func testNoMatchForUnknownComputer() {
        let share = Share(displayName: "x", location: "smb://other-mac.local/x")
        XCTAssertNil(status.awayHost(for: share))
    }

    func testNameKeys() {
        XCTAssertEqual(TailscaleStatus.key("Joey's iMac"), "joeys-imac")
        XCTAssertEqual(TailscaleStatus.key("Halderman-iMac.local"), "halderman-imac")
    }

    func testAwayShareSwapsOnlyTheHost() {
        let share = Share(displayName: "5 TB", location: "smb://halderman-imac.local/5 TB",
                          awayHost: "halderman-imac.tail1234.ts.net")
        let away = share.awayShare
        XCTAssertEqual(away?.id, share.id)
        XCTAssertEqual(away?.host, "halderman-imac.tail1234.ts.net")
        XCTAssertEqual(away?.shareName, "5 TB")
        XCTAssertNil(Share(displayName: "x", location: "nas/x", awayHost: "").awayShare)   // turned off
        XCTAssertNil(Share(displayName: "x", location: "nas/x").awayShare)                 // not set
    }

    func testRouteNames() {
        XCTAssertEqual(Share.awayRouteName(for: "halderman-imac.tail1234.ts.net"), "Tailscale")
        XCTAssertEqual(Share.awayRouteName(for: "100.88.1.5"), "Tailscale")
        XCTAssertEqual(Share.awayRouteName(for: "myhome.example.com"), "away address")
    }

    func testMountFromEitherHostMatches() {
        let share = Share(displayName: "5 TB", location: "smb://halderman-imac.local/5 TB",
                          awayHost: "halderman-imac.tail1234.ts.net")
        let home = MountSource(mntFromName: "//joey@halderman-imac.local/5%20TB")!
        let away = MountSource(mntFromName: "//joey@halderman-imac.tail1234.ts.net/5%20TB")!
        XCTAssertTrue(home.matches(share)); XCTAssertFalse(home.isAway(for: share))
        XCTAssertTrue(away.matches(share)); XCTAssertTrue(away.isAway(for: share))
    }

    func testAwayHostSurvivesSaving() throws {
        let share = Share(displayName: "x", location: "nas/x", awayHost: "nas.tail1234.ts.net")
        let decoded = try JSONDecoder().decode(Share.self, from: JSONEncoder().encode(share))
        XCTAssertEqual(decoded.awayHost, "nas.tail1234.ts.net")
    }
}
