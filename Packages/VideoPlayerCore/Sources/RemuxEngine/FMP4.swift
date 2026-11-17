import Foundation

// Fragmented MP4 writer: an init segment (ftyp + moov with empty sample tables + mvex) per track and one
// moof + mdat fragment per segment. Layout follows ISO/IEC 14496-12 and the HLS fMP4 conventions:
// default-base-is-moof, version 1 tfdt, version 1 trun with composition offsets for video.

/// Colour description for the `colr` box (type "nclx").
public struct ColourInfo: Equatable, Sendable {
    public var primaries: Int
    public var transfer: Int
    public var matrix: Int
    public var fullRange: Bool
    public init(primaries: Int, transfer: Int, matrix: Int, fullRange: Bool) {
        self.primaries = primaries; self.transfer = transfer; self.matrix = matrix; self.fullRange = fullRange
    }
}

public enum VideoCodecConfig: Equatable, Sendable {
    case hevc(HVCConfig)
    case avc(AVCConfig)
}

public struct VideoTrackConfig: Equatable, Sendable {
    public var trackID: UInt32
    public var codec: VideoCodecConfig
    public var width: Int
    public var height: Int
    /// "hvc1", "dvh1" or "avc1".
    public var sampleEntry: String
    public var colour: ColourInfo?
    public var hdr: HDRStaticMetadata
    public var dolbyVision: MKVDolbyVisionMapping?
    public var language: String
    public var timescale: UInt32 = 90000
    public var frameRate: Double?

    public var codecString: String {
        switch codec {
        case .hevc(let c): return c.codecString(fourCC: sampleEntry == "dvh1" ? "hvc1" : sampleEntry)
        case .avc(let c): return c.codecString()
        }
    }
}

public enum TrackConfig: Equatable, Sendable {
    case video(VideoTrackConfig)
    case audio(AudioTrackConfig)
    public var trackID: UInt32 {
        switch self { case .video(let v): return v.trackID; case .audio(let a): return a.trackID }
    }
    public var timescale: UInt32 {
        switch self { case .video(let v): return v.timescale; case .audio(let a): return a.timescale }
    }
}

public struct FMP4Sample: Sendable {
    public var data: ArraySlice<UInt8>
    /// Duration in track timescale ticks.
    public var duration: UInt32
    public var isSync: Bool
    /// Composition time offset (pts - dts) in ticks. Always 0 for audio.
    public var compositionOffset: Int32
    public init(data: ArraySlice<UInt8>, duration: UInt32, isSync: Bool, compositionOffset: Int32 = 0) {
        self.data = data; self.duration = duration; self.isSync = isSync; self.compositionOffset = compositionOffset
    }
}

/// A fragment split into its header and sample payloads (see `FMP4Writer.fragmentParts`).
public struct FragmentParts: Sendable {
    public var head: [UInt8]
    public var samples: [ArraySlice<UInt8>]
    public var byteCount: Int { head.count + samples.reduce(0) { $0 + $1.count } }
    public func flattened() -> [UInt8] {
        var out = head
        out.reserveCapacity(byteCount)
        for s in samples { out.append(contentsOf: s) }
        return out
    }
}

/// Turns configuration and samples into init segments and fragments.
public protocol FragmentWriter: Sendable {
    func initSegment(for track: TrackConfig) -> [UInt8]
    func fragment(for track: TrackConfig, sequence: UInt32, baseDecodeTime: UInt64, samples: [FMP4Sample]) -> [UInt8]
}

public struct FMP4Writer: FragmentWriter {
    public init() {}

    // Sample flags used in trun / trex (ISO 14496-12 8.8.3.1).
    static let syncFlags: UInt32 = 0x0200_0000        // depends_on = 2 (no other samples), is_non_sync = 0
    static let nonSyncFlags: UInt32 = 0x0101_0000     // depends_on = 1, is_non_sync = 1

