# Platform API usage (App/ and TopShelf/)

Every Apple API the app code calls that is not plain Swift, with the page it was checked against and the exact signature that page shows.
Checked 2026-11-17 by fetching each page (Apple documentation, read through a documentation fetch tool). "Checked" means: the page exists, the
platform list on the page includes tvOS at a version at or below 27, and the signature below is copied from it. **Nothing here has been compiled**:
a signature match does not prove the call site is right. The first compile check is the real test (docs/BUILD_ORDER.md).

Rows marked **NOT CHECKED** are listed so nothing is hidden; they are the first thing to look at if the compile check fails.

## SwiftUI and AVKit calls checked from the page

| API | Used in | Signature (from the page) | Page |
|---|---|---|---|
| `Tab(_:systemImage:value:role:content:)` | Shell/RootView | `init(_ titleKey: LocalizedStringKey, systemImage: String, value: Value, role: TabRole?, @ContentBuilder content: () -> Content) where Label == DefaultTabLabel`; tvOS 18.0+. The `role:` parameter has no default in this overload; the overload without `role:` is `init(_:systemImage:value:content:)`, also listed on the page | https://developer.apple.com/documentation/swiftui/tab/init(_:systemimage:value:role:content:) |
| `containerRelativeFrame(_:count:span:spacing:alignment:)` | Shared/CardRow (one use, with a `design-lint:allow`) | `nonisolated func containerRelativeFrame(_ axes: Axis.Set, count: Int, span: Int = 1, spacing: CGFloat, alignment: Alignment = .center) -> some View`; tvOS 17.0+. The app calls `.containerRelativeFrame(.horizontal, count: 6, spacing: 40)`, which matches (span defaults to 1). The two-argument form `containerRelativeFrame(_:alignment:)` (tvOS 17.0+) is not used | https://developer.apple.com/documentation/swiftui/view/containerrelativeframe(_:count:span:spacing:alignment:) |
| `ContentUnavailableView` | Support/EmptyStateView, ErrorStateView, Discover/DiscoverView, Player/PlayerScreen (all use the closure form `ContentUnavailableView { Label } description: { } actions: { }`) | `init(label:description:actions:)`; tvOS 17.0+ (the `init(_:systemImage:description:)` form on the same page is not used) | https://developer.apple.com/documentation/swiftui/contentunavailableview |
| `scrollClipDisabled(_:)` | Shared/CardRow, PosterGridLayout, Movies/FilterChipsRow | `nonisolated func scrollClipDisabled(_ disabled: Bool = true) -> some View`; tvOS 17.0+ | https://developer.apple.com/documentation/swiftui/view/scrollclipdisabled(_:) |
| `NavigationLink(_:value:)` | Detail/ItemDetailContentView (`NavigationLink(series, value: Route.series(id))`) | The localized-resource form is `init<P>(_ titleResource: LocalizedStringResource, value: P?) where P : Decodable, P : Encodable, P : Hashable`; tvOS 16.0+. **`Route` is only `Hashable`, not Codable**, so this call must resolve to the `StringProtocol` overload (a `String` title), which the page lists only as a neighbour and which was NOT fetched. Finding F-1 below | https://developer.apple.com/documentation/swiftui/navigationlink/init(_:value:) |
| `alert(_:isPresented:presenting:actions:message:)` | Sources/SourceFormView (two alerts) | `nonisolated func alert<A, M, T>(_ titleResource: LocalizedStringResource, isPresented: Binding<Bool>, presenting data: T?, @ContentBuilder actions: (T) -> A, @ContentBuilder message: (T) -> M) -> some View`; tvOS 16.0+. On tvOS only `Text` labels are supported in alert actions; the message is unstyled text. The app passes a `String` title (`failure?.title ?? ""`), so it uses the `StringProtocol` neighbour overload (same finding F-1, not fetched) | https://developer.apple.com/documentation/swiftui/view/alert(_:ispresented:presenting:actions:message:) |
| `Menu(_:systemImage:content:)` | Movies/SortMenu, FilterMenu, SavedViewsMenu, Detail/VersionsMenu, ExtrasMenu | `init(_ titleKey: LocalizedStringKey, systemImage: String, @ContentBuilder content: () -> Content)`; tvOS 17.0+ | https://developer.apple.com/documentation/swiftui/menu/init(_:systemimage:content:) |
| `Button(_:systemImage:action:)` | Shared/CardContextMenu, Detail, Settings | `init(_ titleKey: LocalizedStringKey, systemImage: String, action: @escaping @MainActor () -> Void)`; tvOS 14.0+ | https://developer.apple.com/documentation/swiftui/button/init(_:systemimage:action:) |
| `LabeledContent` | Files/FileDetailsSheet, Settings/AboutView, AccessibilitySettingsView, LibrarySettingsView, SourceDetailView (`init(_:value:)` and `init(_:content:)` as `LabeledContent("Modified") { Text(...) }`) | `init(_:value:)` (`Label` and `Content` both `Text`) and `init(_:content:)`; tvOS 16.0+ | https://developer.apple.com/documentation/swiftui/labeledcontent |
| `textInputAutocapitalization(_:)` | NOT USED by the app (checked by search). Page fetched anyway: `nonisolated func textInputAutocapitalization(_ autocapitalization: TextInputAutocapitalization?) -> some View`, tvOS 15.0+. The source field row uses `autocorrectionDisabled()` only (NOT fetched) | https://developer.apple.com/documentation/swiftui/view/textinputautocapitalization(_:) |
| `UIHostingController.sizingOptions` | Player/PlayerCoordinator | `@MainActor @preconcurrency var sizingOptions: UIHostingControllerSizingOptions { get set }`; tvOS 16.0+; default is the empty set. The value `.intrinsicContentSize` used in the code is NOT on this page (member list not fetched) | https://developer.apple.com/documentation/swiftui/uihostingcontroller/sizingoptions |
| `AVPlayerViewController.contextualActions` | Player/SkipButtonPresenter | `var contextualActions: [UIAction] { get set }`; tvOS 15.0+. Shown only when the transport bar is not visible; set to `[]` to dismiss | https://developer.apple.com/documentation/avkit/avplayerviewcontroller/contextualactions |
| `AVContentProposal.automaticAcceptanceInterval` | Player/ProposalPresenter | `var automaticAcceptanceInterval: TimeInterval { get set }`; tvOS 10.0+. Setting it to `.nan` **disables** automatic acceptance (the default is automatic) | https://developer.apple.com/documentation/avkit/avcontentproposal/automaticacceptanceinterval |
| `AVPlayerItemAccessLogEvent.indicatedAverageBitrate` | Player/PlaybackProbe | `var indicatedAverageBitrate: Double { get }`; tvOS 10.0+; **negative when unknown** (the code must treat a negative value as unknown) | https://developer.apple.com/documentation/avfoundation/avplayeritemaccesslogevent/indicatedaveragebitrate |
| `AVPlayer.availableHDRModes` | Player/PlaybackProbe | `nonisolated class var availableHDRModes: AVPlayer.HDRMode { get }`; tvOS 11.2+; **deprecated** ("use eligibleForHDRPlayback instead") | https://developer.apple.com/documentation/avfoundation/avplayer/availablehdrmodes |
| `AVPlayer.eligibleForHDRPlayback` | (replacement, not used) | `nonisolated class var eligibleForHDRPlayback: Bool { get }`; tvOS 13.4+. A single Bool: cannot say which HDR formats exist | https://developer.apple.com/documentation/avfoundation/avplayer/eligibleforhdrplayback |
| `TVTopShelfSectionedContent` | TopShelf/TopShelfProvider | `class TVTopShelfSectionedContent`; `init(sections:)`; tvOS 13.0+ | https://developer.apple.com/documentation/tvservices/tvtopshelfsectionedcontent |
| `TVTopShelfSectionedItem` | TopShelf/TopShelfProvider | `class TVTopShelfSectionedItem` (inherits `TVTopShelfItem`); `imageShape`, `playbackProgress` (0.0 to 1.0), inherited `setImageURL(_:for:)`, `playAction`, `displayAction`; tvOS 13.0+ | https://developer.apple.com/documentation/tvservices/tvtopshelfsectioneditem |

