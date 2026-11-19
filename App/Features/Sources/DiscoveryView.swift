import SwiftUI
import VideoPlayerCore
import AppLogic

/// Servers the system finds by itself. Choosing one opens the form with its name and address filled in.
struct DiscoveryView: View {
    @State private var browser = BonjourBrowser()

    var body: some View {
        List {
            if browser.found.isEmpty {
                Section {
                    HStack {
                        ProgressView()
                        Text("Looking for WebDAV, SMB, NFS, SFTP and FTP servers on your network with Bonjour. If yours does not appear, go back and type its address. UPnP/DLNA servers are not found automatically on Apple TV: choose UPnP/DLNA and type the address of its device description.")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            ForEach(browser.found, id: \.self) { found in
                NavigationLink(value: SetupRoute.discovered(found)) {
                    // #15 2.3 (R188): the readable name on one line (S1), the type, and a machine identifier only as a
                    // secondary line. Fixed in code, verify in next screenshots (21).
                    let kindTitle = SourceCatalog.info(for: found.kind).title
                    let name = SourceSetupText.discoveredName(found.name, kindTitle: kindTitle)
                    VStack(alignment: .leading) {
                        FittingText(name.title)
                        FittingText(kindTitle, style: .caption)
                            .foregroundStyle(.secondary)
                        if let identifier = name.identifier {
                            Text(identifier)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
        .pushedScreen("Your Network")
        .onAppear { browser.start() }
        .onDisappear { browser.stop() }
    }
}
