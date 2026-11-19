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
                    VStack(alignment: .leading) {
                        Text(found.name)
                        Text(SourceCatalog.info(for: found.kind).title)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .pushedScreen("Your Network")
        .onAppear { browser.start() }
        .onDisappear { browser.stop() }
    }
}
