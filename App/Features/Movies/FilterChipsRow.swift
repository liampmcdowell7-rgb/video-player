import SwiftUI
import AppLogic

/// One button per active filter; pressing it removes that filter.
struct FilterChipsRow: View {
    let model: ScreenModel<ItemGridViewModel>

    var body: some View {
        ScrollView(.horizontal) {
            HStack {
                ForEach(model.screen.chips) { chip in
                    Button {
                        Task { await model.run { await $0.removeChip(chip) } }
                    } label: {
                        Label(chip.title, systemImage: "xmark")
                    }
                }
            }
        }
        .scrollClipDisabled()
    }
}
