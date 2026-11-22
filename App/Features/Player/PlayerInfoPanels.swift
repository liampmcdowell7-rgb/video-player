import SwiftUI
import UIKit
import AppLogic
import PlaybackStatus

/// R340 (owner decision of 21 Nov 2026 in R338, docs/HIG_AUDIT.md T15 to T17): the content tabs the app adds to the system
/// player's info panel (`AVPlayerViewController.customInfoViewControllers`, tvOS 15+). Apple: "The system uses a view
/// controller's title property value as the content tab title" and "set a preferredContentSize value ... so the system sizes
/// them correctly"; "The view with the greatest height determines the height of all of the content views", so both tabs
/// ask for the same height. HIG Playing video: "Below the transport controls, the video player displays content tabs, like
/// Info, Episodes, or Chapters". How the tabs look on tvOS 27 is UNVERIFIED until a run.
enum PlayerInfoPanels {
    /// One height for every tab the app adds (Apple: the tallest decides for all).
    static let height: CGFloat = 420

    static func controller<Content: View>(title: String, services: AppServices, @ViewBuilder content: () -> Content) -> UIViewController {
        let host = UIHostingController(rootView: content().environment(services))
        host.title = title
        host.view.backgroundColor = .clear
        host.preferredContentSize = CGSize(width: 0, height: height)
        return host
    }
}

/// The Episodes tab: the season that is playing, as 16:9 lockups (the show page's episode card, one system `.borderless`
/// button each). Choosing another episode plays it; the one playing says "Now Playing" and does nothing.
struct PlayerEpisodesPanel: View {
    let content: PlayerEpisodes.Content
    var onPlay: (Int64) -> Void

    var body: some View {
        ScrollView(.horizontal) {
            // design-lint:allow HIG Layout, 40 pt horizontal spacing between cards (docs/DESIGN_SYSTEM.md section 4)
            LazyHStack(alignment: .top, spacing: 40) {
                ForEach(content.season.episodes) { episode in
                    let isCurrent: Bool = episode.id == content.currentID
                    Button {
                        if !isCurrent { onPlay(episode.id) }
                    } label: {
                        VStack(alignment: .leading) {
                            ArtworkView(key: episode.artworkKey, symbol: "tv", wide: true)
                                .fixedSize(horizontal: false, vertical: true)
                                // design-lint:allow #36 7 (R259): Apple's tvOS media catalog sample attaches the borderless lockup's highlight by hand to a custom artwork view; the system effect, not our own
                                .hoverEffect(.highlight)
                            VStack(alignment: .leading) {
                                CardCaption(text: content.caption(for: episode))
                                FittingText(isCurrent ? PlayerEpisodes.nowPlaying : (episode.runtimeText ?? ""), style: .caption2)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.horizontal)
                            // R393: the row's equal height is reserved by the text block, under its last line.
                            .equalCaptionBlock()
                        }
                    }
                    .buttonStyle(.borderless)
                    // design-lint:allow HIG Layout, four columns of the grid width for 16:9 episode cards (R189)
                    .containerRelativeFrame(.horizontal, count: 4, spacing: 40)
                    .accessibilityLabel(content.caption(for: episode))
                    .accessibilityValue(isCurrent ? PlayerEpisodes.nowPlaying : (episode.runtimeText ?? ""))
                }
            }
            .equalCaptionRow()
        }
        .scrollClipDisabled()
    }
}

/// The Playback Stats tab: every stat at once, most important first (`StatsOverlay.panelRows`), the honest status lines
/// above them. Three columns, so all of them fit the panel without a fold (the owner: all shown, none collapsed).
struct StatsPanelView: View {
    let model: StatsOverlayModel

    // design-lint:allow HIG Layout, 40 pt between the three stat columns (docs/DESIGN_SYSTEM.md section 4)
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 40, alignment: .top), count: 3)

    var body: some View {
        VStack(alignment: .leading) {
            ForEach(model.statusLines, id: \.self) { line in
                Text(line)
                    .font(.caption2)
            }
            LazyVGrid(columns: columns, alignment: .leading) {
                ForEach(Array(StatsOverlay.panelRows(model.rows).enumerated()), id: \.offset) { _, row in
                    LabeledContent {
                        Text(row.value)
                            .foregroundStyle(row.tone == .warning ? Color.orange : Color.primary)
                    } label: {
                        Text(row.label)
                            .foregroundStyle(.secondary)
                    }
                    .font(.caption2)
                }
            }
        }
        .onAppear { model.setShown(true) }
        .onDisappear { model.setShown(false) }
    }
}