## Findings from this check

- **F-1 (open).** `NavigationLink(_:value:)` and `alert(_:isPresented:presenting:...)` pages show the `LocalizedStringResource` overloads (which for
  `NavigationLink` need a `Codable` value). The app passes plain `String` titles, which should select the `StringProtocol` overloads. Those two
  neighbour pages were not fetched, so this stays an open compile-check item. If it fails: make `Route` `Codable`, or use `NavigationLink(value:) { Text(...) }`.
- **F-2 (changed in code).** `AVPlayer.availableHDRModes` is deprecated. Kept on purpose (the only call that says WHICH formats the TV supports; the
  replacement is one Bool). Expect a deprecation warning, not an error. PROVISIONAL; alternative recorded in the code comment and in OPEN_QUESTIONS.md.
- **F-3 (open).** `UIHostingControllerSizingOptions.intrinsicContentSize` was not on the fetched page. If the compile check rejects it, drop the line:
  the stats overlay then uses a fixed frame.
- **F-4 (code must match).** `indicatedAverageBitrate` is negative when unknown. Checked in the code in the second read (see docs/OPEN_QUESTIONS.md).
- **F-5 (note).** `Tab(... value:, role:)` has `role` without a default in the page's overload; the plain tabs use the overload without `role:`; the
  search tab passes `role: .search`.

## Now Playing on tvOS (checked 2026-11-17 after the second compile; decision R157)

The second compile failed with `PlayerCoordinator.swift:78:20: error: 'updatesNowPlayingInfoCenter' is unavailable in tvOS`. Pages read:

| API | Available on (from the page) | What the page says that matters here | Page |
|---|---|---|---|
| `AVPlayerViewController.updatesNowPlayingInfoCenter` | iOS 10.0+, iPadOS 10.0+, Mac Catalyst 13.1+, visionOS 1.0+. **No tvOS** | A Boolean that says whether the player updates the Now Playing info center; default true. Not on tvOS, so it cannot be set (the compile error) | https://developer.apple.com/documentation/avkit/avplayerviewcontroller/updatesnowplayinginfocenter |
| `AVPlayerItem.externalMetadata` | tvOS listed (no version shown) | Metadata the app supplies for display; the identifiers the player shows are `commonKeyTitle`, `iTunesMetadataTrackSubTitle`, `commonIdentifierArtwork`, `commonKeyDescription`, `iTunesMetadataKeyContentRating`, `quickTimeMetadataKeyGenre` | https://developer.apple.com/documentation/avfoundation/avplayeritem/externalmetadata |
| `MPNowPlayingSession` | tvOS 14.0+ | "An AVPlayerViewController manages its own player and Now Playing session, so you can't add your own Now Playing session." Do not use a session with the AVPlayer an AVPlayerViewController presents | https://developer.apple.com/documentation/mediaplayer/mpnowplayingsession |
| `MPNowPlayingInfoCenter` | tvOS 5.0+ | The system-wide Now Playing dictionary; lists `MPNowPlayingSession` under Now Playing information | https://developer.apple.com/documentation/mediaplayer/mpnowplayinginfocenter |
| `MPRemoteCommandCenter` | tvOS 7.1+ | Remote command targets, through `shared()` | https://developer.apple.com/documentation/mediaplayer/mpremotecommandcenter |
| WWDC17 session 251, "Now Playing and Remote Commands on tvOS" | n/a (video) | With AVKit, give Now Playing information as `AVMutableMetadataItem`s in the player item's `externalMetadata` (identifier, value, `extendedLanguageTag` "und", and a `dataType` for JPEG/PNG artwork). Use `MPNowPlayingInfoCenter` only when playing with some other technology | https://developer.apple.com/videos/play/wwdc2017/251/ |

