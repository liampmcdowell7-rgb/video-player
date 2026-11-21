import Foundation
import VideoPlayerCore
import PlaybackLogic
import UserData
import AppLogic

/// Gives the player the skip segments of one library item: user marks, embedded chapters and sidecar files, merged and checked
/// (docs/SEGMENTS.md). #26: IntroDB timings when none of those has any and Free Data Sources is on. R315: the media
/// server's own markers (Plex). R316: what this Apple TV learned by comparing the audio of a season's episodes
/// (`EpisodeAudioReader`), kept in the app's caches folder, which the system may empty (then it is learned again).
///
/// Never throws. When the file cannot be opened, the chapters cannot be read or a sidecar is broken, that source gives nothing and
/// the others still count; an item with nothing gives an empty list, and the player then shows no skip button.
struct SegmentService: Sendable {
    private let provider: SegmentProvider

    init(provider: SegmentProvider) {
        self.provider = provider
    }

    /// Built from the app's parts. `openSource` is asked on the main actor because `AppServices.makeSource` lives there.
    @MainActor
    init(services: AppServices) {
        let sqlite = services.sqlite
        let online: SegmentProvider.OnlineTimings? = SegmentProvider.onlineTimings(services.online.segmentLookup)
        let opener: SegmentProvider.SourceOpener = { [services] sourceID in
            await MainActor.run { () -> (any MediaSource)? in
                guard let definition = services.definitions.first(where: { $0.id == sourceID }) else { return nil }
                return services.makeSource(definition)
            }
        }
        self.provider = SegmentProvider(
            store: sqlite,
            ledger: services.ledger,
            itemKey: { id in try? await sqlite.userDataKey(forItem: id) },
            openSource: opener,
            online: online,
            detection: Self.detectionStore)
        self.openSource = opener
    }

    private var openSource: SegmentProvider.SourceOpener = { _ in nil }

    /// One store for the whole app, so two playbacks never write the same season file at once. Local only.
    static let detectionStore: SeasonDetectionStore = {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first ?? FileManager.default.temporaryDirectory
        return SeasonDetectionStore(directory: base.appendingPathComponent("SegmentDetection", isDirectory: true))
    }()

    /// R316: learns the intro and credits of `itemID` from its audio when this Apple TV has not yet (background priority;
    /// does nothing for films, unknown lengths, files analysed before, or sources without a link the system can open).
    func learn(forItem itemID: Int64) async {
        guard let target = await provider.analysisTarget(forItem: itemID), let source = await openSource(target.sourceID),
              let access = try? await source.playbackAccess(for: target.file.path) else { return }
        await EpisodeAudioReader.analyse(target, access: access) { record in await provider.store(record, for: target) }
    }

    /// The merged segments of the file the player will open (the item's preferred version). Empty when there are none.
    func segments(forItem itemID: Int64) async -> [Segment] {
        await provider.segments(forItem: itemID)
    }

    /// The same plus one line per source saying what was read and what was skipped. For File Details and for tests.
    func collection(forItem itemID: Int64) async -> SegmentCollection? {
        await provider.collection(forItem: itemID)
    }
}

extension AppServices {
    /// A service over the current library, ledger and sources. Cheap to build; nothing is stored on `AppServices`.
    var segmentService: SegmentService { SegmentService(services: self) }
}
