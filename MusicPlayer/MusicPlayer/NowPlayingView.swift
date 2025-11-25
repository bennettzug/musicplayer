import SwiftUI

struct NowPlayingView: View {
    @EnvironmentObject private var viewModel: AppViewModel
    let album: Album

    private var currentTrack: Track? {
        album.tracks[safe: viewModel.currentTrackIndex]
    }

    var body: some View {
        VStack(spacing: 32) {
            Spacer(minLength: 32)

            // Artwork
            AlbumCoverView(image: album.coverImage)
                .frame(width: 420, height: 420)
                .shadow(color: .black.opacity(0.35), radius: 28, x: 0, y: 18)

            // Title / album / artist
            metadataSection
                .frame(maxWidth: 420)

            // Scrubber + transport + volume grouped like Apple Music
            VStack(spacing: 28) {
                ScrubberView(
                    position: $viewModel.playbackPosition,
                    duration: viewModel.duration
                ) { time in
                    viewModel.seek(to: time)
                }
                .frame(maxWidth: 420)

                TransportControlsView(
                    isPlaying: viewModel.isPlaying,
                    volume: viewModel.volume,
                    isQueueVisible: viewModel.isQueueVisible,
                    onPlayPause: { viewModel.togglePlayback() },
                    onNext: { viewModel.playNext() },
                    onPrevious: { viewModel.playPrevious() },
                    onVolumeChange: { viewModel.setVolume($0) },
                    onToggleQueue: { viewModel.toggleQueueVisibility() }
                )
                .frame(maxWidth: 420)
            }

            // Queue list
            if viewModel.isQueueVisible {
                UpcomingListView(
                    album: album,
                    currentIndex: viewModel.currentTrackIndex
                ) { index in
                    viewModel.play(album: album, trackIndex: index)
                }
                .frame(maxWidth: 420)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            Spacer(minLength: 40)
        }
        .padding(.horizontal, 80)
        .foregroundColor(.white)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Metadata

    private var metadataSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let track = currentTrack {
                Text(track.title)
                    .font(.system(size: 26, weight: .semibold))
                    .lineLimit(2)
            }

            Text(album.artist)
                .font(.system(size: 17, weight: .regular))
                .foregroundColor(.secondary)
                .lineLimit(1)

            Text(album.year.isEmpty ? album.title : "\(album.title) • \(album.year)")
                .font(.caption)
                .foregroundColor(.secondary.opacity(0.9))
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Artwork

struct AlbumCoverView: View {
    let image: Image

    var body: some View {
        image
            .resizable()
            .aspectRatio(1, contentMode: .fill)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

// MARK: - Scrubber

struct ScrubberView: View {
    @Binding var position: TimeInterval
    let duration: TimeInterval
    var onSeek: (TimeInterval) -> Void

    private func timeString(_ time: TimeInterval) -> String {
        let totalSeconds = max(Int(time), 0)
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    var body: some View {
        VStack(spacing: 8) {
            Slider(
                value: Binding(
                    get: { position },
                    set: { newValue in
                        position = newValue
                        onSeek(newValue)
                    }
                ),
                in: 0...max(duration, 1)
            )
            .tint(.white)
            .sliderThumbVisibility(.hidden)

            HStack {
                Text(timeString(position))
                Spacer()
                Text(timeString(duration))
            }
            .font(.caption)
            .foregroundColor(.secondary)
        }
    }
}

// MARK: - Transport / volume / queue

struct TransportControlsView: View {
    let isPlaying: Bool
    let volume: Double
    let isQueueVisible: Bool

    var onPlayPause: () -> Void
    var onNext: () -> Void
    var onPrevious: () -> Void
    var onVolumeChange: (Double) -> Void
    var onToggleQueue: () -> Void

    var body: some View {
        VStack(spacing: 28) {
            // Main playback controls
            HStack(spacing: 64) {
                Button(action: onPrevious) {
                    Image(systemName: "backward.fill")
                        .font(.system(size: 22, weight: .semibold))
                }
                .buttonStyle(.plain)

                Button(action: onPlayPause) {
                        Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 30, weight: .semibold))
                }
                .buttonStyle(.plain)

                Button(action: onNext) {
                    Image(systemName: "forward.fill")
                        .font(.system(size: 22, weight: .semibold))
                }
                .buttonStyle(.plain)
            }

            // Volume slider (long, bottom-aligned) + queue button on the right
            HStack(spacing: 20) {
                HStack(spacing: 12) {
                    Image(systemName: "speaker.fill")
                    Slider(
                        value: Binding(
                            get: { volume },
                            set: { newValue in onVolumeChange(newValue) }
                        ),
                        in: 0...1
                    ).tint(.white)
                    Image(systemName: "speaker.wave.3.fill")
                }

                Button(action: onToggleQueue) {
                    HStack(spacing: 6) {
                        Image(systemName: "list.bullet")
                        Text(isQueueVisible ? "Hide Queue" : "Show Queue")
                            .font(.subheadline)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background(Color.white.opacity(isQueueVisible ? 0.2 : 0.12))
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
            .font(.caption)
            .foregroundColor(.secondary)
        }
        .foregroundColor(.white)
    }
}

// MARK: - Queue

struct UpcomingListView: View {
    let album: Album
    let currentIndex: Int
    var onSelect: (Int) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Up Next")
                .font(.headline)

            ForEach(Array(album.tracks.enumerated()), id: \.offset) { index, track in
                Button {
                    onSelect(index)
                } label: {
                    HStack {
                        
                            Text(track.title)
                                .font(.subheadline.weight(.medium))
                                .lineLimit(1)

                            
                        
                        Spacer()
                        if index == currentIndex {
                            Image(systemName: "waveform")
                                .symbolEffect(.breathe, options: .repeat(.continuous))
                                .foregroundColor(.white)
                        } else {
                            Text(formattedDuration(track.duration))
                                .foregroundColor(.secondary)
                                .font(.caption)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(index == currentIndex ? Color.white.opacity(0.14) : Color.white.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func formattedDuration(_ duration: TimeInterval) -> String {
        let totalSeconds = max(Int(duration), 0)
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}
