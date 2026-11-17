import Foundation
import RemuxEngine
import PlaybackStatus
import DolbyVisionRPU

// Dolby Vision and HDR10+ glue for the converting player (docs/DOLBY_VISION.md).

extension RemuxPlaybackModel {
    /// The engine options the app opens every file with: Dolby Vision profile 7 is converted to 8.1 when this build has
    /// the RPU library (all Apple builds do; Linux test builds only with VP_LIBDOVI). One converter per playback, so its
    /// counters describe that file.
    public static func engineOptions(_ base: RemuxOptions = RemuxOptions()) -> RemuxOptions {
        var options = base
        if options.dolbyVisionConverter == nil { options.dolbyVisionConverter = DolbyVisionProfile7Converter.native() }
        return options
    }
}

public enum DeviceVideoCapabilities {
    /// Whether the device with this hardware model identifier (`uname` machine, e.g. "AppleTV11,1") sends HDR10+
    /// metadata. support.apple.com/102339: "HDR10+ is a supported format only on Apple TV 4K (3rd generation) and later";
    /// the tech specs pages list no HDR10+ for Apple TV HD (111928), 4K 1st generation (111929) and 2nd generation (111922).
    /// Model identifiers: AppleTV5,3 HD, AppleTV6,2 4K 1st gen, AppleTV11,1 4K 2nd gen, AppleTV14,1 4K 3rd gen.
    /// PROVISIONAL: any later major number (14 and up) is taken as "3rd generation and later". Alternative: `.unknown`
    /// for identifiers not listed, which shows the neutral HDR10 sentence on new models.
    public static func sendsHDR10Plus(modelIdentifier: String) -> Tri {
        let prefix = "AppleTV"
        guard modelIdentifier.hasPrefix(prefix),
              let major = Int(modelIdentifier.dropFirst(prefix.count).prefix(while: { $0.isNumber })) else { return .unknown }
        if major >= 14 { return .yes }
        if [5, 6, 11].contains(major) { return .no }
        return .unknown
    }
}
