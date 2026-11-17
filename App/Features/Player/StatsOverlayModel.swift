import Foundation
import Observation
import AVFoundation
import PlaybackStatus

/// What the Playback Stats overlay shows right now: the table rows and the honest audio and video status lines.
@MainActor
@Observable
final class StatsOverlayModel {
    var isVisible = false
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