**What the app does now:** title (`commonIdentifierTitle`) and the episode line (`iTunesMetadataTrackSubTitle`) are set before the item is handed
to the player; the poster (`commonIdentifierArtwork`, data type `kCMMetadataBaseDataType_JPEG` or `_PNG` chosen from the file's first bytes, other
formats left out) is appended when it has been read, a moment after playback starts. The app writes neither `MPNowPlayingInfoCenter` nor
`MPRemoteCommandCenter`; the system player handles position and play/pause. **Not verified on a device** (checklist P10; P10 (d) is whether a
poster added after start is shown). `kCMMetadataBaseDataType_JPEG/PNG` pages were not fetched; the compile run will report them if they are wrong.

## Availability audit: replaced by the compiler (R158)

A page-by-page tvOS availability audit of every Apple symbol was started and then dropped. The compiler reports every API that is unavailable on
tvOS as an error, and the compile check now compiles whole modules and continues after errors (R158), so the next run lists them all. What the
compiler cannot catch is behaviour that differs on tvOS. Those get a row here, with the page, only when that area is worked on:

- Focus and Siri Remote handling (focus order, focus on custom views, touch-surface gestures).
- Menu button behaviour (back, exit to the Home Screen, dismissing sheets and the player).
- AVPlayerViewController's own UI (transport bar, info panel, subtitle and audio menus, content proposals, contextual actions).
- Permission prompts (local network for Bonjour and SSDP).
- Keychain and iCloud behaviour (synchronisable items, CloudKit account changes, multiple users).
- Background limits (what keeps running after the Home button: loopback server, sync).
- File access (no user Documents folder; caches can be removed by the system; App Group container for Top Shelf).

## NOT CHECKED against a page (names used by the app)

- SwiftUI: `TabView(selection:)`, `NavigationStack(path:)`, `navigationDestination(for:)`, `fullScreenCover(item:)`, `onOpenURL`, `searchable`,
  `task`, `focusable`-free default focus, `Observable` macro, `Environment` with an `@Observable` object, `ScrollView`, `LazyVGrid`, `Picker`, `Toggle`,
  `Form`, `Section`, `Label`, `Text`, `ProgressView`, `ForEach`, `ViewThatFits`-free layout. These are long-standing; they are listed so the compile check
  can be pointed at them. Not individually fetched.
- AVKit and AVFoundation: `AVPlayerViewController`, `AVPlayer`, `AVPlayerItem`, `AVMutableMetadataItem`, `AVPlayerViewControllerDelegate`
  `playerViewController(_:...)` content-proposal callbacks, `AVAudioSession.sharedInstance().currentRoute`, `maximumOutputNumberOfChannels`.
- Network: `NWBrowser`, `NWBrowser.Descriptor.bonjour(type:domain:)`. CryptoKit `SHA256`. Security `SecTrustCopyCertificateChain`.
- CloudKit: `CKContainer`, `CKRecord.encryptedValues`, `CKDatabase.modifyRecords(saving:deleting:savePolicy:atomically:)` (defaults). See docs/STORAGE_MODEL.md.
- SF Symbols (names only, rendered by `Image(systemName:)` / `Label(_, systemImage:)`): house, film, tv, folder, sparkles, magnifyingglass, gearshape,
  externaldrive, externaldrive.connected.to.line.below, tray, exclamationmark.triangle, eye, eye.slash, heart, heart.slash, play.fill, play.slash,
  arrow.counterclockwise, square.stack, doc.on.doc, ellipsis, arrow.up.arrow.down, line.3.horizontal.decrease.circle, bookmark, plus, trash, xmark,
  wifi, captions.bubble, photo, doc.text, doc, arrow.clockwise, chart.bar, checkmark.circle. **None verified**: the symbol catalogue is an app
  (SF Symbols) with no page per name. An unknown name draws nothing and does not crash, so the cost of a wrong name is a blank icon. Check on a device.

## Skip segments and Up Next data (SEGMENTS)

Checked against Apple pages through the documentation tool on 2026-11-17.

| Name | Used in | Checked | Page |
|---|---|---|---|
| `AVPlayerViewController.transportBarCustomMenuItems` | App/Features/Player/PlayerMarkMenu.swift, SegmentsWiring.swift | `var transportBarCustomMenuItems: [UIMenuElement] { get set }`, tvOS 15.0+. "Only supports menu elements of type `UIAction` and `UIMenu`, and supports displaying inline one level of submenus." So the mark menu is one `UIMenu` whose children are all `UIAction`; no nested menus. | https://developer.apple.com/documentation/avkit/avplayerviewcontroller/transportbarcustommenuitems |
| `UIMenu` `init(title:image:identifier:options:children:)` | PlayerMarkMenu.swift | Exists, tvOS 13.0+; `UIMenu(title:image:children:)` uses the defaults for `identifier` and `options` (default values of those two were not read on the page: **NOT CHECKED**, the compiler will say). | https://developer.apple.com/documentation/uikit/uimenu |
| `AVPlayerViewController.contextualActions` | existing `SkipButtonPresenter` (unchanged) | Listed in the tvOS player customisation group on the same page as above; its own page was not fetched. **NOT CHECKED**. | https://developer.apple.com/documentation/avkit/avplayerviewcontroller/contextualactions |

