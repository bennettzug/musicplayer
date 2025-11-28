import SwiftUI

struct AlbumBrowserSidebar: View {
    @EnvironmentObject private var viewModel: AppViewModel

    var body: some View {
        List {
            Section("Library") {
                ForEach(viewModel.filteredArtists(), id: \.self) { artist in
                    let binding = Binding<Bool>(
                        get: { viewModel.isArtistExpanded(artist) },
                        set: { viewModel.setArtistExpanded(artist, $0) }
                    )

                    DisclosureGroup(isExpanded: binding) {
                        VStack(spacing: 4) {
                            ForEach(viewModel.albumsForArtistFiltered(artist)) { album in
                                AlbumRow(album: album, isActive: album.id == viewModel.currentAlbum?.id)
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        viewModel.play(album: album, trackIndex: 0)
                                    }
                            }
                        }
                        .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .top)))
                    } label: {
                        HStack {
                            Text(artist)
                                .font(.headline.weight(.semibold))
                            Spacer()
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                                viewModel.setArtistExpanded(artist, !viewModel.isArtistExpanded(artist))
                            }
                        }
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .searchable(text: $viewModel.searchText, placement: .sidebar, prompt: Text("Search library"))
    }
}

private struct AlbumRow: View {
    let album: Album
    let isActive: Bool

    var body: some View {
        HStack(spacing: 12) {
            album.coverImage
                .resizable()
                .aspectRatio(1, contentMode: .fill)
                .frame(width: 32, height: 32)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(album.title)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                Text("\(album.year)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
            if isActive {
                Image(systemName: "waveform")
                    .foregroundColor(.accentColor)
            }
        }
        .padding(.vertical, 4)
    }
}
