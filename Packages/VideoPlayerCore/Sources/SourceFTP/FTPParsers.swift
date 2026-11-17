import Foundation
import VideoPlayerCore

/// Pure parsing helpers for FTP replies and directory listings.
enum FTPParsers {
    // MARK: Paths

    static func join(_ parent: String, _ name: String) -> String {
        let p = parent == "/" ? "" : parent
        return p + "/" + name
    }

    static func parent(of path: String) -> String {
        var parts = path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        guard !parts.isEmpty else { return "/" }
        parts.removeLast()
        return "/" + parts.joined(separator: "/")
    }

    static func lastComponent(_ name: String) -> String {
        name.split(separator: "/", omittingEmptySubsequences: true).last.map(String.init) ?? name
    }

    // MARK: Regex helper

    static func groups(_ pattern: String, in text: String) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let ns = text as NSString
        guard let m = regex.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)) else { return nil }
        return (0..<m.numberOfRanges).map { i in
            let r = m.range(at: i)
            return r.location == NSNotFound ? "" : ns.substring(with: r)
        }
    }

    // MARK: Passive replies

    /// `227 Entering Passive Mode (h1,h2,h3,h4,p1,p2)`
    static func parsePASV(_ text: String) -> (host: String, port: Int)? {
        guard let g = groups(#"(\d+),(\d+),(\d+),(\d+),(\d+),(\d+)"#, in: text), g.count == 7,
              let p1 = Int(g[5]), let p2 = Int(g[6]), p1 < 256, p2 < 256 else { return nil }
        return ("\(g[1]).\(g[2]).\(g[3]).\(g[4])", p1 * 256 + p2)
    }

    /// `229 Entering Extended Passive Mode (|||port|)` (the delimiter may be any character)
    static func parseEPSV(_ text: String) -> Int? {
        guard let g = groups(#"\((.)\1\1(\d+)\1\)"#, in: text), g.count == 3, let port = Int(g[2]), port > 0, port < 65536 else { return nil }
        return port
    }

    // MARK: Dates

    private static var utc: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }

    /// `YYYYMMDDHHMMSS[.sss]` in UTC (MDTM and MLSx `modify`).
    static func parseMDTM(_ text: String) -> Date? {
        let digits = text.prefix { $0.isNumber }
        guard digits.count >= 14 else { return nil }
        let s = Array(digits)
        func n(_ a: Int, _ b: Int) -> Int { Int(String(s[a..<b])) ?? 0 }
        var comps = DateComponents()
        comps.year = n(0, 4); comps.month = n(4, 6); comps.day = n(6, 8)
        comps.hour = n(8, 10); comps.minute = n(10, 12); comps.second = n(12, 14)
        return utc.date(from: comps)
    }

    private static let months = ["jan": 1, "feb": 2, "mar": 3, "apr": 4, "may": 5, "jun": 6,
                                 "jul": 7, "aug": 8, "sep": 9, "oct": 10, "nov": 11, "dec": 12]

    // MARK: MLSD / MLST

    /// One MLSx line: `fact=value;fact=value; name`. Returns nil for `cdir`, `pdir` and unparsable lines.
    static func parseMLSLine(_ rawLine: String, parent: String) -> SourceEntry? {
        var line = rawLine
        if line.hasSuffix("\r") { line.removeLast() }
        let trimmed = Substring(line)
        guard let space = trimmed.firstIndex(of: " ") else { return nil }
        let factsPart = String(trimmed[trimmed.startIndex..<space]).trimmingCharacters(in: .whitespaces)
        let name = String(trimmed[trimmed.index(after: space)...])
        var facts: [String: String] = [:]
        for fact in factsPart.split(separator: ";") {
            guard let eq = fact.firstIndex(of: "=") else { continue }
            facts[fact[fact.startIndex..<eq].lowercased()] = String(fact[fact.index(after: eq)...])
        }
        guard let type = facts["type"]?.lowercased() else { return nil }
        if type == "cdir" || type == "pdir" { return nil }
        let leaf = lastComponent(name)
        if leaf == "." || leaf == ".." || leaf.isEmpty { return nil }
        let isDir = type == "dir"
        return SourceEntry(
            path: name.hasPrefix("/") ? name : join(parent, leaf),
            name: leaf,
            isDirectory: isDir,
            size: isDir ? nil : facts["size"].flatMap { Int64($0) },
            modified: facts["modify"].flatMap(parseMDTM)
        )
    }

    static func parseMLSD(_ text: String, parent: String) -> [SourceEntry] {
        text.split(whereSeparator: { $0.isNewline }).compactMap { line in   // "\r\n" is one Character in Swift
            var l = String(line)
            if l.hasPrefix(" ") { l.removeFirst() }   // MLST payload lines start with one space; MLSD lines do not
            return parseMLSLine(l, parent: parent)
        }
    }

    // MARK: LIST (Unix and DOS formats)

    static func parseList(_ text: String, parent: String, now: Date = Date()) -> [SourceEntry] {
        text.split(whereSeparator: { $0.isNewline }).compactMap { parseListLine(String($0), parent: parent, now: now) }
    }

    static func parseListLine(_ line: String, parent: String, now: Date) -> SourceEntry? {
        if line.isEmpty || line.lowercased().hasPrefix("total ") { return nil }
        // Unix: drwxr-xr-x 2 user group 4096 Mar  2 10:00 name   (group column optional)
        if let g = groups(#"^([\-dlcbps])[rwxsStTl\-\?]{9}[+@.]?\s+\d+\s+(?:\S+\s+)?\S+\s+(\d+)\s+([A-Za-z]{3})\s+(\d{1,2})\s+(\d{4}|\d{1,2}:\d{2})\s+(.+)$"#, in: line), g.count == 7 {
            var name = g[6]
            let kind = g[1]
            if kind == "l", let arrow = name.range(of: " -> ") { name = String(name[name.startIndex..<arrow.lowerBound]) }
            let leaf = lastComponent(name)
            if leaf == "." || leaf == ".." || leaf.isEmpty { return nil }
            let isDir = kind == "d"
            return SourceEntry(path: join(parent, leaf), name: leaf, isDirectory: isDir,
                               size: isDir ? nil : Int64(g[2]),
                               modified: unixDate(month: g[3], day: g[4], yearOrTime: g[5], now: now))
        }
        // DOS: 03-02-24  10:00AM       <DIR>          name   or   03-02-2024 10:00AM 123 name
        if let g = groups(#"^(\d{2})-(\d{2})-(\d{2,4})\s+(\d{1,2}):(\d{2})\s*([AaPp][Mm])?\s+(<DIR>|\d+)\s+(.+)$"#, in: line), g.count == 9 {
            let leaf = lastComponent(g[8])
            if leaf == "." || leaf == ".." || leaf.isEmpty { return nil }
            var year = Int(g[3]) ?? 1970
            if g[3].count == 2 { year += year < 70 ? 2000 : 1900 }
            var hour = Int(g[4]) ?? 0
            let ampm = g[6].lowercased()
            if ampm == "pm", hour < 12 { hour += 12 }
            if ampm == "am", hour == 12 { hour = 0 }
            var c = DateComponents()
            c.year = year; c.month = Int(g[1]); c.day = Int(g[2]); c.hour = hour; c.minute = Int(g[5]); c.second = 0
            let isDir = g[7] == "<DIR>"
            return SourceEntry(path: join(parent, leaf), name: leaf, isDirectory: isDir,
                               size: isDir ? nil : Int64(g[7]), modified: utc.date(from: c))
        }
        return nil
    }

    private static func unixDate(month: String, day: String, yearOrTime: String, now: Date) -> Date? {
        guard let m = months[month.lowercased()], let d = Int(day) else { return nil }
        var c = DateComponents()
        c.month = m; c.day = d
        if yearOrTime.contains(":") {
            let hm = yearOrTime.split(separator: ":")
            c.hour = Int(hm[0]); c.minute = Int(hm[1])
            let nowYear = utc.component(.year, from: now)
            c.year = nowYear
            if let date = utc.date(from: c), date > now.addingTimeInterval(86_400) { c.year = nowYear - 1 }
        } else {
            c.year = Int(yearOrTime)
        }
        return utc.date(from: c)
    }
}
