import Foundation
import VideoPlayerCore
import PlaybackLogic
import UserData
import AppLogic

/// Gives the player the skip segments of one library item: user marks, embedded chapters and sidecar files, merged and checked
/// (docs/SEGMENTS.md). #26: IntroDB timings when none of those has any and Free Data Sources is on. On-device
/// detection is a later item (docs/FEATURE_BACKLOG.md item 34).
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
        let lookup = services.online.segmentLookup
        self.provider = SegmentProvider(
            store: sqlite,
            ledger: services.ledger,
            itemKey: { id in try? await sqlite.userDataKey(forItem: id) },
            openSource: { [services] sourceID in
                await MainActor.run { () -> (any MediaSource)? in
                    guard let definition = services.definitions.first(where: { $0.id == sourceID }) else { return nil }
                    return services.makeSource(definition)
                }
            },
            online: lookup.map { lookup in { item, file in await lookup.segments(for: item, file: file) } })
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
