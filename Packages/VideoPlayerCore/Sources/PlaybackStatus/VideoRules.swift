import Foundation

/// Video / HDR half of the honest status rules. See docs/PLAYBACK_STATUS.md for the full table.
extension StatusRules {

    static let displayUnknownOutput = "Display mode: unknown"
    static let unknownDisplayClause = "Apple TV did not report which HDR modes this display supports"
    static let matchOffSentence = "Match Dynamic Range is off in Apple TV settings, so the display is not switched for this file."
    static let fallbackUnconfirmedClause = "the fallback player does not confirm which display mode is active"

    private struct Plan {
        var output: String
        var mode: DisplayMode?
        var path: VideoPath
        var note: String?
        /// true when `note` only says the display's abilities are unknown.
        var noteIsUnknownDisplay = false
    }

    private static func supports(_ s: DisplayHDRModes, _ mode: DisplayMode) -> Bool {
        switch mode {
        case .sdr: return true
        case .hdr10: return s.contains(.hdr10)
        case .hlg: return s.contains(.hlg)
        case .dolbyVision: return s.contains(.dolbyVision)
        }
    }

    /// The display mode the file should end up in, ignoring what the display reports as active.
    /// nil when it cannot be told (display abilities unknown, or Profile 5 on a display without Dolby Vision).
    /// The next-episode logic uses this to decide whether the display must switch.
    public static func expectedMode(_ format: HDRFormat, availableHDR: DisplayHDRModes?, profile7: Profile7Conversion) -> DisplayMode? {
        video(format, display: DisplayState(availableHDR: availableHDR, activeMode: nil, matchDynamicRange: .yes),
              engine: .primary, profile7: profile7).mode
    }

    public static func video(_ format: HDRFormat, display: DisplayState, engine: PlaybackEngine,
                             profile7: Profile7Conversion) -> VideoStatus {
        let contains = format.containsText
        var plan = engine == .fallback ? fallbackPlan(format, display: display) : primaryPlan(format, display: display, profile7: profile7)

        // The user's setting stops the app from switching the display for HDR files.
        if engine == .primary && display.matchDynamicRange == .no && format != .sdr {
            if let a = display.activeMode {
                plan = Plan(output: a.displayName, mode: a, path: .passthrough, note: matchOffSentence)
            } else {
                plan = Plan(output: displayUnknownOutput, mode: nil, path: .unknown, note: matchOffSentence)
            }
            return VideoStatus(contains: contains, output: plan.output, note: plan.note, path: plan.path, mode: plan.mode)
        }

        // The display told us what it is really doing: that beats what we expected.
        if let a = display.activeMode, plan.mode != a {
            if let expected = plan.mode {
                plan = Plan(output: a.displayName, mode: a, path: plan.path,
                            note: "The display is in \(a.displayName) mode, not \(expected.displayName).")
            } else {
                plan = Plan(output: a.displayName, mode: a, path: .passthrough,
                            note: plan.noteIsUnknownDisplay ? nil : plan.note)
            }
        }
        return VideoStatus(contains: contains, output: plan.output, note: plan.note, path: plan.path, mode: plan.mode)
    }

    // MARK: Primary player

    private static func unknownPlan(extras: [String] = []) -> Plan {
        Plan(output: displayUnknownOutput, mode: nil, path: .unknown,
             note: sentence(unknownDisplayClause, extras),
             noteIsUnknownDisplay: true)
    }

    private static func primaryPlan(_ format: HDRFormat, display: DisplayState, profile7: Profile7Conversion) -> Plan {
        if format == .sdr { return Plan(output: "SDR", mode: .sdr, path: .sdr, note: nil) }
        guard let s = display.availableHDR else {
            var extras: [String] = []
            if case .dolbyVision(let p) = format, p.isProfile7, profile7 != .available {
                extras.append(profile7 == .failedForThisFile
                              ? "Dolby Vision Profile 7 conversion failed for this file"
                              : "Dolby Vision Profile 7 conversion is not available on this device")
            }
            return unknownPlan(extras: extras)
        }

        switch format {
        case .sdr:
            return Plan(output: "SDR", mode: .sdr, path: .sdr, note: nil)
        case .hdr10:
            return signalPlan(.hdr10, label: "HDR10", s: s, suffix: "", note: nil)
        case .hdr10Plus:
            // The display mode is HDR10 either way; HDR10+ is HDR10 plus per-scene metadata the display may use.
            switch display.sendsHDR10Plus {
            case .yes:
                var plan = signalPlan(.hdr10, label: "HDR10", s: s, suffix: "", note: nil)
                if plan.mode == .hdr10 {
                    plan.output = "HDR10+ or HDR10"
                    plan.note = "This Apple TV sends the HDR10+ metadata when the display supports it; it does not report whether the display uses it."
                }
                return plan
            case .no:
                return signalPlan(.hdr10, label: "HDR10", s: s, suffix: "",
                                  note: "This Apple TV model does not support HDR10+, so this plays as HDR10.")
            case .unknown:
                return signalPlan(.hdr10, label: "HDR10", s: s, suffix: "",
                                  note: "The app could not tell whether this Apple TV model sends HDR10+ metadata, so this is shown as HDR10.")
            }
        case .hlg:
            return signalPlan(.hlg, label: "HLG", s: s, suffix: "", note: nil)
        case .dolbyVision(let p):
            return dolbyVisionPlan(p, s: s, profile7: profile7)
        }
    }

