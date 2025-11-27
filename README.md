# MusicPlayer (SwiftUI macOS)

SwiftUI macOS album-first player. Scans a local music folder, lets you browse by artist/album, and plays with a simple now-playing view and queue.

## Requirements
- macOS with Xcode installed.
- Audio files in a folder (MP3/FLAC/ALAC/etc.).
- Optional: Last.fm credentials (see below).

## Setup
1) Open `MusicPlayer/MusicPlayer.xcodeproj` in Xcode.  
2) Scheme: `MusicPlayer` targeting “My Mac”.  
3) Run (⌘R) to launch.

Last.fm (optional):
- Copy `MusicPlayer/LastFMSecrets.plist.example` to `MusicPlayer/LastFMSecrets.plist`.
- Fill in your API key/secret. The real file is `.gitignore`d.

## Building a standalone app
CLI (unsigned local build):
```bash
cd MusicPlayer
xcodebuild -scheme MusicPlayer -configuration Release -destination 'generic/platform=macOS' build
cp build/Build/Products/Release/MusicPlayer.app /Applications/
```
First launch will require “Right-click → Open” (or Privacy & Security → Open Anyway).

Xcode UI:
1) Open `MusicPlayer.xcodeproj`.  
2) Scheme: `MusicPlayer`; Destination: `Any Mac (Apple Silicon/Intel)`.  
3) Product → Archive.  
4) In the Organizer, select the archive → Distribute → Copy App, then save the `.app`.  
5) Copy the exported `MusicPlayer.app` to `/Applications` and open (use “Right-click → Open” on first launch).

## Features & notes
- Album browser sidebar with search; click an album to play.
- Now playing shows art, track metadata, scrubber, transport, volume, and an optional queue.
- Spacebar toggles play/pause when the app is focused and no text input has focus.
- Background gradient adapts to album art; text color auto-adjusts for contrast.
- Library path is persisted via security-scoped bookmarks; “Rescan (Clear Cache)” purges and rebuilds the library cache.
- Last.fm scrobble/now-playing support when linked.

## Hotkeys
- Spacebar: play/pause (only when app is active and you’re not typing).
