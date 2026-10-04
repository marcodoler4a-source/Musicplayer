# Melo Player PWA

An installable, offline-first personal music player for iPhone/iPad and modern browsers.

## iPhone installation
1. Host this folder over HTTPS (GitHub Pages is fine).
2. Open the hosted site in **Safari** on iPhone.
3. Tap **Share** → **Add to Home Screen** → **Add**.
4. Open **Melo** from the Home Screen.
5. Go to **Library → Import Music** and select audio files from the iPhone Files app.

Music, edited metadata, lyrics, artwork, favorites, playlists and settings are stored locally in the browser using IndexedDB.

## Features
- Local audio import and offline storage
- Home, Search, Library and Settings
- Mini player and full Now Playing screen
- Play/pause, previous/next, seeking, shuffle, repeat and speed
- Favorites, play counts and playlists
- Edit title, artist, album, genre and year
- Lyrics search via LRCLIB plus manual editing/saving
- Album-art search via the iTunes Search API plus local image selection
- Saved lyrics and cover art
- Media Session / Lock Screen controls where iOS Safari supports them
- Sleep timer, volume, accent and playback preferences
- PWA manifest and offline app-shell service worker

## Important iOS/PWA limitation
A PWA is not identical to a native SwiftUI app. iOS controls background browser execution, so long-running background playback and sleep timers may be less reliable after iOS suspends the web app. Imported music remains inside Safari/PWA website storage and can be cleared if the user removes website data.

## GitHub Pages
Upload the contents of this folder to a GitHub repository. In the repository settings, enable **Pages** from the main branch/root folder. Open the generated HTTPS Pages address in Safari and add it to the Home Screen.

## v3.1 iPhone performance/audio fix
- Music files are written to IndexedDB only when imported. Lyrics, artwork, play count and position now save as lightweight metadata instead of rewriting the entire MP3 blob.
- LRC is parsed only when it changes; lyric highlighting updates only when the active line changes.
- Playback now explicitly loads the local Blob URL before seeking/playing and reports playback errors instead of silently failing.
- Service worker uses network-first updates and immediate activation to avoid an old cached app.js after GitHub Pages deployment.
