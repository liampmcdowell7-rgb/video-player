import SwiftUI
import AppLogic

/// Which file the Play button opens, when a title has more than one.
struct VersionsMenu: View {
    let versions: [VersionRow]
    let model: ScreenModel<ItemDetailViewModel>

    var body: some View {
        Menu("Versions", systemImage: "square.stack") {
            Picker("Version", selection: selection) {
                ForEach(versions) { version in
                    Text(label(version)).tag(version.id)
                }
            }
        }
    }

    private var selection: Binding<Int64> {
        Binding(
            get: { versions.first(where: \.isPreferred)?.id ?? versions.first?.id ?? 0 },
            set: { id in Task { await model.run { await $0.choosePreferredVersion(id) } } })
    }

    private func label(_ version: VersionRow) -> String {
        version.detail.map { "\(version.title), \($0)" } ?? version.title
    }
}
