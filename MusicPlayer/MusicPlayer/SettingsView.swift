import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var viewModel: AppViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            librarySection
           
            lastFMSection
            Spacer()
        }
        .padding(24)
        .frame(maxWidth: 520, minHeight: 260)   // <- keep it prefs-sized
    }

    // MARK: - Library

    private var librarySection: some View {
        VStack(alignment: .leading) {
            HStack(alignment: .firstTextBaseline, spacing: 16) {
                Text("Location")
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    Text(viewModel.libraryPath ?? "Not set")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)           // <- don't let this drive width

                    Button("Change…") {
                        viewModel.pickAlbumFolder()
                    }
                    .controlSize(.small)
                }
            }

            HStack(spacing: 8) {
                Button("Rescan") {
                    viewModel.rescanLibrary()
                }

                Button("Rescan & Clear Cache") {
                    viewModel.rescanLibraryClearingCache()
                }
            }
            .controlSize(.small)
            .buttonStyle(.bordered)
        }
    }

    // MARK: - Last.fm

    private var lastFMSection: some View {
        VStack(alignment: .leading) {
            
            VStack(alignment: .leading, spacing: 4) {
                if let username = viewModel.lastFMUsername {
                    Text("Linked as \(username)")
                        .font(.headline.weight(.semibold))
                } else {
                    Text("Not linked")
                        .font(.headline.weight(.semibold))
                }

                Text(viewModel.lastFMStatus)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 8) {
                Button("Link") {
                    viewModel.startLastFMAuth()
                }
                .disabled(viewModel.lastFMUsername != nil)

                Button("Complete Linking") {
                    viewModel.completeLastFMAuth()
                }

                Spacer()

                Button("Unlink", role: .destructive) {
                    viewModel.unlinkLastFM()
                }
            }
            .controlSize(.small)
            .buttonStyle(.bordered)
        }
    }
}
