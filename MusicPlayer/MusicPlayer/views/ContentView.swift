import SwiftUI
import AppKit

struct ContentView: View {
    @EnvironmentObject private var viewModel: AppViewModel
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var windowDelegate = FullscreenHidingWindowDelegate()
    @State private var spacebarHandler: SpacebarToggleManager?

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            AlbumBrowserSidebar()
                .environmentObject(viewModel)
                .navigationSplitViewColumnWidth(min: 320, ideal: 420, max: 560)
                .scrollEdgeEffectStyle(.soft, for:.top)
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
        .onAppear {
            spacebarHandler = SpacebarToggleManager {
                viewModel.togglePlayback()
            }
            spacebarHandler?.start()
        }
        .onDisappear {
            spacebarHandler?.stop()
        }
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
                colors: [palette.accent.opacity(0.28), Color.black.opacity(0.18)],
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

        let boostedS = max(s, min(1.0, s * 1.15 + 0.1))

        let light = NSColor(
            hue: h,
            saturation: min(boostedS * 0.85, 1.0),
            brightness: min(b * 1.12 + 0.12, 1.0),
            alpha: a
        )
        let dark = NSColor(
            hue: h,
            saturation: min(boostedS * 1.2, 1.0),
            brightness: max(b * 0.42, 0.12),
            alpha: a
        )
        let accent = NSColor(
            hue: h,
            saturation: min(boostedS * 1.08, 1.0),
            brightness: min(b * 1.08, 1.0),
            alpha: a
        )

        return (Color(light), Color(dark), Color(accent))
    }
}

#Preview {
    let viewModel = AppViewModel()
    return ContentView()
        .environmentObject(viewModel)
        .environmentObject(viewModel.playback)
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

/// Global spacebar listener that toggles play/pause when appropriate.
private final class SpacebarToggleManager {
    private var monitor: Any?
    private let onToggle: () -> Void

    init(onToggle: @escaping () -> Void) {
        self.onToggle = onToggle
    }

    func start() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }

            // Only respond to plain space (no control/command/option).
            let disallowed = event.modifierFlags.intersection([.command, .option, .control])
            guard disallowed.isEmpty else { return event }
            guard event.charactersIgnoringModifiers == " " else { return event }

            // Avoid hijacking when typing (search field or any text input).
            if let responder = NSApp.keyWindow?.firstResponder {
                if responder is NSTextView ||
                    responder is NSTextField ||
                    responder is NSTextInputClient ||
                    responder is NSControl {
                    return event
                }
            }

            onToggle()
            return nil
        }
    }

    func stop() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
    }
}
