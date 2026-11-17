import Foundation
import VideoPlayerCore
#if canImport(Network)
import Network
#endif

/// One answer to an SSDP M-SEARCH.
public struct SSDPResponse: Equatable, Sendable {
    public var location: URL
    public var searchTarget: String?
    public var usn: String?
    public var server: String?
}

/// The pure parts of SSDP: building the search and reading the answers. These run on Linux and
/// are unit tested. The socket that sends them (`SSDPDiscovery`) is Apple-only and device-only.
public enum SSDP {
    public static let multicastHost = "239.255.255.250"
    public static let port = 1900
    public static let mediaServerTarget = "urn:schemas-upnp-org:device:MediaServer:1"

    /// The M-SEARCH datagram. `mx` is how many seconds devices may wait before answering (1...5).
    public static func mSearchMessage(searchTarget: String = mediaServerTarget, mx: Int = 3) -> String {
        let wait = min(5, max(1, mx))
        return [
            "M-SEARCH * HTTP/1.1",
            "HOST: \(multicastHost):\(port)",
            "MAN: \"ssdp:discover\"",
            "MX: \(wait)",
            "ST: \(searchTarget)",
            "", ""
        ].joined(separator: "\r\n")
    }

    /// Reads an answer datagram. Returns nil for anything that is not a 200 answer with a usable LOCATION
    /// (for example another device's own M-SEARCH, or NOTIFY announcements).
    public static func parseResponse(_ text: String) -> SSDPResponse? {
        // "\r\n" is a single Character in Swift, so split on isNewline rather than on "\n".
        var lines = text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
        guard let status = lines.first, status.uppercased().hasPrefix("HTTP/1."), status.contains(" 200") else { return nil }
        lines.removeFirst()
        var headers: [String: String] = [:]
        for line in lines {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let name = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            if headers[name] == nil { headers[name] = value }
        }
        guard let location = headers["location"], let url = URL(string: location),
              let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https", url.host != nil
        else { return nil }
        return SSDPResponse(location: url, searchTarget: headers["st"], usn: headers["usn"], server: headers["server"])
    }

    /// The server entry the app shows. The friendly name needs the description, so until that is
    /// fetched the SERVER header (or the host) is the label. `description` replaces it when known.
    public static func discoveredSource(from response: SSDPResponse, description: UPnPDeviceDescription? = nil) -> DiscoveredSource {
        let host = response.location.host ?? ""
        let name = description?.friendlyName ?? response.server.flatMap { $0.isEmpty ? nil : $0 } ?? host
        return DiscoveredSource(kind: .upnp, name: name, host: host, port: response.location.port,
                                address: response.location.absoluteString)
    }
}

#if canImport(Network)
/// Finds UPnP/DLNA media servers with SSDP multicast.
///
/// Device-only: tvOS needs the multicast networking entitlement (`com.apple.developer.networking.multicast`)
/// for this, and this project does NOT request it. Without it, the group below fails to start and the
/// stream simply ends with nothing found, so the app falls back to a typed address (or Bonjour).
/// Not exercised by any automated test; the message building and parsing it uses are.
public struct SSDPDiscovery: SourceDiscovery {
    public var kind: SourceKind { .upnp }
    private let searchTarget: String
    private let listenSeconds: Double

    public init(searchTarget: String = SSDP.mediaServerTarget, listenSeconds: Double = 4) {
        self.searchTarget = searchTarget
        self.listenSeconds = listenSeconds
    }

    public func discover() -> AsyncStream<DiscoveredSource> {
        AsyncStream { continuation in
            let queue = DispatchQueue(label: "ssdp.discovery")
            guard let multicast = try? NWMulticastGroup(for: [.hostPort(host: "239.255.255.250", port: 1900)]) else {
                continuation.finish()
                return
            }
            let group = NWConnectionGroup(with: multicast, using: .udp)
            let message = Data(SSDP.mSearchMessage(searchTarget: searchTarget).utf8)
            var seen = Set<String>()

            group.setReceiveHandler(maximumMessageSize: 65_535, rejectOversizedMessages: false) { _, content, _ in
                guard let content, let text = String(data: content, encoding: .utf8),
                      let response = SSDP.parseResponse(text) else { return }
                let key = response.usn ?? response.location.absoluteString
                if seen.insert(key).inserted {
                    continuation.yield(SSDP.discoveredSource(from: response))
                }
            }
            group.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    group.send(content: message) { _ in }
                case .failed, .cancelled:
                    continuation.finish()
                default:
                    break
                }
            }
            continuation.onTermination = { _ in group.cancel() }
            group.start(queue: queue)
            queue.asyncAfter(deadline: .now() + listenSeconds) {
                group.cancel()
                continuation.finish()
            }
        }
    }
}
#endif
