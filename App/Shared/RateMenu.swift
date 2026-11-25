import SwiftUI
import AppLogic

/// R471 (16), PROVISIONAL: the Rate entry of a details button or a long press: a system menu picker (five choices from
/// 5 Stars down to 1 Star, then No Rating), the current rating checked and named in the entry's title. Words ours.
struct RateMenu: View {
    /// The rating now; nil when there is none (or it is not known yet, on a card).
    let current: Int?
    /// The entry's title when it is not the plain "Rate" (the show page's season: "Rate Season 2").
    var title: String? = nil
    let onChoose: (Int?) -> Void

    var body: some View {
        Picker(selection: Binding(get: { current ?? 0 }, set: { onChoose($0 == 0 ? nil : $0) })) {
            ForEach(RatingText.choices, id: \.self) { stars in
                Text(RatingText.title(stars)).tag(stars)
            }
            Text(RatingText.clear).tag(0)
        } label: {
            Label(title ?? RatingText.menuTitle(current: current), systemImage: ProductAction.rate.symbol)
        }
        .pickerStyle(.menu)
        .accessibilityIdentifier("product.rate")
    }
}
