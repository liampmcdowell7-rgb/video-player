import SwiftUI
import AVKit
import AppLogic

/// R471 (24): a card on a title's Trailers or Bonus Content shelf, to play.
struct ExtraPlayRequest: Identifiable, Hashable {
    let itemID: Int64
    let extraID: Int64
    var id: Int64 { extraID }
}

/// R471 (24): plays a trailer or bonus video in the system player, from its start. It keeps no position and no watch
/// state, offers no Up Next and tells no server it was watched (`AppServices.resolveExtra`). Menu closes it.
/// PROVISIONAL (OPEN_QUESTIONS R471 (24)); NOT COMPILED for tvOS.
struct ExtraPlayerScreen: View {
    let request: ExtraPlayRequest
    @Environment(AppServices.self) private var services
    @Environment(\.dismiss) private var dismiss
    @State private var phase: Phase = .loading
    /// Set when the screen went away; a file that opens after that is closed again.
    @State private var closed = false

    enum Phase {
        case loading
        case ready(AVPlayer, ResolvedExtra)
        case failed(PlaybackFailure)
    }

    var body: some View {
        content
            .alert(failure?.alertTitle ?? PlaybackFailure.title, isPresented: Binding(get: { failure != nil }, set: { _ in }),
                   presenting: failure) { _ in
                Button("Done", role: .cancel) { dismiss() }
            } message: { failure in
                Text(failure.text)
            }
            .onDisappear {
                closed = true
                if case .ready(let player, let resolved) = phase {
                    // The player is stopped first, then the converting player (`RemuxPlayback.stop`).
                    player.pause()
                    player.replaceCurrentItem(with: nil)
                    resolved.remux?.stop()
                }
            }
    }

    @ViewBuilder private var content: some View {
        switch phase {
        case .loading:
            LoadingView()
                .task(id: request.id) { await resolve() }
        case .ready(let player, _):
            ExtraPlayerHost(player: player)
                // design-lint:allow the system player draws its own safe areas; the video fills the whole screen
                .ignoresSafeArea()
        case .failed:
            // The alert above says why.
            Color.clear
        }
    }

    private var failure: PlaybackFailure? {
        if case .failed(let failure) = phase { return failure }
        return nil
    }

    private func resolve() async {
        do {
            let resolved = try await services.resolveExtra(itemID: request.itemID, extraID: request.extraID)
            if Task.isCancelled || closed {
                resolved.remux?.stop()
                return
            }
            let options: [String: Any]? = resolved.headers.isEmpty ? nil : ["AVURLAssetHTTPHeaderFieldsKey": resolved.headers]
            let item = AVPlayerItem(asset: AVURLAsset(url: resolved.url, options: options))
            let title = AVMutableMetadataItem()
            title.identifier = .commonIdentifierTitle
            title.value = resolved.title as NSString
            title.extendedLanguageTag = "und"
            item.externalMetadata = [title]
            phase = .ready(AVPlayer(playerItem: item), resolved)
        } catch {
            phase = .failed(PlaybackFailureMapper.failure(for: error))
        }
    }
}

/// The system player for an extra, started at once.
private struct ExtraPlayerHost: UIViewControllerRepresentable {
    let player: AVPlayer

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.player = player
        player.play()
        return controller
    }

    func updateUIViewController(_ controller: AVPlayerViewController, context: Context) {}
}
