# Device test checklist: platform items

New items from docs/PLATFORM_AUDIT.md. The parent merges them into the main checklist. Every item needs a real Apple TV; none has been run. Each says what to do and what a pass looks like. Item ids P1 onward.

## Player, voice and remote
- P1. Say "Skip ahead 15 seconds" (Siri Remote) during playback of a remuxed MKV. Pass: playback jumps about 15 seconds forward. Note the exact phrase variants that work.
- P2. Say "What did they say?" during playback with a text subtitle track. Pass: it rewinds a short way and shows the subtitle. Repeat with no subtitle track and with a PGS track; record what happens (PGS is expected not to work).
- P3. Open the subtitle menu in the system player. Pass: every text subtitle track of the file appears once, no duplicate, no entry from our own list; a "Picture subtitles" item appears only for files with PGS.
- P4. Pick a PGS track, then a text track, then Off. Pass: exactly one source is visible at a time; switching clears the other.
- P5. Change the system caption style (Settings > Accessibility > Subtitles and Captioning) and play a text track. Pass: our WebVTT text follows the style. Record if it does not.
- P6. Play/Pause button, swipe-scrub, click-scrub on the touch surface. Pass: standard system behaviour, no custom gesture.
- P7. Connect a Bluetooth keyboard; press Space during playback. Pass: pauses and resumes.
- P8. iPhone Remote (Control Center) controls playback and navigation. Pass: play, pause, skip, directional navigation work.
- P9. Connect a game controller. Pass: A selects, B goes back in menus; record what the controller does during playback.
- P10. Now Playing entry (OPEN_QUESTIONS R157: published by the system player from `externalMetadata`; the app writes no Now Playing info of its own). Play an episode that has a poster, once as a direct file and once through the converting player. (a) Open Control Center / the Now Playing view from the Home Screen (hold the TV button). Pass: the title and the episode line (second line) are ours, the poster is shown, the position matches the player and moves. (b) In that view, press Play/Pause on the Siri Remote and use the on-screen play/pause. Pass: playback pauses and resumes and the position stops and restarts. (c) Skip 10 s forward and back with the Siri Remote, then look again. Pass: the position follows. (d) A poster that appears a few seconds after playback starts (artwork added after start): record whether it shows at all; if not, artwork must be set before the item is handed to the player. (e) Stop playback. Pass: the entry goes away or shows paused, and no second, stale entry from our app remains.
- P11. Skip Intro / Credits button and Next Episode proposal appear in the system player at the right times and the Siri Remote Select activates them.

## Picture in Picture
- P12. Start PiP from the transport bar for a remuxed MKV from the loopback server. Pass: video continues in the corner, audio continues, the loopback server keeps serving for at least 10 minutes of PiP.
- P13. Go to the Home Screen with PiP active, then reopen the app. Pass: restore is fast, no crash, position is correct.
- P14. Start a second video in another app, swap. Pass: both directions work, no mixed audio.
- P15. Seek, skip and audio-track change inside PiP. Record which controls PiP shows (Skip Intro and Next Episode buttons are expected not to appear).
- P16. Stop PiP from the PiP window. Pass: the loopback server and read-ahead stop within 30 seconds and memory falls.

## Lifecycle
- P17. Play 2 minutes, press Home, wait 5 minutes, reopen. Pass: Resume shows the right position, no prompt.
- P18. Watch the playback position in CloudKit after pause and after 60 seconds of playing (second device or reinstall). Pass: saved position within 60 s of reality.
- P19. Leave the Apple TV playing for the screen-saver timeout. Pass: no screen saver during playback. Pause and wait: record when the screen saver starts.
- P20. Phone-call-style interruptions: start Siri during playback. Pass: playback pauses and resumes as the system does for other apps.
- P21. Switch the Apple TV user (Control Center > users) with the app open and with the app closed. Record: does the library, history and server list change, stay, or does the app crash? This decides D2.

## Audio, display, hardware
- P22. HDMI to a TV, then to an eARC soundbar, then AirPlay speaker, then a HomePod pair, then Bluetooth headphones: for each, check the Playback Stats text matches what is truly playing (channels, codec) and never says Atmos on a stereo route.
- P23. Change the audio route while playing (unplug HDMI, switch AirPlay speaker). Pass: no crash, status text updates within a second, playback pauses or continues as the system decides.
- P24. Match Content on (Dynamic Range and Frame Rate) with an HDR10 file, a Dolby Vision file and a 23.976 fps file. Pass: the TV switches mode; the status text says what the OS did. With Match Content off, the text says so.
- P25. Check the status text for an HDR10+ file: it must say HDR10 and must not say HDR10+.
- P26. Run the library scan plus a 4K remux with high bitrate on the oldest supported Apple TV; watch for memory pressure or thermal throttling (stutter after 20 minutes). Record the device model and what read-ahead budget worked.
- P27. Playing from a server with old TLS: pass is a clear message, not a silent failure (tvOS 26 and 27 TLS minimums).

## Text entry and setup
- P28. Add a server by Bonjour pick: count remote presses. Add by typing: type the host with the iPhone keyboard (Continuity) and with paste. Pass: both work in the standard field; a pasted full URL is split correctly.
- P29. Text fields on tvOS 27: `.bordered` style, focus, Larger Text at the largest size. Pass: nothing clipped.

## Accessibility
- P30. VoiceOver on: navigate every screen; every poster, button and track has a spoken label.
- P31. Larger Text, Bold Text, Increase Contrast, Reduce Motion, Reduce Transparency each on: nothing unreadable, motion replaced by fades.
- P32. Dim Flashing Lights on with a file with flashes: record the OS behaviour.
- P33. Audio description track (if the file has one) is selectable from the system audio menu. Record whether it is labelled as audio description.

## Liquid Glass and App Store
- P34. Look at every screen on tvOS 27: standard buttons, tabs and the player look like the system apps; no hand-made blur. Compare with the Settings app side by side.
- P35. Top Shelf shows the last snapshot while the app is closed; after a purge (free space) it shows the static fallback image without errors.
- P36. Check with an Apple TV 4K 2nd generation if available: design and performance differ from 3rd generation.
- P37. First TestFlight build: App Store Connect shows no privacy manifest email, no export-compliance prompt that contradicts `ITSAppUsesNonExemptEncryption`.
