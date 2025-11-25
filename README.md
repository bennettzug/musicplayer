# MusicPlayer (SwiftUI macOS)

SwiftUI macOS album-first player scaffold.

## Running
- CLI: `swift run MusicPlayer` (debug) or `swift build -c release && .build/release/MusicPlayer`.
- In Xcode: open `Package.swift`, select the `MusicPlayer` scheme, and Run.

## Building a standalone `.app`
- SwiftPM bundle: `make app` (creates `dist/MusicPlayer.app`; launch with `open dist/MusicPlayer.app`). Uses `Resources/Info.plist` and the release binary.
- Xcode archive (for signing/notarization):
  1) Open `Package.swift` in Xcode.
  2) Scheme: `MusicPlayer`; target: your Mac.
  3) Add `MusicPlayer.entitlements` in Signing & Capabilities; enable App Sandbox and User Selected File (Read/Write).
  4) Product → Archive, then export the `.app` from Organizer.

## Notes
- Library folder choice is persisted via security-scoped bookmarks.
- Album art colors drive the background gradient.
- Library drawer: artists → albums per artist; main view: large art, track-first typography, optional queue.***