    /// Plays `signal` if the display supports it, otherwise tone-maps to SDR.
    private static func signalPlan(_ signal: DisplayMode, label: String, s: DisplayHDRModes, suffix: String, note: String?,
                                   path: VideoPath = .passthrough) -> Plan {
        if supports(s, signal) {
            return Plan(output: label + suffix, mode: signal, path: path, note: note)
        }
        return Plan(output: "SDR (tone-mapped from \(label))", mode: .sdr, path: .toneMappedToSDR,
                    note: "This display does not support \(label), so the picture is tone-mapped to SDR.")
    }

    private static func dolbyVisionPlan(_ p: DolbyVisionProfile, s: DisplayHDRModes, profile7: Profile7Conversion) -> Plan {
        let dvDisplay = s.contains(.dolbyVision)
        switch p {
        case .p5:
            if dvDisplay { return Plan(output: "Dolby Vision", mode: .dolbyVision, path: .passthrough, note: nil) }
            return Plan(output: displayUnknownOutput, mode: nil, path: .unknown,
                        note: "Dolby Vision Profile 5 has no HDR10 layer, so colors can look wrong on a display without Dolby Vision.")
        case .p7FEL, .p7MEL:
            if profile7 == .available && dvDisplay {
                // FEL: the residual picture detail of the enhancement layer (12-bit reconstruction) cannot reach the
                // display; MEL carries no picture detail, so nothing visible is lost (docs/DOLBY_VISION.md).
                return Plan(output: "Dolby Vision (converted from Profile 7)", mode: .dolbyVision, path: .convertedProfile7,
                            note: p == .p7FEL
                                ? "Profile 7 is converted to Profile 8.1, so the extra picture detail in its full enhancement layer (FEL) is not shown and the 10-bit base layer plays with the Dolby Vision metadata."
                                : "Profile 7 is converted to Profile 8.1, and its minimal enhancement layer (MEL) holds no picture detail, so nothing is lost.")
            }
            var plan = signalPlan(.hdr10, label: "HDR10", s: s, suffix: " (base layer)", note: nil, path: .baseLayer)
            switch profile7 {
            case .notAvailableOnDevice:
                plan.note = sentence("Dolby Vision Profile 7 conversion is not available on this device, so the HDR10 base layer " +
                                     (plan.path == .toneMappedToSDR ? "is tone-mapped to SDR" : "plays"))
            case .failedForThisFile:
                plan.note = sentence("Dolby Vision Profile 7 conversion failed for this file, so the HDR10 base layer " +
                                     (plan.path == .toneMappedToSDR ? "is tone-mapped to SDR" : "plays"))
            case .available:
                plan.note = sentence("This display does not support Dolby Vision, so the HDR10 base layer " +
                                     (plan.path == .toneMappedToSDR ? "is tone-mapped to SDR" : "plays"))
            }
            return plan
        case .p8_1, .p8_2, .p8_4:
            if dvDisplay { return Plan(output: "Dolby Vision", mode: .dolbyVision, path: .passthrough, note: nil) }
            let (signal, label): (DisplayMode, String) = p == .p8_1 ? (.hdr10, "HDR10") : p == .p8_2 ? (.sdr, "SDR") : (.hlg, "HLG")
            if signal == .sdr {
                return Plan(output: "SDR (Dolby Vision base layer)", mode: .sdr, path: .baseLayer,
                            note: "This display does not support Dolby Vision, so the SDR base layer plays.")
            }
            var plan = signalPlan(signal, label: label, s: s, suffix: " (Dolby Vision base layer)", note: nil, path: .baseLayer)
            plan.note = sentence("This display does not support Dolby Vision, so the \(label) base layer " +
                                 (plan.path == .toneMappedToSDR ? "is tone-mapped to SDR" : "plays"))
            return plan
        }
    }

    // MARK: Fallback player

    private static func fallbackPlan(_ format: HDRFormat, display: DisplayState) -> Plan {
        let confirm: [String] = display.activeMode == nil ? [fallbackUnconfirmedClause] : []
        func unknownOr(_ mode: DisplayMode?) -> (String, DisplayMode?, VideoPath) {
            if let m = mode { return (m.displayName, m, mode == .sdr ? .sdr : .passthrough) }
            return (displayUnknownOutput, nil, .unknown)
        }
        switch format {
        case .sdr:
            return Plan(output: "SDR", mode: .sdr, path: .sdr, note: nil)
        case .hdr10, .hdr10Plus, .hlg:
            let (o, m, path) = unknownOr(nil)
            return Plan(output: o, mode: m, path: path,
                        note: confirm.isEmpty ? nil : sentence("The fallback player does not confirm which display mode is active"))
        case .dolbyVision(let p):
            switch p {
            case .p5:
                let (o, m, path) = unknownOr(nil)
                return Plan(output: o, mode: m, path: path,
                            note: sentence("Dolby Vision is unavailable in fallback mode, and Profile 5 has no HDR10 layer so colors can look wrong"))
            case .p8_2:
                return Plan(output: "SDR", mode: .sdr, path: .baseLayer,
                            note: sentence("Dolby Vision is unavailable in fallback mode, so the SDR base layer plays"))
            case .p7FEL, .p7MEL, .p8_1, .p8_4:
                let label = p == .p8_4 ? "HLG" : "HDR10"
                let (o, m, path) = unknownOr(nil)
                return Plan(output: o, mode: m, path: path == .unknown ? .unknown : .baseLayer,
                            note: sentence("Dolby Vision is unavailable in fallback mode, so the \(label) base layer plays", confirm))
            }
        }
    }
}
