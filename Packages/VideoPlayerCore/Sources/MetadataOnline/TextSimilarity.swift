import Foundation

/// Title normalisation and similarity used by the matcher. Pure functions, covered by tests.
public enum TitleText {
    private static let articles: Set<String> = ["the", "a", "an"]
    private static let romanNumerals: [String: String] = ["ii": "2", "iii": "3", "iv": "4", "v": "5", "vi": "6", "vii": "7", "viii": "8", "ix": "9"]

    /// Lower-case, accents folded, "&" read as "and", apostrophes dropped, other punctuation as spaces,
    /// runs of single letters joined ("S.H.I.E.L.D." gives "shield"), a leading "the/a/an" or a trailing
    /// ", The" removed, roman numerals II to IX turned into digits.
    public static func normalize(_ title: String) -> String {
        var s = title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        for suffix in [", the", ", a", ", an"] where s.hasSuffix(suffix) {
            s = String(s.dropLast(suffix.count))
            break
        }
        s = s.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
        s = s.replacingOccurrences(of: "&", with: " and ")
        for apostrophe in ["'", "\u{2019}", "\u{2018}", "`"] { s = s.replacingOccurrences(of: apostrophe, with: "") }
        let mapped = s.unicodeScalars.map { CharacterSet.alphanumerics.contains($0) ? Character($0) : " " }
        var tokens = String(mapped).split(separator: " ").map(String.init)

        // Join runs of two or more single letters.
        var joined: [String] = []
        var run = ""
        func flush() {
            if !run.isEmpty { joined.append(run); run = "" }
        }
        for t in tokens {
            if t.count == 1, let c = t.first, c.isLetter {
                run += t
            } else {
                flush()
                joined.append(t)
            }
        }
        flush()
        tokens = joined

        if tokens.count > 1, let first = tokens.first, articles.contains(first) { tokens.removeFirst() }
        if tokens.count > 1 { tokens = tokens.map { romanNumerals[$0] ?? $0 } }
        return tokens.joined(separator: " ")
    }

    // MARK: Similarity

    /// 0...1. 1 means the normalised titles are the same (spacing ignored).
    public static func similarity(_ a: String, _ b: String) -> Double {
        normalizedSimilarity(normalize(a), normalize(b))
    }

    static func normalizedSimilarity(_ na: String, _ nb: String) -> Double {
        if na.isEmpty || nb.isEmpty { return 0 }
        if na == nb { return 1 }
        let ca = na.replacingOccurrences(of: " ", with: "")
        let cb = nb.replacingOccurrences(of: " ", with: "")
        if ca == cb { return 0.98 }
        let chars = (Array(na), Array(nb))
        // Jaro-Winkler is generous to a short string inside a long one, so it is scaled by the length ratio.
        let lengthRatio = Double(min(chars.0.count, chars.1.count)) / Double(max(chars.0.count, chars.1.count))
        var score = max(jaroWinkler(chars.0, chars.1) * lengthRatio.squareRoot(), 1 - Double(levenshtein(chars.0, chars.1)) / Double(max(chars.0.count, chars.1.count)))
        // One title wholly inside the other at word boundaries ("Star Wars" in "Star Wars A New Hope").
        let wa = na.split(separator: " ").map(String.init)
        let wb = nb.split(separator: " ").map(String.init)
        let (short, long) = wa.count <= wb.count ? (wa, wb) : (wb, wa)
        if short.count < long.count, containsSequence(long, short) {
            score = max(score, short.count >= 2 ? 0.85 : 0.7)
        }
        return min(score, 0.97)
    }

    /// Best similarity of a query against a title and its alternatives.
    public static func bestSimilarity(query: String, names: [String]) -> Double {
        let q = normalize(query)
        return names.map { normalizedSimilarity(q, normalize($0)) }.max() ?? 0
    }

    private static func containsSequence(_ long: [String], _ short: [String]) -> Bool {
        guard !short.isEmpty, short.count <= long.count else { return false }
        for start in 0...(long.count - short.count) where Array(long[start..<(start + short.count)]) == short { return true }
        return false
    }

    static func levenshtein(_ a: [Character], _ b: [Character]) -> Int {
        if a.isEmpty { return b.count }
        if b.isEmpty { return a.count }
        var previous = Array(0...b.count)
        var current = [Int](repeating: 0, count: b.count + 1)
        for i in 1...a.count {
            current[0] = i
            for j in 1...b.count {
                let cost = a[i - 1] == b[j - 1] ? 0 : 1
                current[j] = min(previous[j] + 1, current[j - 1] + 1, previous[j - 1] + cost)
            }
            swap(&previous, &current)
        }
        return previous[b.count]
    }

    static func jaroWinkler(_ a: [Character], _ b: [Character]) -> Double {
        if a.isEmpty || b.isEmpty { return 0 }
        if a == b { return 1 }
        let window = max(0, max(a.count, b.count) / 2 - 1)
        var aMatched = [Bool](repeating: false, count: a.count)
        var bMatched = [Bool](repeating: false, count: b.count)
        var matches = 0
        for i in 0..<a.count {
            let lo = max(0, i - window)
            let hi = min(b.count - 1, i + window)
            if lo > hi { continue }
            for j in lo...hi where !bMatched[j] && a[i] == b[j] {
                aMatched[i] = true
                bMatched[j] = true
                matches += 1
                break
            }
        }
        if matches == 0 { return 0 }
        var transpositions = 0
        var k = 0
        for i in 0..<a.count where aMatched[i] {
            while !bMatched[k] { k += 1 }
            if a[i] != b[k] { transpositions += 1 }
            k += 1
        }
        let m = Double(matches)
        let jaro = (m / Double(a.count) + m / Double(b.count) + (m - Double(transpositions) / 2) / m) / 3
        // The shared-prefix bonus only applies to strings that are already clearly similar (standard Jaro-Winkler).
        guard jaro >= 0.7 else { return jaro }
        var prefix = 0
        for i in 0..<min(4, min(a.count, b.count)) {
            if a[i] == b[i] { prefix += 1 } else { break }
        }
        return jaro + Double(prefix) * 0.1 * (1 - jaro)
    }
}