    public func initSegment(for track: TrackConfig) -> [UInt8] {
        var w = ByteWriter(capacity: 2048)
        w.box("ftyp") { w in
            w.fourCC("iso6")
            w.u32(0)
            for b in ["iso6", "cmfc", "mp41", "hlsf"] { w.fourCC(b) }
        }
        w.box("moov") { w in
            w.fullBox("mvhd", version: 0, flags: 0) { w in
                w.u32(0); w.u32(0); w.u32(1000); w.u32(0)
                w.u32(0x0001_0000); w.u16(0x0100); w.u16(0); w.u32(0); w.u32(0)
                Self.identityMatrix(&w)
                w.zeros(24)
                w.u32(track.trackID + 1)
            }
            w.box("trak") { w in
                w.fullBox("tkhd", version: 0, flags: 3) { w in
                    w.u32(0); w.u32(0); w.u32(track.trackID); w.u32(0); w.u32(0)
                    w.u32(0); w.u32(0)
                    w.u16(0); w.u16(0)
                    if case .audio = track { w.u16(0x0100) } else { w.u16(0) }
                    w.u16(0)
                    Self.identityMatrix(&w)
                    if case .video(let v) = track { w.u32(UInt32(v.width) << 16); w.u32(UInt32(v.height) << 16) } else { w.u32(0); w.u32(0) }
                }
                w.box("mdia") { w in
                    w.fullBox("mdhd", version: 0, flags: 0) { w in
                        w.u32(0); w.u32(0); w.u32(track.timescale); w.u32(0)
                        w.u16(Self.packedLanguage(track))
                        w.u16(0)
                    }
                    w.fullBox("hdlr", version: 0, flags: 0) { w in
                        w.u32(0)
                        if case .video = track { w.fourCC("vide") } else { w.fourCC("soun") }
                        w.zeros(12)
                        let name = Array((track.isVideo ? "VideoHandler" : "SoundHandler").utf8)
                        w.append(name); w.u8(0)
                    }
                    w.box("minf") { w in
                        if case .video = track {
                            w.fullBox("vmhd", version: 0, flags: 1) { w in w.u16(0); w.u16(0); w.u16(0); w.u16(0) }
                        } else {
                            w.fullBox("smhd", version: 0, flags: 0) { w in w.u16(0); w.u16(0) }
                        }
                        w.box("dinf") { w in
                            w.fullBox("dref", version: 0, flags: 0) { w in
                                w.u32(1)
                                w.fullBox("url ", version: 0, flags: 1) { _ in }
                            }
                        }
                        w.box("stbl") { w in
                            w.fullBox("stsd", version: 0, flags: 0) { w in
                                w.u32(1)
                                switch track {
                                case .video(let v): Self.videoSampleEntry(&w, v)
                                case .audio(let a): Self.audioSampleEntry(&w, a)
                                }
                            }
                            w.fullBox("stts", version: 0, flags: 0) { w in w.u32(0) }
                            w.fullBox("stsc", version: 0, flags: 0) { w in w.u32(0) }
                            w.fullBox("stsz", version: 0, flags: 0) { w in w.u32(0); w.u32(0) }
                            w.fullBox("stco", version: 0, flags: 0) { w in w.u32(0) }
                        }
                    }
                }
            }
            w.box("mvex") { w in
                w.fullBox("trex", version: 0, flags: 0) { w in
                    w.u32(track.trackID); w.u32(1); w.u32(0); w.u32(0)
                    w.u32(track.isVideo ? Self.nonSyncFlags : Self.syncFlags)
                }
            }
        }
        return w.bytes
    }

    public func fragment(for track: TrackConfig, sequence: UInt32, baseDecodeTime: UInt64, samples: [FMP4Sample]) -> [UInt8] {
        let parts = fragmentParts(for: track, sequence: sequence, baseDecodeTime: baseDecodeTime, samples: samples)
        return parts.flattened()
    }

    /// The fragment as a header (moof and the mdat box header) followed by the sample slices, so a server can send
    /// the samples straight from the window they were read into, without a second copy.
    public func fragmentParts(for track: TrackConfig, sequence: UInt32, baseDecodeTime: UInt64, samples: [FMP4Sample]) -> FragmentParts {
        let isVideo = track.isVideo
        var w = ByteWriter(capacity: 512 + samples.count * 16)
        var dataOffsetPatch = 0
        w.box("moof") { w in
            w.fullBox("mfhd", version: 0, flags: 0) { w in w.u32(sequence) }
            w.box("traf") { w in
                // tfhd: default-base-is-moof (0x020000) + default-sample-flags-present (0x20)
                w.fullBox("tfhd", version: 0, flags: 0x020020) { w in
                    w.u32(track.trackID)
                    w.u32(isVideo ? Self.nonSyncFlags : Self.syncFlags)
                }
                w.fullBox("tfdt", version: 1, flags: 0) { w in w.u64(baseDecodeTime) }
                // trun: data-offset (0x1), duration (0x100), size (0x200), [flags (0x400), cts (0x800)] for video
                let flags: UInt32 = isVideo ? 0x000F01 : 0x000301
                w.fullBox("trun", version: 1, flags: flags) { w in
                    w.u32(UInt32(samples.count))
                    dataOffsetPatch = w.count
                    w.u32(0)
                    for s in samples {
                        w.u32(s.duration)
                        w.u32(UInt32(s.data.count))
                        if isVideo {
                            w.u32(s.isSync ? Self.syncFlags : Self.nonSyncFlags)
                            w.i32(s.compositionOffset)
                        }
                    }
                }
            }
        }
        w.patchU32(at: dataOffsetPatch, UInt32(w.count + 8))     // moof size + mdat header, relative to the moof start
        let payload = samples.reduce(0) { $0 + $1.data.count }
        w.u32(UInt32(payload + 8)); w.fourCC("mdat")
        return FragmentParts(head: w.bytes, samples: samples.map { $0.data })
    }

    // MARK: pieces

    private static func identityMatrix(_ w: inout ByteWriter) {
        for v: UInt32 in [0x0001_0000, 0, 0, 0, 0x0001_0000, 0, 0, 0, 0x4000_0000] { w.u32(v) }
    }

    /// ISO-639-2/T code packed as three 5-bit letters; "und" when unknown.
    static func packedLanguage(_ track: TrackConfig) -> UInt16 {
        let lang: String
        switch track { case .video(let v): lang = v.language; case .audio(let a): lang = a.language }
        return packLanguage(lang)
    }

