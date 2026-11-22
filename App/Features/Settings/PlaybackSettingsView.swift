import SwiftUI
import AppLogic

/// Settings > Playback. #15 3.2: bounded column (`SettingsPane`), footers of one or two lines, the full explanations on
/// "Learn More" pages (SettingsTexts).
struct PlaybackSettingsView: View {
    @AppStorage(SettingsKey.autoPlayNextEpisode.rawValue) private var autoPlayNext = true
    @AppStorage(SettingsKey.showSkipButtons.rawValue) private var skipButtons = true
    // R314: the intro is skipped by itself by default (owner); credits only when asked, since binge starts at them anyway.
    @AppStorage(SettingsKey.skipIntrosAutomatically.rawValue) private var skipIntros = true
    @AppStorage(SettingsKey.skipCreditsAutomatically.rawValue) private var skipCredits = false
    @AppStorage(SettingsKey.showPlaybackStatsButton.rawValue) private var statsButton = true
    @AppStorage(SettingsKey.rememberTrackChoicePerShow.rawValue) private var rememberTracks = true
    @AppStorage(SettingsKey.trueHDCompatibilityCore.rawValue) private var trueHDCore = false
    /// R311: the last playback that failed on this Apple TV (`PlaybackProblemLog`), tokens removed.
    @AppStorage(PlaybackProblem.storageKey) private var problemData: Data?

    var body: some View {
        SettingsPane(title: "Playback", summary: SettingsTexts.playbackSummary) {
            Section {
                SettingToggle("Play Next Episode Automatically", isOn: $autoPlayNext)
                SettingToggle("Show Skip Buttons", isOn: $skipButtons)
                SettingToggle("Skip Intros Automatically", isOn: $skipIntros)
                SettingToggle("Skip Credits Automatically", isOn: $skipCredits)
                LearnMoreLink(title: SettingsTexts.skipLearnMoreTitle, text: SettingsTexts.skipFull)
            } footer: {
                Text(SettingsTexts.skipShort)
            }
            Section {
                SettingToggle("Remember Audio and Subtitle Choice for Each Show", isOn: $rememberTracks)
                SettingToggle("Show Playback Stats in the Player", isOn: $statsButton)
            } footer: {
                Text(SettingsTexts.statsFooter)
            }
            Section {
                SettingToggle("Play the Dolby Digital Core of Dolby TrueHD", isOn: $trueHDCore)
                LearnMoreLink(title: SettingsTexts.trueHDLearnMoreTitle, text: SettingsTexts.trueHDFull)
            } footer: {
                Text(SettingsTexts.trueHDShort)
            }
            // R311: what the owner reads after a failed start, without a Mac: the step, the source, the file and the error.
            // R389 (owner's device test of 22 Nov 2026: Settings could not scroll down to it): this last section held no
            // control, and a tvOS Form scrolls only by moving the focus, so the focus stopped at the row above and these
            // rows stayed below the screen. Each row now takes the focus (`readableRow`), and the full report (R386: every
            // row, the player's message and the recent events) is one press away on its own page, the section's last row.
            Section(PlaybackProblem.sectionTitle) {
                if let problem = PlaybackProblem.decoded(problemData) {
                    ForEach(Array(problem.rows.enumerated()), id: \.offset) { _, row in
                        if Self.wrappedRows.contains(row.label) {
                            ProblemTextRow(label: row.label, text: row.value).readableRow()
                        } else {
                            ValueRow(row.label, value: row.value).readableRow()
                        }
                    }
                    LearnMoreLink(title: PlaybackProblem.fullReportTitle, text: problem.fullText())
                        .accessibilityIdentifier(SettingsRowID.last)
                } else {
                    StatusText(PlaybackProblem.noneText)
                        .readableRow()
                        .accessibilityIdentifier(SettingsRowID.last)
                }
            }
        }
    }

    /// R389: the long values (an error message, an underlying error, an event with its time) wrap under their label instead
    /// of shrinking to fit one line.
    static let wrappedRows: Set<String> = ["Underlying Error", "Last Event", "Error"]
}

/// R389: a label with a long value under it, wrapped, never cut (rule L7). Read-only; the caller makes it focusable.
private struct ProblemTextRow: View {
    let label: String
    let text: String

    var body: some View {
        VStack(alignment: .leading) {
            FittingText(label)
            Text(text)
                .font(.callout)
                .foregroundStyle(ReadableSecondary.style)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(text)
    }
}
