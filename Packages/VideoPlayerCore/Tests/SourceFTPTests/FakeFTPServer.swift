import Foundation
@testable import SourceFTP

/// A scripted in-memory FTP server for deterministic dialogue tests. Everything is synchronous:
/// a command sent on the control stream immediately queues its reply bytes.
final class FakeFTPServer: FTPConnector, @unchecked Sendable {
    struct File { var content: Data; var modify = "20240102030405" }

    // Configuration
    var files: [String: File] = [:]           // absolute path -> file
    var directories: Set<String> = ["/"]
    var features: [String] = ["MLST type*;size*;modify*;", "REST STREAM", "EPSV", "SIZE", "MDTM", "UTF8"]
    var password = "secret"
    var supportsEPSV = true
    var supportsREST = true
    var supportsMLSD = true
    var requireTLS = false                    // AUTH TLS accepted; refuses login before it
    var refuseAuthTLS = false
    var listFormat: ListFormat = .mlsd
    enum ListFormat { case mlsd, unix, dos }

    // Recording
    private let lock = NSLock()
    private(set) var log: [String] = []       // every command line the client sent
    private(set) var connections: [(host: String, port: Int, tls: Bool, allowUpgrade: Bool)] = []
    private(set) var controlConnections = 0
    private(set) var tlsUpgrades = 0
    private(set) var abortedTransfers = 0
    var dropNextCommand = false               // the next command makes the control connection die

    private var nextDataPort = 40000
    private var pendingData: [Int: DataChannel] = [:]

    func record(_ line: String) { lock.lock(); log.append(line); lock.unlock() }
    var commands: [String] { lock.lock(); defer { lock.unlock() }; return log }

    func connect(host: String, port: Int, tls: Bool, allowUpgrade: Bool) async throws -> FTPStream {
        openStream(host: host, port: port, tls: tls, allowUpgrade: allowUpgrade)
    }

    private func openStream(host: String, port: Int, tls: Bool, allowUpgrade: Bool) -> FTPStream {
        lock.lock(); defer { lock.unlock() }
        connections.append((host, port, tls, allowUpgrade))
        if let channel = pendingData[port] {
            pendingData[port] = nil
            channel.tls = tls
            return channel
        }
        controlConnections += 1
        return ControlStream(server: self, tls: tls, allowUpgrade: allowUpgrade)
    }

    func allocateDataChannel() -> (Int, DataChannel) {
        lock.lock(); defer { lock.unlock() }
        nextDataPort += 1
        let channel = DataChannel(server: self)
        pendingData[nextDataPort] = channel
        return (nextDataPort, channel)
    }

    func noteUpgrade() { lock.lock(); tlsUpgrades += 1; lock.unlock() }
    func noteAbort() { lock.lock(); abortedTransfers += 1; lock.unlock() }

    // MARK: Data channel (server -> client payload)

    final class DataChannel: FTPStream, @unchecked Sendable {
        let server: FakeFTPServer
        var tls = false
        var payload = Data()
        var position = 0
        var armed = false
        var onClose: ((Bool) -> Void)?       // true when the client read everything
        init(server: FakeFTPServer) { self.server = server }
        func send(_ data: Data) async throws {}
        func receive(maxLength: Int) async throws -> Data {
            guard armed, position < payload.count else { return Data() }
            let end = min(payload.count, position + min(maxLength, 4096))
            let chunk = payload.subdata(in: position..<end)
            position = end
            return chunk
        }
        func startTLS(serverName: String) async throws {}
        func close() async {
            if armed { let h = onClose; onClose = nil; armed = false; h?(position >= payload.count) }
        }
    }

    // MARK: Control stream

    final class ControlStream: FTPStream, @unchecked Sendable {
        let server: FakeFTPServer
        var tls: Bool
        var allowUpgrade: Bool
        var outbound = Data()
        var inbound = Data()
        var closed = false
        var loggedIn = false
        var user = ""
        var restOffset = 0
        var protP = false
        var pendingChannel: DataChannel?
        var upgraded = false

        init(server: FakeFTPServer, tls: Bool, allowUpgrade: Bool) {
            self.server = server
            self.tls = tls
            self.allowUpgrade = allowUpgrade
            reply("220 fake ftp ready")
        }

        func reply(_ text: String) { outbound.append(Data((text + "\r\n").utf8)) }

        func send(_ data: Data) async throws {
            if closed { throw FTPStreamError.closed }
            inbound.append(data)
            while let nl = inbound.firstIndex(of: 0x0A) {
                let lineData = inbound[inbound.startIndex..<nl]
                inbound.removeSubrange(inbound.startIndex...nl)
                var line = String(decoding: lineData, as: UTF8.self)
                if line.hasSuffix("\r") { line.removeLast() }
                server.record(line.hasPrefix("PASS ") ? "PASS ****" : line)
                if server.dropNextCommand { server.dropNextCommand = false; closed = true; outbound.removeAll(); return }
                handle(line)
            }
        }

        func receive(maxLength: Int) async throws -> Data {
            if outbound.isEmpty { return Data() }   // server went away
            let n = min(maxLength, outbound.count)
            let chunk = outbound.prefix(n)
            outbound.removeFirst(n)
            return Data(chunk)
        }

        func startTLS(serverName: String) async throws {
            guard allowUpgrade else { throw FTPStreamError.tlsUnavailable("not opened for upgrade") }
            upgraded = true
            server.noteUpgrade()
        }

        func close() async { closed = true }

        private var secure: Bool { tls || upgraded }