    public static func packLanguage(_ lang: String) -> UInt16 {
        let two: [String: String] = ["en": "eng", "fr": "fra", "de": "deu", "es": "spa", "it": "ita", "ja": "jpn", "ko": "kor",
                                     "zh": "zho", "pt": "por", "ru": "rus", "nl": "nld", "sv": "swe", "pl": "pol", "tr": "tur"]
        var l = lang.lowercased()
        if l.count == 2, let m = two[l] { l = m }
        let chars = Array(l.unicodeScalars)
        guard chars.count == 3, chars.allSatisfy({ $0.value >= 0x61 && $0.value <= 0x7A }) else { return packLanguage("und") }
        return UInt16((chars[0].value - 0x60) << 10 | (chars[1].value - 0x60) << 5 | (chars[2].value - 0x60))
    }

    private static func visualHeader(_ w: inout ByteWriter, width: Int, height: Int, compressor: String) {
        w.zeros(6); w.u16(1)                                  // data_reference_index
        w.u16(0); w.u16(0); w.zeros(12)                        // pre_defined, reserved, pre_defined[3]
        w.u16(UInt16(width)); w.u16(UInt16(height))
        w.u32(0x0048_0000); w.u32(0x0048_0000)                 // 72 dpi
        w.u32(0); w.u16(1)                                     // reserved, frame_count
        w.fixedString(compressor, length: 32)
        w.u16(0x18); w.u16(0xFFFF)                             // depth, pre_defined = -1
    }

    static func videoSampleEntry(_ w: inout ByteWriter, _ v: VideoTrackConfig) {
        w.box(v.sampleEntry) { w in
            visualHeader(&w, width: v.width, height: v.height, compressor: "")
            switch v.codec {
            case .hevc(let c): w.box("hvcC") { w in w.append(c.raw) }
            case .avc(let c): w.box("avcC") { w in w.append(c.raw) }
            }
            if let dv = v.dolbyVision, case .hevc = v.codec {
                // Box name follows the profile (dvcC up to profile 7, dvvC above), as FFmpeg and Dolby specify.
                w.box(dv.profile <= 7 ? "dvcC" : "dvvC") { w in w.append(dv.record) }
            }
            if let c = v.colour {
                w.box("colr") { w in
                    w.fourCC("nclx"); w.u16(UInt16(c.primaries)); w.u16(UInt16(c.transfer)); w.u16(UInt16(c.matrix))
                    w.u8(c.fullRange ? 0x80 : 0)
                }
            }
            if let m = v.hdr.mdcv { w.box("mdcv") { w in w.append(m) } }
            if let l = v.hdr.clli { w.box("clli") { w in w.append(l) } }
        }
    }

    static func audioSampleEntry(_ w: inout ByteWriter, _ a: AudioTrackConfig) {
        let entry: String
        switch a.codec { case .ac3: entry = "ac-3"; case .eac3: entry = "ec-3"; case .aac: entry = "mp4a"; case .flac: entry = "fLaC" }
        w.box(entry) { w in
            w.zeros(6); w.u16(1)
            w.u16(0); w.u16(0); w.u32(0)                       // version 0 sound entry
            w.u16(UInt16(a.channels)); w.u16(UInt16(a.bitsPerSample)); w.u16(0); w.u16(0)
            w.u32(a.sampleRate << 16)
            switch a.codec {
            case .ac3: w.box("dac3") { w in w.append(a.specific) }
            case .eac3: w.box("dec3") { w in w.append(a.specific) }
            case .flac: w.fullBox("dfLa", version: 0, flags: 0) { w in w.append(a.specific) }
            case .aac: w.fullBox("esds", version: 0, flags: 0) { w in esDescriptor(&w, a) }
            }
        }
    }

    /// ES_Descriptor with DecoderConfigDescriptor (MPEG-4 audio, object type 0x40) and the AudioSpecificConfig.
    private static func esDescriptor(_ w: inout ByteWriter, _ a: AudioTrackConfig) {
        func len(_ n: Int) -> [UInt8] { [0x80, 0x80, 0x80, UInt8(n)] }       // 4-byte form, as FFmpeg writes it
        let asc = a.specific
        let decSpec: [UInt8] = [0x05] + len(asc.count) + asc
        let bitrate = UInt32(max(a.bitrate, 0))
        var dcd = ByteWriter()
        dcd.u8(0x40); dcd.u8(0x15); dcd.u24(0); dcd.u32(bitrate); dcd.u32(bitrate)
        dcd.append(decSpec)
        let decoderConfig: [UInt8] = [0x04] + len(dcd.count) + dcd.bytes
        let sl: [UInt8] = [0x06, 0x80, 0x80, 0x80, 0x01, 0x02]
        var es = ByteWriter()
        es.u16(UInt16(a.trackID & 0xFFFF)); es.u8(0)
        es.append(decoderConfig); es.append(sl)
        w.append([0x03] + len(es.count) + es.bytes)
    }
}

extension TrackConfig {
    var isVideo: Bool { if case .video = self { return true } else { return false } }
}
