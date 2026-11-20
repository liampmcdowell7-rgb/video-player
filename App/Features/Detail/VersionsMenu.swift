import SwiftUI
import AppLogic

/// Which file the Play button opens, when a title has more than one.
struct VersionsMenu: View {
    let versions: [VersionRow]
    let model: ScreenModel<ItemDetailViewModel>

    var body: some View {
        Menu {
            Picker("Version", selection: selection) {
                ForEach(versions) { version in
                    Text(version.label).tag(version.id)
                }
            }
        } label: {
            // #25 B5: the system label, the same height as the other detail buttons (ActionRow). Symbol: docs/SYMBOLS.md.
            ActionLabel("Versions", systemImage: "square.stack")
        }
        .accessibilityLabel("Versions")
        .accessibilityIdentifier(ControlID.versions)
    }

    private var selection: Binding<Int64> {
        Binding(
            get: { versions.first(where: \.isPreferred)?.id ?? versions.first?.id ?? 0 },
            set: { id in Task { await model.run { await $0.choosePreferredVersion(id) } } })
    }
}
