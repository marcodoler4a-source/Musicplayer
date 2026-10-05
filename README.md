# MeloGlass
Native SwiftUI local music player for iPhone.

## Features
- Local audio import via Files
- Metadata + embedded cover artwork
- Glass UI and full Now Playing screen
- Mirrored/blurred cover artwork background
- Play/pause, previous/next, seeking, shuffle, repeat-one/all, speed, sleep timer
- Background audio, Lock Screen/Control Center metadata and remote controls
- Standard timestamped `.lrc` parsing and synced lyric scrolling
- Lyrics search shortcut (LRCLIB) and music-info search shortcut (MusicBrainz)

## Build on GitHub
This repository includes a GitHub Actions workflow. Push to GitHub, open **Actions > Build IPA > Run workflow**, then download the `MeloGlass-IPA` artifact.

## SideStore
Extract the artifact to get `MeloGlass.ipa`, then import that IPA into SideStore. SideStore signs it with your Apple Account during sideloading/refresh.

## Note about online search
The initial version opens LRCLIB/MusicBrainz searches from inside the app. This avoids hard-coding an unofficial lyrics scraping service. Local LRC playback is fully native.


## App icon
The project includes the blue glass music-note icon in `MeloGlass/Assets.xcassets/AppIcon.appiconset`. Xcode/GitHub Actions uses it as the installed iPhone app icon.

## V11 online music info
Use the ••• menu beside any library song and choose **Search Music Info Online**. MeloGlass searches MusicBrainz for title, artist, album, release date, genre, and track number, then can apply the selected result and fetch cover artwork from the Cover Art Archive.