NOT CHECKED against a page (used by the SEGMENTS files): `UIAction(title:image:attributes:handler:)` with `.disabled`, `UIImage(systemName:)` names `flag`,
`xmark`, `trash`, `arrow.uturn.backward` (symbol names are not verifiable from pages; a wrong name draws nothing), `String.capitalized`,
`AVContentProposal` / `AVPlayerItem.nextContentProposal` (existing `ProposalPresenter`, unchanged).

Open check for the compile: the `UIAction` handler closure is not marked main-actor in these files; each handler hops with
`Task { @MainActor in ... }` as the stats menu entry already does. If the compiler under Swift 6 mode rejects a capture, make the handler capture only `weak` values.

## SOURCES (source wiring, trust, Bonjour resolution)

Verified (page read): `NWConnection.currentPath` (tvOS 12.0+), `NWPath.remoteEndpoint` (tvOS 12.0+).

NOT CHECKED (used in uncompiled App/ code; confirm at the first compile): `NWBrowser`, `NWEndpoint.service` / `.hostPort`,
`NWEndpoint.Host` text form (the code strips a `%interface` suffix and only keeps IPv4), `NWProtocolIP.Options.version`,
`NWParameters.defaultProtocolStack.internetProtocol`, `sec_protocol_options_set_verify_block`, `sec_trust_copy_ref`,
`SecTrustEvaluateWithError`, `SecTrustCopyCertificateChain`, `SecCertificateCopyData`, `URLSessionStreamTask.startSecureConnection`,
`URLSession` server-trust delegate method, SwiftUI `Picker`, `confirmationDialog(_:isPresented:titleVisibility:presenting:)`,
`.alert(_:isPresented:presenting:)`. Not found on the pages checked: tvOS applicability of `NSBonjourServices` and
`NSLocalNetworkUsageDescription`; the multicast entitlement is not offered for tvOS, so none is requested.

## PLAYBACK (converted playback, display, subtitles)

Pages read for this area (Markdown copies of the Apple pages through the documentation tool). Nothing here has been compiled.

| Name | Used in | Checked | Page |
|---|---|---|---|
| `AVPlayerViewController.appliesPreferredDisplayCriteriaAutomatically` | PlayerCoordinator | tvOS 11.2+. When true the player applies the asset's preferred display criteria itself (dynamic range and frame rate matching, subject to the person's settings). Set explicitly to true. | https://developer.apple.com/documentation/avkit/avplayerviewcontroller/appliespreferreddisplaycriteriaautomatically |
| `AVDisplayManager` (`isDisplayCriteriaMatchingEnabled`, `preferredDisplayCriteria`, `isDisplayModeSwitchInProgress`), `AVDisplayCriteria` | not used by the app | Read to decide that the app does NOT set criteria itself: the HLS playlist carries VIDEO-RANGE, CODECS and FRAME-RATE and the automatic path reads them. Alternative if the device test shows no switch: build an `AVDisplayCriteria` from the frame rate and the format description and set `AVDisplayManager.preferredDisplayCriteria`. | https://developer.apple.com/documentation/avkit/avdisplaymanager |
| `AVPlayerViewController.allowsPictureInPicturePlayback` | PlayerCoordinator | Read; set to true (decision D3). | https://developer.apple.com/documentation/avkit/avplayerviewcontroller/allowspictureinpictureplayback |
| `AVPlayerViewController.transportBarCustomMenuItems` | PlayerCoordinator (picture subtitle menu, mark menu, stats entry) | tvOS 15.0+, `UIAction` and `UIMenu` only, one level of inline submenus. The picture subtitle menu is one `UIMenu` of `UIAction` rows (state `.on` marks the choice). | https://developer.apple.com/documentation/avkit/avplayerviewcontroller/transportbarcustommenuitems |
| `AVPlayerViewController.contentOverlayView` | PictureSubtitleOverlay, stats overlay | tvOS 9.0+. "Noninteractive custom views" between the video and the controls. | https://developer.apple.com/documentation/avkit/avplayerviewcontroller/contentoverlayview |
| `AVPlayerItem.mediaSelectionDidChangeNotification` | PlayerCoordinator | tvOS 13.0+. Posted when the item's media selection changes; used to learn that the system subtitle menu changed (D1 exclusivity) and which audio rendition plays. | https://developer.apple.com/documentation/avfoundation/avplayeritem/mediaselectiondidchangenotification |
| `AVAsset.loadMediaSelectionGroup(for:)` (async throws) | PlayerCoordinator, PlaybackProbe | tvOS 15.0+; `.legible` and `.audible` supported. | https://developer.apple.com/documentation/avfoundation/avasset/loadmediaselectiongroup(for:completionhandler:) |
| `AVPlayerItem.currentMediaSelection`, `AVMediaSelection.selectedMediaOption(in:)` | PlayerCoordinator, PlaybackProbe | tvOS 9.0+. The result may be nil when the group allows an empty selection. | https://developer.apple.com/documentation/avfoundation/avmediaselection/selectedmediaoption(in:) |
| `AVPlayerItem.select(_:in:)` | PlayerCoordinator (turn the text subtitle off) | tvOS 9.0+. nil deselects only if the group's `allowsEmptySelection` is true. | https://developer.apple.com/documentation/avfoundation/avplayeritem/select(_:in:) |
| `UIAction.init(title:subtitle:image:identifier:discoverabilityTitle:attributes:state:handler:)` | PlayerCoordinator | tvOS 15.0+. | https://developer.apple.com/documentation/uikit/uiaction/init(title:subtitle:image:identifier:discoverabilitytitle:attributes:state:handler:) |
| `AVError.Code` cases `fileFormatNotRecognized`, `failedToParse`, `fileFailedToParse`, `formatUnsupported`, `decoderNotFound`, `incompatibleAsset`, `decodeFailed`, `undecodableMediaData` | PlayerCoordinator (error text) | All listed on the page. | https://developer.apple.com/documentation/avfoundation/averror-swift.struct/code |
| `NSAllowsLocalNetworking` | project.yml (already present) | Covers IP addresses and local hostnames, so `http://127.0.0.1:<port>` needs no other ATS key. ATS does not apply to low-level socket APIs (the loopback server uses POSIX sockets). No key was added for PLAYBACK. | https://developer.apple.com/documentation/bundleresources/information-property-list/nsapptransportsecurity/nsallowslocalnetworking |

