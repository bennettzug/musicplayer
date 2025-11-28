import Foundation
import AVFoundation
import CoreAudio

final class PlayerController {
    private var player: AVPlayer?
    private var cachedDuration: TimeInterval?
    private var endObserver: Any?
    var onTrackEnd: (() -> Void)?
    private var removeDeviceListener: (() -> Void)?
    var onExternalPause: (() -> Void)?

    init() {
        addOutputDeviceListener()
    }

    func play(track: Track, volume: Double) {
        removeEndObserver()
        player = AVPlayer(url: track.url)
        player?.volume = Float(volume)
        player?.play()
        cachedDuration = nil
        addEndObserver()
    }

    func pause() {
        player?.pause()
    }

    func resume() {
        player?.play()
    }

    func seek(to time: TimeInterval) {
        let cm = CMTime(seconds: time, preferredTimescale: 600)
        player?.seek(to: cm)
    }

    func setVolume(_ volume: Double) {
        player?.volume = Float(volume)
    }

    func currentTime() -> TimeInterval {
        player?.currentTime().seconds ?? 0
    }

    /// Asynchronously loads the current item's duration using the modern load API.
    @MainActor
    func loadCurrentDuration() async -> TimeInterval {
        guard let item = player?.currentItem else { return 0 }
        do {
            let duration = try await item.asset.load(.duration)
            let seconds = duration.seconds.isFinite ? duration.seconds : 0
            cachedDuration = seconds
            return seconds
        } catch {
            return cachedDuration ?? 0
        }
    }

    /// Returns a cached duration if available; otherwise 0. Call `await loadCurrentDuration()` to refresh.
    func currentDuration() -> TimeInterval {
        cachedDuration ?? 0
    }

    var hasCurrentItem: Bool {
        player?.currentItem != nil
    }

    private func addEndObserver() {
        guard let item = player?.currentItem else { return }
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            self?.onTrackEnd?()
        }
    }

    private func removeEndObserver() {
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
            self.endObserver = nil
        }
    }

    private func addOutputDeviceListener() {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let status = AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            DispatchQueue.main
        ) { [weak self] _, _ in
            self?.pause()
            self?.onExternalPause?()
        }
        if status == noErr {
            removeDeviceListener = { [weak self] in
                var addr = address
                AudioObjectRemovePropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &addr, DispatchQueue.main, { _, _ in })
                self?.removeDeviceListener = nil
            }
        }
    }

    deinit {
        removeEndObserver()
        removeDeviceListener?()
    }
}
