import SwiftUI
import AppLogic

/// Settings > Metadata and Artwork (R456, PROVISIONAL): where descriptions and pictures come from. Online Lookup (the key, the
/// region, Free Data Sources) is the existing page, one row down. Metadata Fetching is that page's state: on while a key is
/// set (R209: nothing is sent before then).
struct MetadataArtworkSettingsView: View {
    @Environment(AppServices.self) private var services
    @AppStorage(AppPreference.preferLocalArtwork.rawValue) private var preferLocalArtwork = true
    @AppStorage(SettingsKey.showTitleLogos.rawValue) private var showTitleLogos = true
    @State private var size: Int64 = 0
    @State private var confirmClear = false

    var body: some View {
        SettingsPane(title: "Metadata and Artwork", summary: "Where descriptions and pictures come from.") {
            Section {
                NavigationLink { OnlineLookupSettingsView() } label: {
                    ValueRow("Metadata Fetching", value: services.online.hasCatalogueKey ? "On" : "Off")
                }
                SettingToggle("Prefer Local Artwork", isOn: $preferLocalArtwork)
                SettingToggle("Show Title Logos", isOn: $showTitleLogos)
            } footer: {
                Text(preferLocalArtwork ? "Pictures next to your files come first, then your server's, then online. Your own choices always win."
                                        : "Online pictures come first, then the ones next to your files. Your own choices always win.")
            }
            Section {
                Button(role: .destructive) { confirmClear = true } label: {
                    ValueRow("Clear All Metadata", value: OnlineDataCache.sizeText(size))
                }
                .accessibilityIdentifier("settings.clearMetadata")
            }
        }
        .task { size = OnlineDataCache.bytes() }
        .confirmationDialog("Clear All Metadata?", isPresented: $confirmClear, titleVisibility: .visible) {
            Button("Clear All Metadata", role: .destructive) {
                OnlineDataCache.clear()
                size = OnlineDataCache.bytes()
                services.online.artworkChanged()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Removes the online descriptions, cast and pictures stored on this Apple TV (\(OnlineDataCache.sizeText(size))). They are fetched again when needed. Your edits, your chosen pictures and your files are kept.")
        }
    }
}