NOT CHECKED against a page (used in uncompiled App/ code): `AVAudioSession.setCategory(_:mode:)` with `.playback` and `.moviePlayback`, `AVPlayerItem.timeJumpedNotification` (listed on the notification page, its own page not fetched), key-value observing of `AVPlayerItem.status` and `AVPlayerItem.error`, `AVMediaSelectionOption.displayName`, `CGImage.init(width:height:bitsPerComponent:bitsPerPixel:bytesPerRow:space:bitmapInfo:provider:decode:shouldInterpolate:intent:)` with `CGImageAlphaInfo.last` (straight alpha), `CGDataProvider(data:)`, `UIAlertController` presented over the player, `UIImage(systemName: "captions.bubble")` (a wrong symbol name draws nothing), the PiP restore delegate methods (not used: PiP restoring the full screen is on the device checklist), and whether `AVPlayerViewController` keeps a PiP window alive while the loopback server stays up (device checklist).

## ARTWORK AND DISCOVER (pictures, online lookups, Fix Match, Discover, ledger cloud sync, jump list)

Nothing here has been compiled. Pages read through the documentation tool this session are marked checked; everything else is NOT CHECKED.

| Name | Used in | Checked | Page |
|---|---|---|---|
| `View.asyncImageURLSession(_:)` | App/Shared/ArtworkView.swift | tvOS 27.0+ (read earlier; decision D-DS5). The session's `URLCache` is where `AsyncImage` keeps pictures. | https://developer.apple.com/documentation/swiftui/view/asyncimageurlsession(_:) |
| `URLCache.init(memoryCapacity:diskCapacity:directory:)` | App/Support/ArtworkResolving.swift | tvOS 13.0+. "A disk cache measured in the tens of megabytes is acceptable in most cases"; the app uses 100 MB (PROVISIONAL). | https://developer.apple.com/documentation/foundation/urlcache/init(memorycapacity:diskcapacity:directory:) |
| `Menu` (`init(_:systemImage:content:)`) | AlphabetJumpMenu | tvOS 17.0+. | https://developer.apple.com/documentation/swiftui/menu |
| `View.autocorrectionDisabled(_:)` | OnlineLookupSettingsView | tvOS 13.0+. | https://developer.apple.com/documentation/swiftui/view/autocorrectiondisabled(_:) |
| `NotificationCenter.notifications(named:object:)` | CloudSyncHost | tvOS 15.0+; `Notification` is not Sendable, so only a mapped `Void` is iterated. | https://developer.apple.com/documentation/foundation/notificationcenter/notifications(named:object:) |

NOT CHECKED against a page (used in uncompiled App/ code): the Swift spelling of the account-change notification (the Objective-C name `CKAccountChangedNotification` was read, so the app observes `Notification.Name("CKAccountChangedNotification")` as text; the periodic pull is the fallback if the name were wrong), `AsyncImage(url:content:)` with a file URL, `SecureField`, `confirmationDialog(_:isPresented:titleVisibility:presenting:)` on this platform, `ScrollViewReader` and `ScrollViewProxy.scrollTo(_:anchor:)` inside a `LazyVGrid`, `containerRelativeFrame(_:count:spacing:)` (already used by Home shelves), `@Environment(\.scenePhase)`, `FileManager.containerURL(forSecurityApplicationGroupIdentifier:)` for the Top Shelf pictures, whether the Top Shelf extension accepts a PNG or JPEG file named `.jpg` (the app writes the bytes as received), and `UserDefaults` key `onlineRegion` through `@AppStorage`.

## Network and Security (verified 2026-11-17)

Checked by the CI agent: every Network.framework, Security and URLSession trust call in App/Features/Sources/BonjourBrowser.swift,
App/Support/PinnedTransport.swift, Packages/VideoPlayerCore/Sources/SourceFTP/NetworkFTPStream.swift and
Packages/VideoPlayerCore/Sources/SourceUPnP/SSDP.swift, each page fetched through the documentation tool. App/Support/SourceBuilder.swift,
SourceFactory.swift, LiveSourceConnector.swift and TrustCenter.swift were searched and call none of these APIs directly (they use
`URLSessionTransport` from the package and `PinnedTransport`). All pages list tvOS at or below 27. **Nothing here has been compiled.**
The rows of the SOURCES section above that said NOT CHECKED for these names are superseded by this table.

