# Device test checklist: converted playback (MKV through the loopback player)

New items from docs/PLAYBACK_WIRING.md. The parent merges them into the main checklist. Every item needs a real Apple TV, a real TV or receiver, and real files; none has been run, and none of the App/ code has been compiled. Each item says what to do and what a pass looks like. Ids P1 onward. When a result is "record", write down what happened; it is an input to a decision, not a pass or fail.

Files to have ready (one each where possible): HDR10 MKV (HEVC, PQ); HLG MKV; Dolby Vision profile 5 MKV; Dolby Vision profile 8.1 MKV; Dolby Vision profile 7 MKV (FEL if you have one); SDR H.264 MKV; MKV with AC-3 5.1; with E-AC-3 5.1; with E-AC-3 Atmos (JOC); with AAC stereo; with DTS only; with TrueHD only; with TrueHD plus an AC-3 core; with SRT, ASS and WebVTT subtitles; with PGS subtitles; with a VobSub track; a file over 20 GB; a file of 3 hours or more; an AVI and a TS file (for the refusal); a damaged MKV (cut a file in half); a VP9 MKV.

## Start and display

- P1. Open an HDR10 MKV from a server. Pass: it starts within a few seconds, picture is HDR10 (the TV shows its HDR indicator), no black screen. Record the time to first frame.
- P2. Open an HLG MKV. Pass: the TV switches to HLG (or the display state the status text reports).
- P3. Open a Dolby Vision profile 8.1 MKV on a Dolby Vision TV. Pass: the TV shows its Dolby Vision indicator. Repeat on a TV without Dolby Vision. Pass: HDR10 plays and Playback Stats says the display does not support Dolby Vision.
- P4. Open a Dolby Vision profile 5 MKV on a Dolby Vision TV. Pass: colours are right (not green and purple). On a TV without Dolby Vision, record what plays; the status text must not claim Dolby Vision.
- P5. Open a Dolby Vision profile 7 MKV. Pass: it plays as HDR10; Playback Stats says "HDR10 (base layer)" and that conversion is not available on this device in this version. No Dolby Vision indicator on the TV.
- P6. Match Content: with Match Dynamic Range and Match Frame Rate both on in the system settings, open a 23.976 fps HDR10 file from an SDR home screen. Pass: the TV switches mode before the first frame and the first seconds look right (no washed out or stretched picture, no visible mode change after playback starts). Then turn each setting off in turn. Pass: the app does not force a switch (record what the TV does).
- P7. Open a 25 fps and a 59.94 fps file. Pass: the frame rate matches when Match Frame Rate is on. Record whether the FRAME-RATE in the playlist was enough or whether the display switch needs `AVDisplayManager` criteria set by the app (alternative in docs/API_USAGE.md).
- P8. Open an SDR H.264 MKV. Pass: plays, no HDR indicator.

## Audio paths and honest status

