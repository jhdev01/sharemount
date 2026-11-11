import Foundation

/// Helpers for talking to `/usr/bin/smbutil view`, which lists the shares a
/// server offers. Kept free of AppKit so it can be unit-tested.
enum SMBShareList {

    /// The `//user:password@host` argument for `smbutil view`, with the user
    /// name and password percent-encoded so characters like `@` and `:` survive.
    static func smbutilURL(host: String, credentials: Credentials?) -> String {
        var url = "//"
        if let credentials, !credentials.username.isEmpty {
            url += encode(credentials.username, .urlUserAllowed)
            if !credentials.password.isEmpty {
                url += ":" + encode(credentials.password, .urlPasswordAllowed)
            }
            url += "@"
        }
        return url + host
    }

    /// Names of the disk shares in `smbutil view` output. Output looks like:
    ///
    ///     Share                                           Type    Comments
    ///     -------------------------------
    ///     IPC$                                            Pipe    IPC Service
    ///     Media                                           Disk
    ///     My Backups                                      Disk    Time Machine
    ///
    /// Hidden admin shares (names ending in `$`), pipes and printers are skipped.
    static func diskShares(fromSmbutilOutput output: String) -> [String] {
        var typeColumn: Int?
        var names: [String] = []
        for line in output.components(separatedBy: .newlines) {
            if typeColumn == nil, line.hasPrefix("Share"), let type = line.range(of: "Type") {
                typeColumn = line.distance(from: line.startIndex, to: type.lowerBound)
                continue
            }
            guard let (name, type) = split(line, typeColumn: typeColumn),
                  type.caseInsensitiveCompare("Disk") == .orderedSame,
                  !name.isEmpty, !name.hasSuffix("$"), !names.contains(name)
            else { continue }
            names.append(name)
        }
        return names
    }

    /// Split a row into (share name, type). Uses the header's "Type" column
    /// when the row lines up with it, else looks for the type keyword.
    private static func split(_ line: String, typeColumn: Int?) -> (String, String)? {
        let chars = Array(line)
        if let column = typeColumn, column > 0, chars.count > column, chars[column - 1] == " " {
            let name = String(chars[..<column]).trimmingCharacters(in: .whitespaces)
            let type = String(chars[column...]).split(separator: " ").first.map(String.init) ?? ""
            return (name, type)
        }
        // Long name pushed past the column (or no header): find the type word.
        guard let match = line.range(of: #"\s+(Disk|Pipe|Printer|Device)(\s|$)"#,
                                     options: .regularExpression)
        else { return nil }
        let name = line[..<match.lowerBound].trimmingCharacters(in: .whitespaces)
        let type = line[match].trimmingCharacters(in: .whitespaces)
        return (name, type)
    }

    private static func encode(_ text: String, _ allowed: CharacterSet) -> String {
        var set = allowed
        set.remove(charactersIn: ":@/?#")   // keep ";" so "DOMAIN;user" works
        return text.addingPercentEncoding(withAllowedCharacters: set) ?? text
    }
}
