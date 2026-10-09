Musix V75 - queue reliability and backup improvements (development source)

Changes:
- Up Next entries persist across relaunch and can be restored from a Musix backup.
- Queue reordering and removal persist immediately.
- Stop After Current Song now applies when a song finishes naturally, not when the user manually taps Next.
- NowPlayingView.swift is unchanged from V74/V71 layout.

Not a completed 11-feature release. True gapless scheduling and overlapping crossfade are NOT implemented. Existing visualizer is an energy meter, not a spectral analyzer. No iOS SDK build or device test was possible here.
