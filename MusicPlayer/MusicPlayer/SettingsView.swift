import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var viewModel: AppViewModel

    var body: some View {
        Form {
            Section(header: Text("Library")) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Library Location")
                            .font(.headline.weight(.semibold))
                        Text(viewModel.libraryPath ?? "Not set")
                            .foregroundColor(.secondary)
                            .lineLimit(2)
                    }
                    Spacer()
                    Button("Change…") {
                        viewModel.pickAlbumFolder()
                    }
                    Button("Rescan") {
                        viewModel.rescanLibrary()
                    }
                    Button("Rescan (Clear Cache)") {
                        viewModel.rescanLibraryClearingCache()
                    }
                    
                }
            }

            Section(header: Text("Last.fm")) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(viewModel.lastFMUsername != nil ? "Linked as \(viewModel.lastFMUsername!)" : "Not linked")
                        .font(.headline.weight(.semibold))
                    Text(viewModel.lastFMStatus)
                        .foregroundColor(.secondary)
                        .font(.subheadline)
                }

                HStack {
                    Button("Link Last.fm") {
                        viewModel.startLastFMAuth()
                    }
                    

                    Button("Complete Linking") {
                        viewModel.completeLastFMAuth()
                    }

                    Button("Unlink") {
                        viewModel.unlinkLastFM()
                    }
                    .foregroundColor(.red)
                }
            }
        }
        .padding()
        .frame(minWidth: 420, minHeight: 160)
    }
}
