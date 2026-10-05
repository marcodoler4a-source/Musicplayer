# MeloPlayer Native iOS — UI + Synced Lyrics Fix

Changes in this build:
- True full-screen Now Playing using fullScreenCover
- Smaller adaptive typography and corrected safe-area alignment
- Album art sized responsively instead of oversized fixed layout
- LRC parser for [mm:ss.xx] / [mm:ss.xxx] timestamps
- Synced lyrics auto-highlight and auto-scroll with playback time
- Import .lrc/text files from Files
- Online LRCLIB search prefers syncedLyrics over plainLyrics
- Plain online lyrics are clearly shown as non-synchronized when timestamps are unavailable
- Physical iPhone / AltStore Codemagic packaging retained
