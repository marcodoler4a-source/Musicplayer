# MeloPlayer 1.1
Native SwiftUI offline music player for iOS 17+.

## Added in 1.1
- Import audio from the iOS Files picker
- Edit song title, artist, album, genre, year, lyrics and cover art
- Album artwork search (iTunes Search API) and Photos picker
- Lyrics search (LRCLIB), manual edit, save and floating lyrics card
- Favorites / Liked Songs
- Create/delete playlists and add/remove songs
- Sort library by date, title, artist or play count
- Persistent library and settings
- Shuffle and repeat off/all/one
- Playback speed, volume, seeking, skip/resume position
- Sleep timer
- Haptic and lyrics display settings
- Background audio, Lock Screen and Control Center commands
- Delete songs and reset settings/library

Open `MeloPlayer.xcodeproj` in Xcode 15+ and select your signing team. Imported files and app metadata are stored in the app Documents directory.

Note: online lyrics/artwork results depend on third-party catalog availability. Review results before saving. Crossfade is stored as a preference for a future queue engine; AVAudioPlayer's current single-player implementation does not perform true overlapping crossfade.
