import SwiftUI
import AppLogic

/// R341 (Decided by the owner, 21 Nov 2026; docs/HIG_AUDIT.md T8): a cast member's titles in the owner's library, opened
/// from the cast shelf of a movie or show page, as the Apple TV app opens a person's page from its cast row. The same
/// poster grid and cards as Movies and Shows (`PosterGridLayout`, `PosterCard`, `SeriesCard`): movies first, then shows,
/// each in title order. Read only from the title details already stored on this Apple TV; nothing is asked online
/// (`OnlineServices.storedDetails`). HIG Layout (grid spacing, docs/DESIGN_SYSTEM.md section 4). How close this is to the
/// TV app's own person page on tvOS 27 is UNVERIFIED.
struct PersonView: View {
    let name: String
    @Environment(AppServices.self) private var services
    @State private var state: ViewState<PersonTitles.Content> = .loading

    var body: some View {
        VStack(alignment: .leading) {
            // Rule S1: one line, scaled to fit, never cut.
            FittingText(name, style: .title2)
                .accessibilityAddTraits(.isHeader)
            ScreenStateView(state: state, onRetry: { Task { await load() } }) { content in
                VStack(alignment: .leading) {
                    FittingText(content.countText, style: .callout)
                        .foregroundStyle(.secondary)
                        // R396 (audit P1, SF6): room for the focused card of the first row, which touched this line.
                        // The same value as under the count line of Movies and Shows (R392).
                        .padding(.bottom, CGFloat(ProductPageSpacing.aboveFirstGridRow))
                    PosterGridLayout {
                        ForEach(content.movies) { card in
                            PosterCard(card: card)
                        }
                        ForEach(content.shows) { show in
                            SeriesCard(series: show)
                        }
                    }
                }
            }
        }
        .pushedScreen(name)
        .task(id: services.libraryRevision) { await load() }
    }

    private func load() async {
        let details = services.online.storedDetails()
        state = await PersonTitles.state(name: name, store: services.store, details: details)
    }
}
