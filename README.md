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

## V12 update
- Online music-info search results now show album cover artwork from Cover Art Archive when available.
- Applying a result uses both metadata and the selected result's cover artwork.
- Now Playing has a dedicated Music Info button directly beside Search Lyrics.

## V13 additions
- Add/replace album cover art manually from the iPhone Photos library using the photo+ button beside Music Info on Now Playing.
- Broader music-info search combines MusicBrainz and Apple's public search catalog, with cover art from Cover Art Archive or catalog artwork when available.
- Broader synced-lyrics matching tries exact title/artist, combined keyword search, and cleaned title-only fallback through LRCLIB.

## V15
- Fixed the Now Playing favorite heart so it is an actual button and reflects favorite state.
- Tapping the large album cover now opens album/music actions, including online Music Info + Cover Art search and Favorites.
- Manual iPhone Photos cover selection remains available from the photo-plus button.
- MusicBrainz results now attempt Cover Art Archive front-cover thumbnails directly; Apple catalog results retain high-resolution artwork fallback.

## V16 broader search
- Music info now searches MusicBrainz broadly and literally, plus Apple music catalog storefronts for US, Philippines, Japan, and UK, then merges/deduplicates results.
- Music info requests more results and prefers higher-resolution catalog artwork when available.
- Synced lyrics now tries exact title/artist/album, primary artist, broad title+artist, title without feat./ft., title+album, and title-only searches.
- Lyrics results are ranked using title, artist, album, and current audio duration.

## V17 Now Playing simplification
- Now Playing utility actions are reduced to exactly two buttons: Search Lyrics and Music Info.
- Removed the separate photo/upload artwork button from the Now Playing action row.
- Tapping the large album artwork now opens Music Info search directly.
