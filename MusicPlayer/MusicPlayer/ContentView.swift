import SwiftUI
import AppKit

struct ContentView: View {
    @EnvironmentObject private var viewModel: AppViewModel
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var windowDelegate = FullscreenHidingWindowDelegate()

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            AlbumBrowserSidebar()
                .environmentObject(viewModel)
                .navigationSplitViewColumnWidth(min: 320, ideal: 420, max: 560)
        } detail: {
            ZStack {
                BackgroundView(color: viewModel.backgroundColor)
                ScrollView {
                    VStack {
                        if let album = viewModel.currentAlbum {
                            NowPlayingView(album: album)
                                .environmentObject(viewModel)
                                .padding(.horizontal, 60)
                                .padding(.vertical, 40)
                        } else {
                            Text("Select an album to start")
                                .font(.title)
                                .foregroundColor(.secondary)
                                .padding(.vertical, 120)
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(WindowAccessor { window in
            window?.delegate = windowDelegate
        })
        .toolbar(removing: .sidebarToggle)
    }

    private func toggleSidebar() {
        withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
            columnVisibility = (columnVisibility == .all) ? .detailOnly : .all
        }
    }
}

private struct BackgroundView: View {
    let color: Color

    var body: some View {
        let palette = derivedPalette(from: color)

        ZStack {
            LinearGradient(
                colors: [palette.light, palette.dark],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            RadialGradient(
                colors: [palette.accent.opacity(0.55), Color.clear],
                center: .center,
                startRadius: 60,
                endRadius: 520
            )
            .blendMode(.screen)
            .ignoresSafeArea()

            LinearGradient(
                colors: [palette.accent.opacity(0.2), Color.clear],
                startPoint: .bottomLeading,
                endPoint: .topTrailing
            )
            .ignoresSafeArea()
        }
    }

    private func derivedPalette(from base: Color) -> (light: Color, dark: Color, accent: Color) {
        let ns = NSColor(base)
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        ns.usingColorSpace(.deviceRGB)?.getHue(&h, saturation: &s, brightness: &b, alpha: &a)

        let boostedS = max(s, min(1.0, s * 1.1 + 0.1))

        let light = NSColor(hue: h, saturation: min(boostedS * 0.9, 1.0), brightness: min(b * 1.05 + 0.05, 1.0), alpha: a)
        let dark = NSColor(hue: h, saturation: min(boostedS * 1.1, 1.0), brightness: max(b * 0.55, 0.15), alpha: a)
        let accent = NSColor(hue: h, saturation: min(boostedS * 1.05, 1.0), brightness: min(b * 1.1, 1.0), alpha: a)

        return (Color(light), Color(dark), Color(accent))
    }
}

#Preview {
    ContentView()
        .environmentObject(AppViewModel())
}

private struct WindowAccessor: NSViewRepresentable {
    var configure: (NSWindow?) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { configure(view.window) }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async { configure(nsView.window) }
    }
}

private final class FullscreenHidingWindowDelegate: NSObject, NSWindowDelegate {
    func window(_ window: NSWindow, willUseFullScreenPresentationOptions proposedOptions: NSApplication.PresentationOptions = []) -> NSApplication.PresentationOptions {
        [.autoHideToolbar, .autoHideMenuBar, .fullScreen]
    }
}
