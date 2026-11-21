import Foundation
import Observation
import AVFoundation
import PlaybackStatus

/// What the Playback Stats tab of the info panel shows right now (R340; an overlay over the picture before): the table rows
/// and the honest audio and video status lines. Updated once a second while the tab is on screen.
@MainActor
@Observable
final class StatsOverlayModel {
    private(set) var isVisible = false
    /// Called when the tab comes on screen, so it never shows old values.
    @ObservationIgnored var onShown: () -> Void = {}

    func setShown(_ shown: Bool) {
        isVisible = shown
        if shown { onShown() }
    }
    /// Plain sentences about tracks that were left out and other limits of this file (from the converting player). Shown under the status.
    var notes: [String] = []
    private(set) var rows: [StatRow] = []
    private(set) var statusLines: [String] = []

    func update(from probe: PlaybackProbe, player: AVPlayer) {
        let snapshot = probe.snapshot(player: player)
        let status = probe.status(for: snapshot)
        rows = StatsOverlay.rows(snapshot, status: status)
        statusLines = (status.map(StatsOverlay.statusLines) ?? []) + notes
    }
}
