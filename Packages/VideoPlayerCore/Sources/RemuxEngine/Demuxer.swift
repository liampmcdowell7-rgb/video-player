import Foundation
import VideoPlayerCore

// The demuxer: turns a segment of the plan into frames by reading one window of the file (the clusters from the
// starting keyframe's cluster through the cluster that holds the next cut keyframe) and parsing it.

public protocol MediaDemuxer: Sendable {
    var index: MKVIndex { get }
    /// The frames of all tracks in `tracks` that lie in the window of `segment`, in file order.
    func window(for segment: SegmentSpec, next: SegmentSpec?, tracks: Set<Int>) async throws -> DemuxedWindow
}

/// The parsed frames of one window and how many bytes were read for it.
public struct DemuxedWindow: Sendable {
    public var frames: [MKVFrame]
    public var bytesRead: Int64
    public var byteRange: ByteRange
}

public struct MatroskaDemuxer: MediaDemuxer {
    public let reader: any ByteRangeReader
    public let index: MKVIndex

    public init(reader: any ByteRangeReader, index: MKVIndex) { self.reader = reader; self.index = index }

    public func window(for segment: SegmentSpec, next: SegmentSpec?, tracks: Set<Int>) async throws -> DemuxedWindow {
        let start = segment.clusterStart
        var end = index.clusterRegionEnd
        if let next {
            // One small read gives the size of the cluster that holds the next keyframe.
            let head = [UInt8](try await reader.read(ByteRange(offset: next.clusterStart, length: 32)))
            let (id, idl) = try EBML.readID(head, 0)
            guard id == EBMLID.cluster else { throw RemuxError.malformed("no cluster at \(next.clusterStart)") }
            let (size, sl) = try EBML.readSize(head, idl)
            if let size { end = min(end, next.clusterStart + Int64(idl + sl) + size) }
        }
        guard end > start else { throw RemuxError.malformed("empty window for segment \(segment.index)") }
        if Task.isCancelled { throw RemuxError.cancelled }
        let data = [UInt8](try await reader.read(ByteRange(offset: start, length: end - start)))
        let parsed = try MatroskaClusterParser.parse(window: data, windowOffset: start, tracks: index.tracks, timecodeScale: index.timecodeScale)
        let kept = parsed.frames.filter { tracks.contains($0.track) }
        return DemuxedWindow(frames: kept, bytesRead: Int64(data.count), byteRange: ByteRange(offset: start, length: end - start))
    }
}

