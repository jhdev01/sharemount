import XCTest

final class SMBShareListTests: XCTestCase {

    private let sample = """
    Share                                           Type    Comments
    -------------------------------
    IPC$                                            Pipe    IPC Service (Samba 4.15)
    Media                                           Disk    
    My Backups                                      Disk    Time Machine Disk
    Office Printer                                  Printer 
    ADMIN$                                          Disk    Remote Admin

    5 shares listed
    """

    func testParsesDiskSharesOnly() {
        XCTAssertEqual(SMBShareList.diskShares(fromSmbutilOutput: sample), ["Media", "My Backups"])
    }

    func testNameLongerThanColumn() {
        let longName = String(repeating: "x", count: 50)
        let output = """
        Share                                           Type    Comments
        -------------------------------
        \(longName) Disk    
        """
        XCTAssertEqual(SMBShareList.diskShares(fromSmbutilOutput: output), [longName])
    }

    func testOutputWithoutHeader() {
        XCTAssertEqual(SMBShareList.diskShares(fromSmbutilOutput: "Photos   Disk   \nIPC$  Pipe"), ["Photos"])
    }

    func testEmptyOutput() {
        XCTAssertEqual(SMBShareList.diskShares(fromSmbutilOutput: ""), [])
    }

    func testSmbutilURL() {
        XCTAssertEqual(SMBShareList.smbutilURL(host: "nas.local", credentials: nil), "//nas.local")
        XCTAssertEqual(
            SMBShareList.smbutilURL(host: "nas.local",
                                    credentials: Credentials(username: "joey", password: "p@ss:w/rd")),
            "//joey:p%40ss%3Aw%2Frd@nas.local")
        XCTAssertEqual(
            SMBShareList.smbutilURL(host: "pc", credentials: Credentials(username: "CORP;joey", password: "")),
            "//CORP;joey@pc")
    }
}
