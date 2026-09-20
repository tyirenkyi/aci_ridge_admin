//
//  ReviewAudioPlayer.swift
//  ACI Admin
//
//  Playback for the review screen. One player, one track at a time: picking a
//  different recording — or flipping the same one between the translation and the
//  English original — replaces what's loaded rather than stacking players up.
//

import AVFoundation
import Observation

@Observable
@MainActor
final class ReviewAudioPlayer {
    private(set) var isPlaying = false
    private(set) var position: Double = 0
    private(set) var duration: Double = 0
    /// Set when the item fails to load, so the panel can say so instead of
    /// leaving a dead play button.
    private(set) var failed = false

    /// What is loaded right now: a track key plus which side of it.
    private(set) var trackKey: String?
    private(set) var usingSource = false

    private var player: AVPlayer?
    private var timeObserver: Any?
    private var statusObservation: NSKeyValueObservation?
    private var endObserver: (any NSObjectProtocol)?

    var fraction: Double { duration > 0 ? min(1, max(0, position / duration)) : 0 }
    var isReady: Bool { duration > 0 }

    func load(_ url: URL?, trackKey: String, usingSource: Bool) {
        guard self.trackKey != trackKey || self.usingSource != usingSource else { return }
        self.trackKey = trackKey
        self.usingSource = usingSource
        reset()
        guard let url else {
            failed = true
            return
        }
        // Under UI testing nothing may touch the network: an AVPlayer resolving a
        // host keeps the app from ever reporting itself idle, and XCUITest waits
        // for idle before every interaction. Report a plausible length instead so
        // the panel still lays out.
        guard !APIConfig.isUITesting else {
            duration = 252
            return
        }
        start(url)
    }

    func toggle() {
        guard let player, isReady else { return }
        if isPlaying {
            player.pause()
            isPlaying = false
        } else {
            if position >= duration { seek(to: 0) }
            player.play()
            isPlaying = true
        }
    }

    func seek(fraction: Double) {
        seek(to: duration * min(1, max(0, fraction)))
    }

    func stop() {
        player?.pause()
        isPlaying = false
    }

    /// Called when the panel goes away. The observers are registered against the
    /// player and the notification centre, neither of which a deinit on a
    /// main-actor type is allowed to reach, so teardown is explicit.
    func tearDown() {
        reset()
        trackKey = nil
    }

    // MARK: Internals

    private func seek(to seconds: Double) {
        position = seconds
        player?.seek(to: CMTime(seconds: seconds, preferredTimescale: 600),
                     toleranceBefore: .zero, toleranceAfter: .zero)
    }

    private func start(_ url: URL) {
        let item = AVPlayerItem(url: url)
        let player = AVPlayer(playerItem: item)
        self.player = player

        // `duration` is unknown until the item loads, and a live-streamed or
        // failed item never reports one — which is why the transport stays
        // disabled on `isReady` rather than assuming a length.
        statusObservation = item.observe(\.status, options: [.initial, .new]) { [weak self] item, _ in
            Task { @MainActor in
                guard let self else { return }
                switch item.status {
                case .readyToPlay:
                    let seconds = item.duration.seconds
                    self.duration = seconds.isFinite && seconds > 0 ? seconds : 0
                case .failed:
                    self.failed = true
                default:
                    break
                }
            }
        }

        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.25, preferredTimescale: 600), queue: .main
        ) { [weak self] time in
            MainActor.assumeIsolated { self?.position = time.seconds }
        }

        endObserver = NotificationCenter.default.addObserver(
            forName: AVPlayerItem.didPlayToEndTimeNotification, object: item, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.isPlaying = false
                self.position = self.duration
            }
        }
    }

    private func reset() {
        if let timeObserver { player?.removeTimeObserver(timeObserver) }
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        timeObserver = nil
        endObserver = nil
        statusObservation = nil
        player?.pause()
        player = nil
        isPlaying = false
        position = 0
        duration = 0
        failed = false
    }
}
