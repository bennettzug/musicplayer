//
//  MusicPlayerApp.swift
//  MusicPlayer
//
//  Created by Bennett Zug on 11/24/25.
//

import SwiftUI

@main
struct MusicPlayerApp: App {
    @StateObject private var viewModel = AppViewModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(viewModel)
                .environmentObject(viewModel.playback)
                .windowToolbarFullScreenVisibility(.onHover)
                .presentedWindowToolbarStyle(.unified)
        }
        
        Settings {
            SettingsView()
                .environmentObject(viewModel)
                .environmentObject(viewModel.playback)
        }
    }
}