| API | Used in | Signature / availability (from the page) | Result | Page |
|---|---|---|---|---|
| `NWBrowser` (class), `cancel()` | BonjourBrowser | `final class NWBrowser`, Sendable; tvOS 13.0+; `cancel()` listed on the class page | match | https://developer.apple.com/documentation/network/nwbrowser |
| `NWBrowser.init(for:using:)` | BonjourBrowser | `init(for descriptor: NWBrowser.Descriptor, using parameters: NWParameters)`; tvOS 13.0+ | match | https://developer.apple.com/documentation/network/nwbrowser/init(for:using:) |
| `NWBrowser.Descriptor.bonjour(type:domain:)` | BonjourBrowser | `case bonjour(type: String, domain: String?)`; tvOS 13.0+ | match (`domain: nil`) | https://developer.apple.com/documentation/network/nwbrowser/descriptor-swift.enum/bonjour(type:domain:) |
| `NWBrowser.browseResultsChangedHandler` | BonjourBrowser | `@preconcurrency final var browseResultsChangedHandler: (@Sendable (Set<NWBrowser.Result>, Set<NWBrowser.Result.Change>) -> Void)?`; tvOS 13.0+ | match; the closure captures only `weak self` (main-actor class) and a `String`, hops with `Task { @MainActor in }` | https://developer.apple.com/documentation/network/nwbrowser/browseresultschangedhandler |
| `NWBrowser.start(queue:)` | BonjourBrowser | `final func start(queue: DispatchQueue)`; tvOS 13.0+ | match | https://developer.apple.com/documentation/network/nwbrowser/start(queue:) |
| `NWBrowser.Result.endpoint` | BonjourBrowser | listed on `NWBrowser.Result` (struct, Hashable, Sendable); tvOS 13.0+ | match | https://developer.apple.com/documentation/network/nwbrowser/result |
| `NWEndpoint.service(name:type:domain:interface:)` | BonjourBrowser (`if case .service(let name, _, _, _)`) | `case service(name: String, type: String, domain: String, interface: NWInterface?)`; tvOS 12.0+ | match (4 values). The enum also has `.url`, `.unix`, `.opaque`; the code uses `if case`, not an exhaustive switch, so new cases do not break it | https://developer.apple.com/documentation/network/nwendpoint/service(name:type:domain:interface:) |
| `NWEndpoint.hostPort(host:port:)` | BonjourBrowser, SSDP | `case hostPort(host: NWEndpoint.Host, port: NWEndpoint.Port)`; tvOS 12.0+ | match | https://developer.apple.com/documentation/network/nwendpoint/hostport(host:port:) |
| `NWEndpoint.Host` text form | BonjourBrowser | The type conforms to `CustomDebugStringConvertible` only; the page does not document the text format | **FIXED**: the address is now built from `.ipv4(IPv4Address)` + `IPv4Address.rawValue` (`var rawValue: Data`) and `.name(String, NWInterface?)`; the debug text is only the last fallback | https://developer.apple.com/documentation/network/nwendpoint/host , https://developer.apple.com/documentation/network/ipv4address/rawvalue , https://developer.apple.com/documentation/network/nwendpoint/host/name(_:_:) |
| `NWEndpoint.Host.init(_:)` | NetworkFTPStream | `init(_ string: String)`; tvOS 12.0+ | match | https://developer.apple.com/documentation/network/nwendpoint/host/init(_:) |
| `NWEndpoint.Port(rawValue:)`, `.rawValue` | NetworkFTPStream, BonjourBrowser | The page lists `RawRepresentable` conformance and `init(_:)` (string); the `init?(rawValue:)` member page does not exist separately (404), the raw type `UInt16` is not shown | **PARTLY CHECKED** (from the conformance list only) | https://developer.apple.com/documentation/network/nwendpoint/port |
| `NWConnection.init(to:using:)` | BonjourBrowser | `init(to: NWEndpoint, using: NWParameters)`; tvOS 12.0+ | match | https://developer.apple.com/documentation/network/nwconnection/init(to:using:) |
| `NWConnection.init(host:port:using:)` | NetworkFTPStream | `convenience init(host: NWEndpoint.Host, port: NWEndpoint.Port, using: NWParameters)`; tvOS 12.0+ | match | https://developer.apple.com/documentation/network/nwconnection/init(host:port:using:) |
| `NWConnection.stateUpdateHandler`, `NWConnection.State` | BonjourBrowser, NetworkFTPStream | `@preconcurrency final var stateUpdateHandler: (@Sendable (NWConnection.State) -> Void)?`; cases `setup`, `waiting(_:)`, `preparing`, `ready`, `failed(_:)`, `cancelled`; tvOS 12.0+ | match (both switches have `default`) | https://developer.apple.com/documentation/network/nwconnection/stateupdatehandler |
| `NWConnection.start(queue:)`, `cancel()` | BonjourBrowser, NetworkFTPStream | `final func start(queue: DispatchQueue)`, `final func cancel()`; tvOS 12.0+ | match | https://developer.apple.com/documentation/network/nwconnection/start(queue:) |
| `NWConnection.send(content:contentContext:isComplete:completion:)` + `.contentProcessed(_:)` | NetworkFTPStream | `@preconcurrency final func send(content: Data?, contentContext: NWConnection.ContentContext = .defaultMessage, isComplete: Bool = true, completion: NWConnection.SendCompletion)`; `case contentProcessed(@Sendable (NWError?) -> Void)`; tvOS 12.0+ | match (defaults used: default message, complete, no write-close) | https://developer.apple.com/documentation/network/nwconnection/send(content:contentcontext:iscomplete:completion:)-5ecuz |
| `NWConnection.receive(minimumIncompleteLength:maximumLength:completion:)` | NetworkFTPStream | `@preconcurrency final func receive(minimumIncompleteLength: Int, maximumLength: Int, completion: @escaping @Sendable (Data?, NWConnection.ContentContext?, Bool, NWError?) -> Void)`; "invoked exactly once"; content may be nil when complete; tvOS 12.0+ | match | https://developer.apple.com/documentation/network/nwconnection/receive(minimumincompletelength:maximumlength:completion:) |
| `NWParameters.tcp`, `NWParameters.init(tls:tcp:)` | BonjourBrowser, NetworkFTPStream | `final class var tcp: NWParameters { get }`; `convenience init(tls: NWProtocolTLS.Options?, tcp: NWProtocolTCP.Options = NWProtocolTCP.Options())`; tvOS 12.0+ | match | https://developer.apple.com/documentation/network/nwparameters/init(tls:tcp:) |
| `NWParameters.defaultProtocolStack`, `ProtocolStack.internetProtocol`, `NWProtocolIP.Options.version` | BonjourBrowser | `final var defaultProtocolStack: NWParameters.ProtocolStack { get }`; `var internetProtocol: NWProtocolOptions? { get set }`; `var version: NWProtocolIP.Options.Version { get set }`; tvOS 12.0+ | match (the code casts `internetProtocol` to `NWProtocolIP.Options` and sets `.v4`) | https://developer.apple.com/documentation/network/nwprotocolip/options/version-swift.property |
| `NWProtocolTLS.Options()`, `.securityProtocolOptions` | NetworkFTPStream | `init()`; `var securityProtocolOptions: sec_protocol_options_t { get }`; tvOS 12.0+ | match | https://developer.apple.com/documentation/network/nwprotocoltls/options/securityprotocoloptions |
| `sec_protocol_options_set_verify_block(_:_:_:)`, `sec_protocol_verify_t` | NetworkFTPStream (FTPS pin / trust-any) | `func sec_protocol_options_set_verify_block(_ options: sec_protocol_options_t, _ verify_block: @escaping sec_protocol_verify_t, _ verify_block_queue: dispatch_queue_t)`; `typealias sec_protocol_verify_t = (sec_protocol_metadata_t, sec_trust_t, @escaping sec_protocol_verify_complete_t) -> Void` ("may be called one or more times for a given connection"); tvOS 12.0+ | match (the block is idempotent: it re-evaluates each time) | https://developer.apple.com/documentation/security/sec_protocol_options_set_verify_block(_:_:_:) |
| `sec_trust_copy_ref(_:)` | NetworkFTPStream | `func sec_trust_copy_ref(_ trust: sec_trust_t) -> Unmanaged<SecTrust>`; returns a retained reference; tvOS 12.0+ | match (`takeRetainedValue()` is the right balance) | https://developer.apple.com/documentation/security/sec_trust_copy_ref(_:) |
| `SecTrustEvaluateWithError(_:_:)` | PinnedTransport, NetworkFTPStream | `func SecTrustEvaluateWithError(_ trust: SecTrust, _ error: UnsafeMutablePointer<CFError?>?) -> Bool`; tvOS 12.0+. "Don't call ... from your app's main run loop" | match; all three call sites run off the main thread (URLSession delegate queue `nil` = background queue; the TLS verify block runs on the private `ftp.network` queue; the async delegate method of a non-actor class runs on the generic executor) | https://developer.apple.com/documentation/security/sectrustevaluatewitherror(_:_:) |
| `SecTrustCopyCertificateChain(_:)` | PinnedTransport, NetworkFTPStream | `func SecTrustCopyCertificateChain(_ trust: SecTrust) -> CFArray?`; tvOS 15.0+ | match | https://developer.apple.com/documentation/security/sectrustcopycertificatechain(_:) |
| `SecCertificateCopyData(_:)` | PinnedTransport, NetworkFTPStream | `func SecCertificateCopyData(_ certificate: SecCertificate) -> CFData` (DER); tvOS 9.0+ | match (the pin is SHA-256 over the DER leaf) | https://developer.apple.com/documentation/security/seccertificatecopydata(_:) |
| `URLSessionDelegate.urlSession(_:didReceive:) async` | PinnedTransport | `optional func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge) async -> (URLSession.AuthChallengeDisposition, URLCredential?)`; tvOS 9.0+; called for server-trust challenges when a session connects over TLS | match | https://developer.apple.com/documentation/foundation/urlsessiondelegate/urlsession(_:didreceive:completionhandler:) |
| `URLSessionTaskDelegate.urlSession(_:task:didReceive:completionHandler:)` | NetworkFTPStream (`URLSessionFTPStream`) | `optional func urlSession(_ session: URLSession, task: URLSessionTask, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping @Sendable (URLSession.AuthChallengeDisposition, URLCredential?) -> Void)`; tvOS 9.0+. Server trust goes here when the session delegate does not implement the session-level method (true for this class), and `startSecureConnection()` says its callbacks come here | **FIXED**: the completion handler lacked `@Sendable`; added so the witness matches the page exactly | https://developer.apple.com/documentation/foundation/urlsessiontaskdelegate/urlsession(_:task:didreceive:completionhandler:) |
| `URLProtectionSpace.serverTrust`, `NSURLAuthenticationMethodServerTrust` | PinnedTransport, NetworkFTPStream | `var serverTrust: SecTrust? { get }` (nil unless server trust); `let NSURLAuthenticationMethodServerTrust: String`; tvOS 9.0+ | match | https://developer.apple.com/documentation/foundation/urlprotectionspace/servertrust |
| `URLCredential.init(trust:)` | PinnedTransport, NetworkFTPStream | `init(trust: SecTrust)`; tvOS 9.0+; the caller must evaluate the trust first | match, EXCEPT the opt-in `trustAnyCertificate` path in `URLSessionFTPStream`/`NetworkFTPStream`, which accepts without evaluation by design (off by default; the pin takes precedence) | https://developer.apple.com/documentation/foundation/urlcredential/init(trust:) |
| `URLSession.streamTask(withHostName:port:)` | NetworkFTPStream | `func streamTask(withHostName hostname: String, port: Int) -> URLSessionStreamTask`; must call `resume()` (the code does); tvOS 9.0+ | match | https://developer.apple.com/documentation/foundation/urlsession/streamtask(withhostname:port:) |
| `URLSessionStreamTask.readData(ofMinLength:maxLength:timeout:completionHandler:)`, `write(_:timeout:completionHandler:)`, `closeRead()`, `closeWrite()`, `startSecureConnection()` | NetworkFTPStream | `func readData(ofMinLength minBytes: Int, maxLength maxBytes: Int, timeout: TimeInterval, completionHandler: @escaping @Sendable (Data?, Bool, (any Error)?) -> Void)`; `func write(_ data: Data, timeout: TimeInterval, completionHandler: @escaping @Sendable ((any Error)?) -> Void)`; `func startSecureConnection()`; tvOS 9.0+ | match | https://developer.apple.com/documentation/foundation/urlsessionstreamtask |
| `NWMulticastGroup.init(for:from:disableUnicast:)` | SSDP (package; not wired into the app) | `init(for groupAddresses: [NWEndpoint], from: NWEndpoint? = nil, disableUnicast: Bool = false) throws`; tvOS 14.0+ | match | https://developer.apple.com/documentation/network/nwmulticastgroup/init(for:from:disableunicast:) |
| `NWConnectionGroup.init(with:using:)`, `setReceiveHandler(maximumMessageSize:rejectOversizedMessages:handler:)`, `send(content:to:message:completion:)` | SSDP | `init(with: any NWGroupDescriptor, using: NWParameters)`; `@preconcurrency final func setReceiveHandler(maximumMessageSize: Int = Int.max, rejectOversizedMessages: Bool = true, handler: (@Sendable (NWConnectionGroup.Message, Data?, Bool) -> Void)?)`; `@preconcurrency final func send(content: Data?, to: NWEndpoint? = nil, message: NWConnectionGroup.Message = .default, completion: @escaping (NWError?) -> Void)`; tvOS 14.0+ | match. Note: the receive handler is `@Sendable` and mutates a captured `var seen`; fine in language mode 5 (the package's mode), an error in mode 6 | https://developer.apple.com/documentation/network/nwconnectiongroup/setreceivehandler(maximummessagesize:rejectoversizedmessages:handler:) |
| Info.plist `NSBonjourServices` | project.yml | **Available on: iOS 14.0+, iPadOS 14.0+, macOS 11.0+, visionOS 1.0+ — tvOS is NOT listed** | kept (an unused key is harmless); PROVISIONAL, alternative: remove | https://developer.apple.com/documentation/bundleresources/information-property-list/nsbonjourservices |
| Info.plist `NSLocalNetworkUsageDescription` | project.yml, InfoPlist.xcstrings | **Available on: iOS 14.0+, iPadOS 14.0+, macOS 11.0+, visionOS 1.0+ — tvOS is NOT listed** | kept, same reasoning; the device test shows whether any prompt appears | https://developer.apple.com/documentation/bundleresources/information-property-list/nslocalnetworkusagedescription |

Behaviour bug found and fixed while reading against the pages (not a signature mismatch): `NetworkFTPStream.open` scheduled
`connection.cancel()` after `timeout` seconds unconditionally, so every plain/implicit-TLS FTP connection was cancelled 15 seconds
after it opened, even mid-transfer. The cancel now runs only inside the run-once guard, i.e. only when the connection never became ready.

Not in scope of this check and still as recorded elsewhere: the Keychain calls in UserData (`SecItemAdd` / `SecItemCopyMatching` /
`SecItemUpdate` / `SecItemDelete`), CryptoKit `SHA256` (NOT CHECKED here).

## DOLBY VISION (profile 7 conversion, HDR10+ status; 2026-11-17)

| API | Used in | Signature / availability | Result | Page |
|---|---|---|---|---|
| `uname(_:)` / `utsname.machine` | App/Features/Player/PlaybackProbe.swift (`hardwareModel`) | POSIX `int uname(struct utsname *)`; `machine` is a fixed C char array, read up to its NUL | NOT CHECKED against an Apple page (POSIX libc, no Apple documentation page; the model identifier strings AppleTV5,3 / 6,2 / 11,1 / 14,1 are from public model lists, not from an Apple page): PROVISIONAL | — |
| `AVPlayer.availableHDRModes` / `AVPlayer.HDRMode` | unchanged; only `.hlg`, `.hdr10`, `.dolbyVision` exist, so HDR10+ cannot be read from it | deprecated, see PLAYBACK section | Verified that no HDR10+ mode exists (the reason HDR10+ support comes from the model) | https://developer.apple.com/documentation/avfoundation/avplayer/hdrmode |
| HLS `SUPPLEMENTAL-CODECS` with `dvh1.08.LL/db1p`, `cdm4` brand | RemuxEngine master playlist | HLS authoring specification for Apple devices (rev. 2025-06-26) | Verified on the page for Dolby Vision 8.1; `cdm4` for HEVC is PROVISIONAL (the page's example is AV1) | https://developer.apple.com/streaming/hls-authoring-specification-for-apple-devices.html |

No new AVFoundation, AVKit or VideoToolbox call was added; the conversion runs in the package on sample bytes.
## AUDIO (decoded audio to FLAC; 2026-11-17)

| API | Used in | Signature / availability | Result | Page |
|---|---|---|---|---|
| `UserDefaults.object(forKey:)` | App/Features/Player/RemuxPlayback.swift (TrueHD core setting) | `func object(forKey defaultName: String) -> Any?`, all platforms | NOT CHECKED against the page in this session (long-standing Foundation API, already used through `@AppStorage`) | https://developer.apple.com/documentation/foundation/userdefaults/object(forkey:) |
| `@AppStorage`, `Toggle`, `Section(footer:)` | App/Features/Settings/PlaybackSettingsView.swift | same use as the existing toggles in that file | no new API shape | see SwiftUI rows above |
| `UIAlertController(title:message:preferredStyle:)` | App/Features/Player/PlayerCoordinator.swift (title now comes from the notice) | unchanged call | no new API | — |
| HLS `CODECS="fLaC"`, FLAC in fMP4, `CHANNELS` | RemuxEngine playlists (decoded tracks) | HLS authoring specification rules 2.5, 2.25, appendix CODECS table | Verified on the page; speaker mapping of FLAC multichannel not stated on any page (UNVERIFIED, device AU-14) | https://developer.apple.com/streaming/hls-authoring-specification-for-apple-devices.html |

The decoding itself uses FFmpeg's C API (libavcodec, libavutil, libswresample) through Sources/CMediaCodecs, not an Apple framework.
