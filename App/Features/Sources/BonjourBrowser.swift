import Foundation
import Network
import Observation
import VideoPlayerCore
import AppLogic

/// Finds servers on the local network by their advertised service names, then resolves each one to a real address.
///
/// Resolution: the system browser (`NWBrowser`) only gives a service name. A short-lived `NWConnection` to that service
/// endpoint makes the system resolve it; once it is ready, `currentPath?.remoteEndpoint` is the address it really used
/// (IPv4 only, so the text can be typed into a form). If that fails or times out, the name plus ".local" is used as before
/// (`BonjourMapping.fallbackHost`) and the form lets the user change it. The mapping itself is tested in the package
/// (`BonjourMapping`); only the Network calls live here. docs/SOURCES_WIRING.md records the alternative (NetService).
@MainActor
@Observable
final class BonjourBrowser {
    private(set) var found: [DiscoveredSource] = []
    private(set) var isSearching = false
    private var browsers: [NWBrowser] = []
    private var results: [String: [DiscoveredSource]] = [:]
    private var resolving: [String: NWConnection] = [:]
    private var resolved: [String: BonjourService] = [:]

    func start() {
        guard browsers.isEmpty else { return }
        #if DEBUG
        // #30 item 2: the screenshot job's one synthetic server, with no browsing and no network. Not compiled into Release.
        if UITestLaunch.usesFakeServer(arguments: ProcessInfo.processInfo.arguments, mode: UITestMode.current) {
            found = [UITestFixtures.discoveredServer]
            return
        }
        #endif
        isSearching = true
        for entry in BonjourMapping.serviceTypes {
            let type = entry.type
            let browser = NWBrowser(for: .bonjour(type: type, domain: nil), using: .tcp)
            browser.browseResultsChangedHandler = { [weak self] results, _ in
                let endpoints: [(name: String, endpoint: NWEndpoint)] = results.compactMap { result in
                    if case .service(let name, _, _, _) = result.endpoint { return (name, result.endpoint) }
                    return nil
                }
                Task { @MainActor in self?.update(type: type, endpoints: endpoints) }
            }
            browser.start(queue: .main)
            browsers.append(browser)
        }
    }

    func stop() {
        for browser in browsers { browser.cancel() }
        for connection in resolving.values { connection.cancel() }
        browsers = []
        resolving = [:]
        isSearching = false
    }

    private func key(_ type: String, _ name: String) -> String { type + "|" + name }

    private func update(type: String, endpoints: [(name: String, endpoint: NWEndpoint)]) {
        let current = Set(endpoints.map { key(type, $0.name) })
        for (k, connection) in resolving where k.hasPrefix(type + "|") && !current.contains(k) { connection.cancel(); resolving[k] = nil }
        results[type] = endpoints.compactMap { item in
            BonjourMapping.discovered(resolved[key(type, item.name)] ?? BonjourService(type: type, name: item.name))
        }
        publish()
        for item in endpoints where resolved[key(type, item.name)] == nil && resolving[key(type, item.name)] == nil {
            resolve(type: type, name: item.name, endpoint: item.endpoint)
        }
    }

    private func publish() {
        found = results.values.flatMap { $0 }.sorted { ($0.name, $0.kind.rawValue) < ($1.name, $1.kind.rawValue) }
    }

    private func resolve(type: String, name: String, endpoint: NWEndpoint) {
        let parameters = NWParameters.tcp
        if let ip = parameters.defaultProtocolStack.internetProtocol as? NWProtocolIP.Options { ip.version = .v4 }
        let connection = NWConnection(to: endpoint, using: parameters)
        let k = key(type, name)
        resolving[k] = connection
        connection.stateUpdateHandler = { [weak self, weak connection] state in
            guard let connection else { return }
            switch state {
            case .ready:
                var host: String?
                var port: Int?
                if case .hostPort(let h, let p)? = connection.currentPath?.remoteEndpoint {
                    host = Self.text(of: h)
                    port = Int(p.rawValue)
                }
                connection.cancel()
                Task { @MainActor in self?.finish(type: type, name: name, host: host, port: port) }
            case .failed, .cancelled:
                Task { @MainActor in self?.finish(type: type, name: name, host: nil, port: nil) }
            default: break
            }
        }
        connection.start(queue: .main)
        // A server that never answers must not leave the row waiting: after a few seconds the .local name stays.
        DispatchQueue.main.asyncAfter(deadline: .now() + 6) { [weak connection] in connection?.cancel() }
    }

    private func finish(type: String, name: String, host: String?, port: Int?) {
        let k = key(type, name)
        resolving[k] = nil
        guard resolved[k] == nil else { return }
        let service = BonjourService(type: type, name: name, resolvedHost: host, resolvedPort: port)
        resolved[k] = service
        guard results[type]?.contains(where: { $0.name == name }) == true, let mapped = BonjourMapping.discovered(service) else { return }
        results[type] = (results[type] ?? []).map { $0.name == name ? mapped : $0 }
        publish()
    }

    /// The address as text, without an interface suffix ("192.168.1.20", never "fe80::1%en0").
    /// Changed 2026-11-17 (Network check): the text form of `NWEndpoint.Host` is only its debug description, whose format the
    /// reference page does not document, so an IPv4 address is now built from `IPv4Address.rawValue` (4 bytes) and a name is
    /// taken from the `.name` case. The debug text is kept only as the last fallback (an IPv6 address, which the IPv4-only
    /// parameters above should not produce).
    private nonisolated static func text(of host: NWEndpoint.Host) -> String {
        switch host {
        case .ipv4(let address) where address.rawValue.count == 4:
            return address.rawValue.map { String($0) }.joined(separator: ".")
        case .name(let name, _):
            return name
        default:
            let raw = "\(host)"
            return raw.split(separator: "%").first.map(String.init) ?? raw
        }
    }
}