- P9. AC-3 5.1 over HDMI to a receiver that takes Dolby Digital. Pass: the receiver shows Dolby Digital; Playback Stats says "Dolby Digital 5.1 (passthrough)". Repeat to TV speakers only. Pass: Stats says the output decodes it (or says it does not know, with the note); sound plays.
- P10. E-AC-3 5.1 the same way. Pass: the receiver shows Dolby Digital Plus (or Dolby Digital if the receiver cannot take it, and Stats must not claim more than the receiver reports).
- P11. E-AC-3 Atmos (JOC) over HDMI to an Atmos receiver. Pass: the receiver shows Dolby Atmos. This is the check of `EAC3Atmos` (never run against a real stream) and of the `CHANNELS="n/JOC"` playlist line. Record the receiver display and what Stats says. If the receiver shows Dolby Digital Plus only, the playlist signalling or the dec3 extension is wrong: save the first 512 KB of the file's audio track for analysis.
- P12. Same Atmos file to TV speakers. Pass: sound plays as the channel bed; Stats must not claim Atmos output.
- P13. AAC stereo and AAC 5.1. Pass: plays; Stats says AAC (passthrough).
- P14. DTS-only file. Pass: video plays WITHOUT sound, an alert says why ("Playing Without Sound", names DTS), the Playback Stats note repeats it. Never silent without a reason.
- P15. TrueHD-only file and TrueHD plus AC-3 core. Pass: same as P14 (this version cannot decode TrueHD and does not extract the AC-3 core; the spec's "TrueHD core" path is not built). Record that the text does not claim a core is playing.
- P16. File with several audio tracks (AC-3, E-AC-3, DTS). Pass: the audio menu lists the first two with their names; the DTS one is not listed and Stats notes it; switching tracks works and Stats follows the track in use.
- P17. Switch the audio output while playing (HDMI to a Bluetooth speaker and back). Pass: playback continues or pauses sensibly; Stats updates on the next refresh.

## Subtitles

- P18. SRT, ASS and WebVTT tracks in one file. Pass: all three appear in the system subtitle menu with their names and languages; picking each shows text at the right time; bold and italic show; ASS positioning and colours are NOT drawn (decision D5, text is plain).
- P19. Forced track and a hearing-impaired track. Pass: the forced track is chosen automatically when the audio language differs from the system language (record what happens); the SDH track is marked as such in the menu.
- P20. System caption style (Settings, Accessibility, Subtitles and Captioning): change size and background. Pass: the subtitles follow it.
- P21. Timing: pause on a cue, compare with the file's timestamps (a known cue at 10:00.000). Pass: appears within about 0.2 s of the right time. Repeat after a seek.
- P22. Record whether the player downloads every subtitle segment at the start (watch the app's network use or the server's read counters). The engine counts `subtitleWindowLoads`; a whole-file read at start means the read-ahead design needs a change.
- P23. PGS: the "Picture Subtitles" menu appears in the transport bar ONLY for a file with PGS. Choose a track. Pass: bitmaps appear in the right place and size, with correct colours and transparency (this checks the straight-alpha image creation), at the right time.
- P24. D1 exclusivity: with a PGS track on, choose a text track in the system menu. Pass: the PGS picture disappears. With a text track on, choose a PGS track. Pass: the text subtitle turns off. Choose Off in the picture menu. Pass: pictures stop.
- P25. PGS after a seek to the middle of a scene. Record whether the first subtitle is missing (known limit) and for how long.
- P26. VobSub track. Pass: not offered anywhere; Playback Stats notes it.

## Seeking and position

- P27. Seek by scrubbing to 10 %, 50 %, 90 % of a 2 hour file. Pass: playback resumes within a few seconds each time; record the times and the server throughput during each.
- P28. Skip forward and back with the remote (10 s and 30 s), repeatedly. Pass: no stall longer than a few seconds, no crash.
- P29. Resume: stop at 40 min, open again. Pass: starts near 40 min. Open the same file from Continue Watching. Pass: same.
- P30. Seek at the very end and the very start. Pass: no hang; at the end the item finishes and is marked watched.
- P31. A file with no seek index (a recording made without Cues). Pass: opens (slower), Stats notes the missing index, seeking works to within a few seconds.

## Picture in Picture and background

- P32. While a converted file plays, press the Picture in Picture control (or go Home). Pass: a PiP window keeps playing. Record: does the loopback server keep serving (no stall for 2 minutes)?
- P33. Return from PiP to full screen. Pass: the full player comes back. If the app opens at its home screen instead, the restore delegate is needed (not built).
- P34. Background the app for 10 minutes with PiP off. Pass: record whether playback stops, and that returning shows the player or a clear message, never a black screen.
- P35. Interruption: start playback, trigger a system sound or another app's audio, pause for 5 minutes, resume. Pass: resumes where it was; no reconnect error. Record whether the loopback port is still open after a long pause (if not, a resume must restart the session).

## Memory, long files, load

- P36. A file over 20 GB (remux): play for 30 minutes. Pass: memory stays below the budget (record the peak in the Memory gauge); no jetsam kill.
- P37. A 3 hour file: play through. Pass: finishes; no gradual memory growth; progress saved.
- P38. A very high bitrate file (above the engine's budget). Pass: Stats notes the high bitrate; playback may stutter but does not crash.
- P39. Source over a slow connection (throttle to 20 Mbit/s with a 60 Mbit/s file). Pass: buffers and says nothing false; no crash; record the stall behaviour.
- P40. Leave the player (Menu) during opening of a large file. Pass: the server and the file reader close (no later activity on the source).

## Error states (each must show a plain reason and a what-to-do line, never a black screen or a silent return)

- P41. A damaged MKV (cut in half). Pass: the "Can't Play This Title" screen says the file looks damaged and what to do.
- P42. A VP9 or AV1 MKV. Pass: names the video format, says it cannot be played yet, suggests converting to H.264 or HEVC.
- P43. An AVI and a TS file. Pass: refused up front with the list of file types this version plays.
- P44. Turn the server off, then open a title. Pass: says the file could not be read from its source and to check the server.
- P45. Delete the source in Settings while a title is queued, then open it. Pass: says the source is not set up any more.
- P46. A file with encrypted or unsupported compressed tracks, if one exists. Pass: the matching message.
- P47. Start playback and kill the server mid-play. Pass: a message appears (the player item fails; the reason replaces the black screen), not a frozen picture.
- P48. Check every message above for wording: formats, servers and services by their real names (docs/NAMES.md), no certification claims, no other player apps, no codes, no blaming.

## Loopback behaviour

- P49. Run two playbacks in a row (leave, open another file). Pass: each gets its own loopback address; the first stops serving.
- P50. With the Settings "local network" permission denied, play a converted file. Pass: it plays (127.0.0.1 is not the local network). Record whether the system asks for permission.
- P51. Confirm nothing outside the device can reach the loopback port (scan from another machine on the network). Pass: refused.
