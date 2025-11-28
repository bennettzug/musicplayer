import Foundation
import MediaPlayer
import AppKit

@MainActor
final class NowPlayingController {
    private let infoCenter = MPNowPlayingInfoCenter.default()

    func configureRemoteCommands(
        play: @escaping () -> Void,
        pause: @escaping () -> Void,
        toggle: @escaping () -> Void,
        next: @escaping () -> Void,
        previous: @escaping () -> Void,
        seek: @escaping (TimeInterval) -> Void
    ) {
        let commands = MPRemoteCommandCenter.shared()

        // Clear any existing handlers so we do not stack duplicates on relaunch.
        commands.playCommand.removeTarget(nil)
        commands.pauseCommand.removeTarget(nil)
        commands.togglePlayPauseCommand.removeTarget(nil)
        commands.nextTrackCommand.removeTarget(nil)
        commands.previousTrackCommand.removeTarget(nil)
        commands.changePlaybackPositionCommand.removeTarget(nil)

        commands.playCommand.isEnabled = true
        commands.pauseCommand.isEnabled = true
        commands.togglePlayPauseCommand.isEnabled = true
        commands.nextTrackCommand.isEnabled = true
        commands.previousTrackCommand.isEnabled = true
        commands.changePlaybackPositionCommand.isEnabled = true

        commands.playCommand.addTarget { _ in
            play()
            return .success
        }
        commands.pauseCommand.addTarget { _ in
            pause()
            return .success
        }
        commands.togglePlayPauseCommand.addTarget { _ in
            toggle()
            return .success
        }
        commands.nextTrackCommand.addTarget { _ in
            next()
            return .success
        }
        commands.previousTrackCommand.addTarget { _ in
            previous()
            return .success
        }
        commands.changePlaybackPositionCommand.addTarget { event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            seek(event.positionTime)
            return .success
        }
    }

    func updateMetadata(track: Track, album: Album, elapsed: TimeInterval, duration: TimeInterval, isPlaying: Bool) {
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: track.title,
            MPMediaItemPropertyArtist: track.artist,
            MPMediaItemPropertyAlbumTitle: album.title,
            MPMediaItemPropertyPlaybackDuration: duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: elapsed,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0
        ]

        if let artwork = artwork(from: album.coverData) {
            info[MPMediaItemPropertyArtwork] = artwork
        }

        infoCenter.nowPlayingInfo = info
        infoCenter.playbackState = isPlaying ? .playing : .paused
    }

    func updateProgress(elapsed: TimeInterval, duration: TimeInterval, isPlaying: Bool) {
        guard var info = infoCenter.nowPlayingInfo else { return }
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = elapsed
        info[MPMediaItemPropertyPlaybackDuration] = duration
        info[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? 1.0 : 0.0
        infoCenter.nowPlayingInfo = info
        infoCenter.playbackState = isPlaying ? .playing : .paused
    }

    func updatePlaybackState(isPlaying: Bool, elapsed: TimeInterval? = nil, duration: TimeInterval? = nil) {
        guard var info = infoCenter.nowPlayingInfo else { return }
        if let elapsed {
            info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = elapsed
        }
        if let duration {
            info[MPMediaItemPropertyPlaybackDuration] = duration
        }
        info[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? 1.0 : 0.0
        infoCenter.nowPlayingInfo = info
        infoCenter.playbackState = isPlaying ? .playing : .paused
    }

    func clear() {
        infoCenter.nowPlayingInfo = nil
        infoCenter.playbackState = .stopped
    }

    private func artwork(from data: Data?) -> MPMediaItemArtwork? {
        guard let data, let image = NSImage(data: data) else { return nil }
        return MPMediaItemArtwork(boundsSize: image.size) { _ in image }
    }
}
