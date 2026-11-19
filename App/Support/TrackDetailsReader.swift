import Foundation
import VideoPlayerCore
import LibraryIndex
import AppLogic

extension AppServices {
    /// Reads one file's header for the detail page's Media Info (#21 C, OPEN_QUESTIONS R192): opens the file's source the
    /// same way the player's chapter reading does (`SegmentService`) and hands it to `MediaTrackProbe`. Nil when the source
    /// is gone, the container is not read or the read fails; the rows then keep saying "Not checked yet" (#25 B6).
    var trackDetailsReader: @Sendable (StoredFile) async -> FileTrackDetails? {
        { [self] file in
            guard MediaTrackProbe.canRead(file) else { return nil }
            let source = await MainActor.run { () -> (any MediaSource)? in
                guard let definition = self.definitions.first(where: { $0.id == file.sourceID }) else { return nil }
                return self.makeSource(definition)
            }
            guard let source else { return nil }
            return await MediaTrackProbe.read(file, from: source)
        }
    }
}
