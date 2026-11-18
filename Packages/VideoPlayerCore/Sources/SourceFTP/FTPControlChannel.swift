import Foundation
import VideoPlayerCore

struct FTPReply: Equatable {
    var code: Int
    /// Every line as received, without the line ending. Multiline replies have several.
    var lines: [String]

    /// The text of the first line after the code.
    var text: String {
        guard let first = lines.first else { return "" }
        return String(first.dropFirst(4)).trimmingCharacters(in: .whitespaces)
    }
    var isPositivePreliminary: Bool { code >= 100 && code < 200 }
    var isCompletion: Bool { code >= 200 && code < 300 }
    var isIntermediate: Bool { code >= 300 && code < 400 }
}

/// Line-oriented reader and writer for the FTP control connection.
final class FTPControlChannel {
    let stream: FTPStream
    private var buffer = Data()

    init(stream: FTPStream) { self.stream = stream }

    private func readLine() async throws -> String {
        while true {
            if let nl = buffer.firstIndex(of: 0x0A) {
                var lineData = buffer[buffer.startIndex..<nl]
                buffer.removeSubrange(buffer.startIndex...nl)
                if lineData.last == 0x0D { lineData = lineData.dropLast() }
                if let s = String(data: lineData, encoding: .utf8) { return s }
                return String(lineData.map { Character(UnicodeScalar($0)) })   // Latin-1 fallback
            }
            if buffer.count > 64 * 1024 { throw SourceError.malformedResponse }
            let chunk = try await stream.receive(maxLength: 4096)
            if chunk.isEmpty { throw FTPStreamError.closed }
            buffer.append(chunk)
        }
    }

    /// Reads one reply. A 421 means the server is closing the control connection.
    func readReply() async throws -> FTPReply {
        let first = try await readLine()
        let chars = Array(first)
        guard chars.count >= 3, let code = Int(String(chars[0..<3])), code >= 100, code < 600 else {
            throw SourceError.malformedResponse
        }
        var lines = [first]
        if chars.count > 3, chars[3] == "-" {
            let terminator = String(chars[0..<3]) + " "
            while true {
                let line = try await readLine()
                lines.append(line)
                if line.hasPrefix(terminator) || line == String(chars[0..<3]) { break }
                if lines.count > 2000 { throw SourceError.malformedResponse }
            }
        }
        if code == 421 { throw FTPStreamError.closed }
        return FTPReply(code: code, lines: lines)
    }

    func send(_ line: String) async throws {
        // Checked on the BYTES. "\r\n" is one Character in Swift, so the Character-based `contains("\r")` (the one chosen on
        // Apple platforms) is false for "/a\r\nDELE x" and the injected command would reach the server. Linux picked
        // Foundation's substring search, so only the tvOS run of testPathWithLineBreakIsRejected showed it (run 44401030622).
        guard !line.utf8.contains(13), !line.utf8.contains(10) else { throw SourceError.invalidURL }
        try await stream.send(Data((line + "\r\n").utf8))
    }

    func command(_ line: String) async throws -> FTPReply {
        try await send(line)
        return try await readReply()
    }

    func close() async { await stream.close() }
}
