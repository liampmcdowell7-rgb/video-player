import Foundation
import VideoPlayerCore

/// FTP / FTPS client. One control connection, one operation at a time (FTP cannot interleave
/// commands), a fresh passive data connection per transfer. A dropped control connection is
/// re-established and the operation retried once.
///
/// Seeking: `REST <offset>` then `RETR`, read `length` bytes, close the data connection (the
/// server answers 426 or 226) and carry on with the same control connection.
public actor FTPClient: MediaSource {
    public nonisolated let kind: SourceKind = .ftp
    public nonisolated let capabilities = SourceCapabilities(
        authMethods: [.none, .usernamePassword],
        byteRanges: true,
        changeSignals: [.modified, .size],
        discovery: false,
        directPlaybackURL: false,
        alwaysEncrypted: false
    )

    private let host: String
    private let port: Int
    private let credentials: FTPCredentials
    private let security: FTPSecurity
    private let connector: FTPConnector

    private var control: FTPControlChannel?
    private var features: Set<String> = []
    private var epsvUnsupported = false
    private var mlsdUnsupported = false

    // FTP cannot interleave commands: operations queue here (actors are re-entrant at awaits).
    private var busy = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    public init(
        host: String,
        port: Int = 21,
        credentials: FTPCredentials = .anonymous,
        security: FTPSecurity = .none,
        connector: FTPConnector = makeDefaultFTPConnector()
    ) {
        self.host = host
        self.port = port
        self.credentials = credentials
        self.security = security
        self.connector = connector
    }

    // MARK: MediaSource

    public func authenticate() async throws {
        try await run(forceReconnect: true) { _ in }
    }

    public func list(_ path: String) async throws -> [SourceEntry] {
        let folder = Self.normalize(path)
        return try await run { ch in try await self.listFolder(ch, folder) }
    }

    public func info(_ path: String) async throws -> SourceEntry {
        let p = Self.normalize(path)
        return try await run { ch in try await self.entryInfo(ch, p) }
    }

    public func read(_ path: String, range: ByteRange) async throws -> Data {
        if range.length == 0 { return Data() }
        let p = Self.normalize(path)
        return try await run { ch in try await self.readRange(ch, p, range) }
    }

    public func playbackAccess(for path: String) async throws -> PlaybackAccess { .byteReader }

    // MARK: Serialising and reconnecting

    private func acquire() async {
        if !busy { busy = true; return }
        await withCheckedContinuation { waiters.append($0) }
    }

    private func release() {
        if waiters.isEmpty { busy = false } else { waiters.removeFirst().resume() }
    }

    private func run<T>(forceReconnect: Bool = false, _ body: (FTPControlChannel) async throws -> T) async throws -> T {
        await acquire()
        defer { release() }
        if forceReconnect { await dropControl() }
        var attempts = 0
        while true {
            do {
                let ch = try await ensureControl()
                return try await body(ch)
            } catch let e as FTPStreamError {
                await dropControl()
                if case .tlsUnavailable(let why) = e { throw SourceError.unsupported(why) }
                attempts += 1
                if attempts >= 2 { throw SourceError.transport("FTP connection failed: \(e)") }
            } catch is CancellationError {
                await dropControl()
                throw CancellationError()
            }
        }
    }

    private func dropControl() async {
        if let c = control { control = nil; await c.close() }
    }

    private func ensureControl() async throws -> FTPControlChannel {
        if let c = control { return c }
        let c = try await connectControl()
        control = c
        return c
    }

    // MARK: Connect and log in

    private func connectControl() async throws -> FTPControlChannel {
        let stream = try await connector.connect(host: host, port: port, tls: security == .implicitTLS, allowUpgrade: security == .explicitTLS)
        let ch = FTPControlChannel(stream: stream)
        do {
            let greeting = try await ch.readReply()
            guard greeting.code == 220 else { throw Self.mapError(greeting) }

            if security == .explicitTLS {
                let auth = try await ch.command("AUTH TLS")
                guard auth.code == 234 else { throw SourceError.unsupported("The server refused AUTH TLS (\(auth.code)). It may not support FTPS.") }
                try await stream.startTLS(serverName: host)
            }

            var reply = try await ch.command("USER \(credentials.username)")
            if reply.code == 331 || reply.code == 332 {
                reply = try await ch.command("PASS \(credentials.password)")
            }
            guard reply.code == 230 || reply.code == 202 else { throw Self.mapError(reply) }

            if security != .none {
                let pbsz = try await ch.command("PBSZ 0")
                guard pbsz.isCompletion else { throw SourceError.unsupported("The server refused PBSZ (\(pbsz.code))") }
                let prot = try await ch.command("PROT P")
                guard prot.isCompletion else { throw SourceError.unsupported("The server refused a protected data channel (\(prot.code))") }
            }

            features = []
            let feat = try await ch.command("FEAT")
            if feat.code == 211, feat.lines.count > 2 {
                for line in feat.lines[1..<(feat.lines.count - 1)] {
                    features.insert(line.trimmingCharacters(in: .whitespaces).uppercased())
                }
            }
            if features.contains("UTF8") { _ = try await ch.command("OPTS UTF8 ON") }

            let type = try await ch.command("TYPE I")
            guard type.isCompletion else { throw Self.mapError(type) }
            return ch
        } catch {
            await ch.close()
            throw error
        }
    }

    private func has(_ feature: String) -> Bool {
        features.contains { $0 == feature || $0.hasPrefix(feature + " ") }
    }

    // MARK: Data connections

    private func openData(_ ch: FTPControlChannel) async throws -> FTPStream {
        var dataPort: Int?
        if !epsvUnsupported {
            let r = try await ch.command("EPSV")
            if r.code == 229, let p = FTPParsers.parseEPSV(r.lines.joined(separator: " ")) {
                dataPort = p
            } else {
                epsvUnsupported = true
            }
        }
        if dataPort == nil {
            let r = try await ch.command("PASV")
            guard r.code == 227, let parsed = FTPParsers.parsePASV(r.text) else { throw Self.mapError(r) }
            // Servers behind NAT often announce their private address: always dial the control host.
            dataPort = parsed.port
        }
        guard let portNumber = dataPort else { throw SourceError.malformedResponse }
        return try await connector.connect(host: host, port: portNumber, tls: security != .none, allowUpgrade: false)
    }

    private func receiveAll(_ data: FTPStream) async throws -> Data {
        var out = Data()
        while true {
            let chunk = try await data.receive(maxLength: 65536)
            if chunk.isEmpty { return out }
            out.append(chunk)
        }
    }

    // MARK: Listing

    private func listFolder(_ ch: FTPControlChannel, _ folder: String) async throws -> [SourceEntry] {
        let useMLSD = has("MLST") && !mlsdUnsupported
        let command = (useMLSD ? "MLSD " : "LIST ") + folder
        let data = try await openData(ch)
        let started = try await ch.command(command)
        guard started.code == 125 || started.code == 150 else {
            await data.close()
            if useMLSD, [500, 501, 502, 504].contains(started.code) {
                mlsdUnsupported = true
                return try await listFolder(ch, folder)
            }
            throw Self.mapError(started)
        }
        let bytes: Data
        do { bytes = try await receiveAll(data) } catch { await data.close(); throw error }
        await data.close()
        let done = try await ch.readReply()
        guard done.isCompletion else { throw Self.mapError(done) }
        let text = String(data: bytes, encoding: .utf8) ?? String(bytes.map { Character(UnicodeScalar($0)) })
        return useMLSD ? FTPParsers.parseMLSD(text, parent: folder) : FTPParsers.parseList(text, parent: folder)
    }

    // MARK: Info

    private func entryInfo(_ ch: FTPControlChannel, _ path: String) async throws -> SourceEntry {
        if path == "/" { return SourceEntry(path: "/", name: "/", isDirectory: true) }
        let leaf = FTPParsers.lastComponent(path)
        let parent = FTPParsers.parent(of: path)

        if has("MLST") {
            let r = try await ch.command("MLST " + path)
            if r.code == 250, r.lines.count >= 3 {
                var line = r.lines[1]
                if line.hasPrefix(" ") { line.removeFirst() }
                if var entry = FTPParsers.parseMLSLine(line, parent: parent) {
                    entry.path = path
                    entry.name = leaf
                    return entry
                }
                throw SourceError.malformedResponse
            }
            if r.code != 500 && r.code != 501 && r.code != 502 { throw Self.mapError(r) }
        }

        let size = try await ch.command("SIZE " + path)
        if size.code == 213, let bytes = Int64(size.text) {
            var modified: Date?
            let mdtm = try await ch.command("MDTM " + path)
            if mdtm.code == 213 { modified = FTPParsers.parseMDTM(mdtm.text) }
            return SourceEntry(path: path, name: leaf, isDirectory: false, size: bytes, modified: modified)
        }
        let cwd = try await ch.command("CWD " + path)
        if cwd.code == 250 { return SourceEntry(path: path, name: leaf, isDirectory: true) }
        throw SourceError.notFound
    }

    // MARK: Ranged reads

    private func readRange(_ ch: FTPControlChannel, _ path: String, _ range: ByteRange) async throws -> Data {
        let want = Int(range.length)
        let data = try await openData(ch)

        if range.offset > 0 {
            let rest: FTPReply
            do { rest = try await ch.command("REST \(range.offset)") } catch { await data.close(); throw error }
            guard rest.code == 350 else {
                await data.close()
                if rest.code == 554 { throw SourceError.rangeNotSatisfiable }
                if [500, 501, 502, 504].contains(rest.code) { throw SourceError.rangesNotSupported }
                throw Self.mapError(rest)
            }
        }

        let started: FTPReply
        do { started = try await ch.command("RETR " + path) } catch { await data.close(); throw error }
        guard started.code == 125 || started.code == 150 else {
            await data.close()
            if range.offset > 0, [551, 554, 501].contains(started.code), try await pastEnd(ch, path, range.offset) {
                throw SourceError.rangeNotSatisfiable
            }
            throw Self.mapError(started)
        }

        var out = Data()
        out.reserveCapacity(min(want, 8 << 20))
        do {
            while out.count < want {
                let chunk = try await data.receive(maxLength: min(256 * 1024, want - out.count))
                if chunk.isEmpty { break }
                out.append(chunk)
            }
        } catch {
            await data.close()
            await dropControl()   // a transfer is half done: the control connection state is unknown
            throw error
        }
        await data.close()

        // The server answers 226 (finished) or 426 (we hung up early). Both are fine for a ranged read.
        let early = out.count >= want
        do {
            let done = try await ch.readReply()
            if !early && !done.isCompletion { throw Self.mapError(done) }
        } catch let e as FTPStreamError {
            if early { await dropControl() } else { throw e }
        }

        if out.isEmpty, range.offset > 0, try await pastEnd(ch, path, range.offset) {
            throw SourceError.rangeNotSatisfiable
        }
        return out
    }

    private func pastEnd(_ ch: FTPControlChannel, _ path: String, _ offset: Int64) async throws -> Bool {
        guard control != nil else { return false }
        let r = try await ch.command("SIZE " + path)
        guard r.code == 213, let size = Int64(r.text) else { return false }
        return offset >= size
    }

    // MARK: Helpers

    static func normalize(_ path: String) -> String {
        var p = path.hasPrefix("/") ? path : "/" + path
        while p.count > 1, p.hasSuffix("/") { p.removeLast() }
        return p
    }

    static func mapError(_ reply: FTPReply) -> Error {
        switch reply.code {
        case 421: return FTPStreamError.closed
        case 530, 532: return SourceError.unauthorized
        case 550:
            let t = reply.text.lowercased()
            if t.contains("permission") || t.contains("denied") { return SourceError.forbidden }
            return SourceError.notFound
        case 551: return SourceError.notFound   // "File not available" (rclone)
        case 553: return SourceError.forbidden
        default: return SourceError.transport("FTP \(reply.code) \(reply.text)")
        }
    }
}
