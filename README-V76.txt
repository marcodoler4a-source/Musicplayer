Musix V76 - Crossfade engine development

Two AVAudioPlayerNode instances share the existing EQ/time-pitch chain. The next track is decoded ahead of the boundary, played concurrently for adjustable equal-power crossfade, and the live player-node references are swapped at the transition so the incoming track is not restarted. Settings UI for crossfade duration is not yet wired; setCrossfade(_:) is exposed on PlayerModel and defaults to zero.

LIMITATIONS: The 250ms timer schedules zero-crossfade transitions shortly before the track boundary, so sample-accurate gapless playback is NOT established. True gapless requires frame-accurate audio timeline scheduling and validation of compressed-file encoder delay/padding. Crossfade and queue behavior require testing on iOS hardware. This is development source, not a verified production release.

Existing NowPlayingView.swift has not been modified.
