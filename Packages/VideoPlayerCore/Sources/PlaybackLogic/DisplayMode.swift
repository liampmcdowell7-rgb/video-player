import Foundation

// "Keep the display mode when the next episode's format matches, so there is no needless display switch."
// Pure comparison of two video formats. The Apple TV side (AVDisplayCriteria, "Match Content") applies the result.
// Not verified on a device: whether tvOS really needs a switch for each difference reported here (see
// docs/PLAYBACK_LOGIC.md "What only an Apple TV can verify").

/// The dynamic range family the display has to be put into.
public enum DynamicRangeFormat: String, Sendable, Codable, CaseIterable {
    case sdr, hdr10, hdr10Plus, hlg, dolbyVision

    /// What the display mode is set to. PROVISIONAL: HDR10+ is output as HDR10 (the Apple TV is not known to output
    /// HDR10+), and every Dolby Vision profile is one display mode.
    var displayFamily: DynamicRangeFormat { self == .hdr10Plus ? .hdr10 : self }
}

/// Size class of a picture. Compared by class, not by exact pixels, because the Apple TV keeps one output resolution:
/// 1920x1080 and 1920x800 are both `hd`.
public enum ResolutionClass: Int, Sendable, Comparable, Codable {
    case sd = 0, hd = 1, uhd = 2

    public static func < (a: ResolutionClass, b: ResolutionClass) -> Bool { a.rawValue < b.rawValue }

    /// Classifies by the larger of the height and the height a 16:9 picture of this width would have, so a wide
    /// cinema crop (3840x1600) is `uhd` and (1920x800) is `hd`. Below 720 lines is `sd`; 1440 lines and above is `uhd`.
    public init(width: Int, height: Int) {
        let effective = max(height, width * 9 / 16)
        if effective < 720 { self = .sd } else if effective < 1440 { self = .hd } else { self = .uhd }
    }
}

public struct DisplayFormat: Equatable, Sendable, Codable {
    public var width: Int
    public var height: Int
    /// Frames per second (23.976, 24, 25, 29.97, 50, 59.94 ...).
    public var frameRate: Double
    public var dynamicRange: DynamicRangeFormat

    public init(width: Int, height: Int, frameRate: Double, dynamicRange: DynamicRangeFormat) {
        self.width = width
        self.height = height
        self.frameRate = frameRate
        self.dynamicRange = dynamicRange
    }

    public var resolutionClass: ResolutionClass { ResolutionClass(width: width, height: height) }
}

public enum DisplayDifference: Equatable, Sendable {
    case resolution
    case frameRate
    case dynamicRange
}

public enum DisplayKeepReason: Equatable, Sendable {
    /// Same resolution class, same frame rate and the same dynamic range family.
    case formatsMatch
    /// The next episode's format is not known: never switch on a guess.
    case nextFormatUnknown
    /// The current format is not known: nothing to compare with, so do not switch.
    case currentFormatUnknown
}

public enum DisplayModeDecision: Equatable, Sendable {
    /// Leave the display mode alone (no needless display switch).
    case keep(DisplayKeepReason)
    /// The formats differ: switch to the next episode's format.
    case switchMode(to: DisplayFormat, differences: [DisplayDifference])
}

public enum DisplayModePlanner {
    /// Two frame rates closer than this are the same (23.976 and 24 are NOT: they are 0.024 apart).
    public static let frameRateTolerance = 0.01

    public static func decide(current: DisplayFormat?, next: DisplayFormat?) -> DisplayModeDecision {
        guard let next else { return .keep(.nextFormatUnknown) }
        guard let current else { return .keep(.currentFormatUnknown) }
        var differences: [DisplayDifference] = []
        if current.resolutionClass != next.resolutionClass { differences.append(.resolution) }
        if abs(current.frameRate - next.frameRate) > frameRateTolerance { differences.append(.frameRate) }
        if current.dynamicRange.displayFamily != next.dynamicRange.displayFamily { differences.append(.dynamicRange) }
        return differences.isEmpty ? .keep(.formatsMatch) : .switchMode(to: next, differences: differences)
    }
}
