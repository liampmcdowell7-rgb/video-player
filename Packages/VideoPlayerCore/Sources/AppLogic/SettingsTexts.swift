import Foundation

/// The texts of the Settings pages (#15 Part 3). Rule L5: a section footer has one or two lines; anything longer moves,
/// unchanged, to a "Learn More" page. Each page has one summary sentence for the left column of `SettingsPane` (L1).
/// The full texts are the footers the pages had before #15, word for word (SettingsTextsTests checks both).
public enum SettingsTexts {
    /// The longest short footer, in characters: about two lines at the footer style in the right half of the screen. A rule
    /// of thumb for the tests, not a measurement (PROVISIONAL, OPEN_QUESTIONS R178); the screenshots are the proof.
    public static let shortFooterLimit = 130

    // MARK: Root

    public static let rootSummary = "Settings for this app. Text size, Bold Text, audio output and captions are set in the Apple TV’s own Settings."

    // MARK: Playback

    public static let playbackSummary = "How titles play and what the player shows."
    public static let skipShort = "Skip buttons appear only for titles with intro, recap or credits markers."
    public static let skipLearnMoreTitle = "About Skip Markers"
    public static let skipFull = "Skip buttons and the next-episode card appear only for titles that have intro, recap or credits markers. Markers come from chapters named Intro, Recap or Credits in MKV files, from .edl or .segments.json files next to the video, and from positions you mark yourself in the player. Markers from online lookups or from analysing the video are not available yet."
    public static let statsFooter = "Playback Stats adds one item to the player’s menu. It is off on screen until you open it."
    public static let trueHDShort = "Off plays Dolby TrueHD losslessly. On plays its lossy Dolby Digital 5.1 core instead."
    public static let trueHDLearnMoreTitle = "About Dolby TrueHD"
    public static let trueHDFull = "Off: Dolby TrueHD is decoded in full, losslessly, in its own channel layout up to 7.1 (Atmos plays as its 7.1 bed). On: tracks that carry a Dolby Digital core play that 5.1 core instead, which is lossy. Applies to the next title you play."

    // MARK: Home Screen

    public static let homeSummary = "Which rows Home shows, and how long titles stay in Continue Watching."
    public static let continueFooter = "The same titles appear in the Top Shelf row on the Apple TV Home Screen once artwork is available for them."
    public static let discoverFooter = "Discover appears in the Search tab while the search field is empty. When it is off, nothing is looked up for it."

    // MARK: Sources, Library, Storage, Accessibility, About

    public static let sourcesSummary = "The servers and shared folders your videos come from."
    public static let noSources = "No sources yet."
    public static let librarySummary = "Scanning your sources, files that need a decision, and what the library holds."
    public static let storageSummary = "Where your settings, passwords and library are kept."
    public static let accessibilitySummary = "This app follows the Apple TV’s own accessibility settings and has no separate copies."
    public static let accessibilityLearnMoreTitle = "About Accessibility Settings"
    public static let accessibilityFull = "Text size, Bold Text, Reduce Motion, Reduce Transparency, Increase Contrast, VoiceOver and captions are set in the device’s own Accessibility settings. This app follows them and has no separate copies."
    public static let aboutSummary = "Version, licences and where the details and pictures come from."

    // MARK: Online Lookup

    public static let onlineSummary = "Your own keys for pictures, Fix Match, Discover and where to watch."
    public static let whatIsSentShort = "Nothing is sent until you enter a key. With a TMDB key, titles and years read from your files go to TMDB."
    public static let whatIsSentTitle = "What Is Sent"
    public static let aboutKeysTitle = "About Keys"
    /// The keys page: the three notes that were rows under the key fields, unchanged.
    public static var aboutKeysFull: String {
        [OnlineLookupText.keysAreOptional, OnlineLookupText.storage, OnlineLookupText.removeNote].joined(separator: "\n\n")
    }

    /// The short footers, for the length test.
    public static let shortFooters = [skipShort, statsFooter, trueHDShort, continueFooter, discoverFooter, whatIsSentShort]
}
