import SwiftUI
import AppLogic

/// One candidate: its picture in the kind's shape, the language in words and the size as text beneath, a check on the choice.
struct ArtworkCandidateTile: View {
    let candidate: ArtworkCandidate
    let kind: ArtworkGalleryKind
    let artworkKey: String
    let isChosen: Bool
    let action: () -> Void
    @Environment(AppServices.self) private var services
    @State private var url: URL?

    var body: some View {
        VStack(alignment: .leading) {
            Button(action: action) {
                picture
                    .aspectRatio(kind.aspectRatio, contentMode: .fit)
                    .overlay(alignment: .topTrailing) {
                        if isChosen {
                            Image(systemName: "checkmark.circle.fill").font(.title2).padding().accessibilityHidden(true)
                        }
                    }
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(label)
            .accessibilityHint("Use This Picture")
            .accessibilityAddTraits(isChosen ? .isSelected : [])
            FittingText(candidate.languageName(), style: .callout)
            if let size = candidate.pixelSizeText { FittingText(size, style: .caption).foregroundStyle(.secondary) }
            FittingText(candidate.source.title, style: .caption).foregroundStyle(.secondary)
        }
        .task(id: candidate.id) { url = await services.online.thumbnail(of: candidate, key: artworkKey, kind: kind) }
    }

    private var label: String {
        [candidate.languageName(), candidate.pixelSizeText, candidate.source.title, isChosen ? "Current choice" : nil].compactMap { $0 }.joined(separator: ", ")
    }

    /// A logo is shown twice in the spec (on a dark sample and on the item's own background); one tile shows it on the dark
    /// sample (`Color.black`), the background preview is the logo screen's own backdrop (PROVISIONAL, R455).
    @ViewBuilder
    private var picture: some View {
        ZStack {
            // design-lint:allow R455: the dark sample a logo's lettering is judged on (white lettering needs a dark ground)
            if kind == .logo { Color.black } else { Rectangle().fill(.quaternary) }
            if let url {
                AsyncImage(url: url) { phase in
                    if case .success(let image) = phase {
                        image.resizable().aspectRatio(contentMode: kind == .logo ? .fit : .fill)
                    }
                }
                .asyncImageURLSession(services.online.imageSession)
            }
        }
        .clipped()
    }
}