        func handle(_ line: String) {
            let parts = line.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: false).map(String.init)
            let cmd = parts[0].uppercased()
            let arg = parts.count > 1 ? parts[1] : ""
            switch cmd {
            case "AUTH":
                if server.refuseAuthTLS { reply("504 AUTH not supported") } else { reply("234 Proceed with negotiation") }
            case "USER":
                if server.requireTLS && !secure { reply("530 Must use TLS first"); return }
                user = arg; reply("331 Password required")
            case "PASS":
                if arg == server.password { loggedIn = true; reply("230 Logged in") } else { reply("530 Login incorrect") }
            case "PBSZ": reply("200 PBSZ=0")
            case "PROT": protP = arg.uppercased() == "P"; reply("200 Protection level set")
            case "FEAT":
                reply("211-Features:")
                for f in server.features where !(f.hasPrefix("MLST") && !server.supportsMLSD) { reply(" " + f) }
                reply("211 End")
            case "OPTS": reply("200 OK")
            case "TYPE": reply("200 Type set")
            case "NOOP": reply("200 OK")
            case "QUIT": reply("221 Bye")
            case "EPSV":
                guard server.supportsEPSV else { reply("500 EPSV unknown"); return }
                let (port, channel) = server.allocateDataChannel()
                pendingChannel = channel
                reply("229 Entering Extended Passive Mode (|||\(port)|)")
            case "PASV":
                let (port, channel) = server.allocateDataChannel()
                pendingChannel = channel
                reply("227 Entering Passive Mode (10,0,0,5,\(port / 256),\(port % 256))")
            case "REST":
                guard server.supportsREST else { reply("502 REST not implemented"); return }
                restOffset = Int(arg) ?? 0; reply("350 Restarting at \(restOffset)")
            case "SIZE":
                if let f = server.files[arg] { reply("213 \(f.content.count)") } else { reply("550 Could not get file size") }
            case "MDTM":
                if let f = server.files[arg] { reply("213 \(f.modify)") } else { reply("550 No such file") }
            case "CWD":
                if server.directories.contains(arg) { reply("250 Directory changed") } else { reply("550 No such directory") }
            case "MLST":
                if let f = server.files[arg] {
                    reply("250-Listing \(arg)"); reply(" type=file;size=\(f.content.count);modify=\(f.modify); \(arg)"); reply("250 End")
                } else if server.directories.contains(arg) {
                    reply("250-Listing \(arg)"); reply(" type=dir;modify=20240101000000; \(arg)"); reply("250 End")
                } else { reply("550 Not found") }
            case "MLSD", "LIST":
                guard let channel = pendingChannel else { reply("425 Use PASV first"); return }
                if cmd == "MLSD" && !server.supportsMLSD { reply("500 MLSD unknown"); return }
                guard server.directories.contains(arg) else { reply("550 No such directory"); return }
                pendingChannel = nil
                channel.payload = Data(server.listing(of: arg, mlsd: cmd == "MLSD").utf8)
                channel.armed = true
                reply("150 Opening data connection")
                channel.onClose = { [unowned self] _ in reply("226 Transfer complete") }
            case "RETR":
                guard let channel = pendingChannel else { reply("425 Use PASV first"); return }
                pendingChannel = nil
                guard let f = server.files[arg] else { reply("550 No such file"); return }
                if restOffset > f.content.count { restOffset = 0; reply("554 Invalid REST"); return }
                channel.payload = f.content.subdata(in: restOffset..<f.content.count)
                restOffset = 0
                channel.armed = true
                reply("150 Opening data connection")
                channel.onClose = { [unowned self] complete in
                    if complete { reply("226 Transfer complete") } else { server.noteAbort(); reply("426 Connection closed; transfer aborted") }
                }
            default:
                reply("502 Command not implemented")
            }
        }
    }

    // MARK: Listings

    func listing(of dir: String, mlsd: Bool) -> String {
        var lines: [String] = []
        let prefix = dir == "/" ? "/" : dir + "/"
        func leaf(_ p: String) -> String? {
            guard p.hasPrefix(prefix), p != dir else { return nil }
            let rest = String(p.dropFirst(prefix.count))
            return rest.contains("/") ? nil : rest
        }
        for d in directories.sorted() {
            guard let name = leaf(d) else { continue }
            switch (mlsd, listFormat) {
            case (true, _): lines.append("type=dir;modify=20240101000000; \(name)")
            case (false, .dos): lines.append("03-02-24  10:00AM       <DIR>          \(name)")
            default: lines.append("drwxr-xr-x 2 ftp ftp 4096 Mar  2  2024 \(name)")
            }
        }
        for (p, f) in files.sorted(by: { $0.key < $1.key }) {
            guard let name = leaf(p) else { continue }
            switch (mlsd, listFormat) {
            case (true, _): lines.append("type=file;size=\(f.content.count);modify=\(f.modify); \(name)")
            case (false, .dos): lines.append("03-02-24  10:00AM \(f.content.count) \(name)")
            default: lines.append("-rw-r--r-- 1 ftp ftp \(f.content.count) Mar  2  2024 \(name)")
            }
        }
        return lines.joined(separator: "\r\n") + (lines.isEmpty ? "" : "\r\n")
    }
}

/// Test pattern shared with the live server's data: the byte at offset k is (k*7+3) % 251.
func patternBytes(offset: Int, count: Int) -> Data {
    Data((0..<count).map { UInt8(((offset + $0) * 7 + 3) % 251) })
}

/// A stream that hands out fixed chunks (to test reply parsing across arbitrary packet splits).
final class ChunkedStream: FTPStream, @unchecked Sendable {
    private var chunks: [Data]
    init(_ chunks: [Data]) { self.chunks = chunks }
    func send(_ data: Data) async throws {}
    func receive(maxLength: Int) async throws -> Data { chunks.isEmpty ? Data() : chunks.removeFirst() }
    func startTLS(serverName: String) async throws {}
    func close() async {}
}
