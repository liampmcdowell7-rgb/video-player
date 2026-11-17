# Device test checklist: skip segments and Up Next

New items from docs/SEGMENTS.md. The parent merges them into the main checklist. Every item needs a real Apple TV and a real server; none has been run. Each says what to do and what a pass looks like. Ids G1 onward.

## Skip button focus and timing (real remote)
- G1. Play an MKV with chapters named Intro, Chapter 02, Credits. Pass: while the controls are hidden, "Skip Intro" appears bottom trailing at the start of the intro chapter and goes when the playhead leaves it.
- G2. With the button showing, press Select on the remote. Pass: playback jumps to the end of the intro, once; the button disappears; no double jump on a quick second press.
- G3. With the button showing, show the controls and hide them again. Pass: the button is still correct. Record whether it is reachable by focus without showing the controls.
- G4. Scrub into the intro and out of it. Pass: the button follows the playhead within about a second.
- G5. Turn Settings > Playback > Show Skip Buttons off. Pass: no button on the next playback.
- G6. Record how long after the file opens the button first appears on a slow server (chapters and sidecars are read in the background, 6 second limit). Pass: playback starts at once; the button may appear late, never blocks.

## Up Next proposal (system player)
- G7. Play an episode that has a next episode in the library, to its credits. Pass: the Up Next card appears at the credits start with the next episode's title.
- G8. Press Play Now on the card. Pass: the next episode starts. Press Cancel (Menu) on another run. Pass: the card goes, the current episode keeps playing and does not come back for the same credits.
- G9. With Play Next Episode Automatically on, let it run. Pass: the next episode starts after the countdown (docs/SEGMENTS.md says the countdown is the app's, the card shows no number: record what the card shows).
- G10. Play the last episode of a show. Pass: no Up Next card, no error.
- G11. Record what the card looks like with a missing title and no preview image.

## Mark action usability
- G12. Open the transport bar. Pass: a "Mark Skip Points" menu is next to Playback Stats and opens with the remote.
- G13. Choose Mark Intro at 1:00, then Mark Intro End at 2:30. Pass: the first line of the menu says what happened; reopening shows the intro mark with its times and a Delete entry.
- G14. Stop and play the same episode again. Pass: the Skip Intro button shows over the marked range (the mark was saved).
- G15. Mark an end too soon (under 10 seconds). Pass: the menu says why it was refused and the start is kept.
- G16. Delete a mark, then Undo. Pass: the mark returns.
- G17. Record how many remote presses a full mark takes, and whether the menu is usable while the video plays.

## Sidecar files on a real server
- G18. Put `<name>.edl` with a line like `40 100 intro` next to the video on a WebDAV server. Pass: the button appears over 0:40 to 1:40.
- G19. Put `<name>.segments.json` per docs/SEGMENTS.md. Pass: same.
- G20. Put a broken sidecar (random text). Pass: no crash, no button from it, other sources still work.
- G21. A folder with thousands of files. Pass: folder listing does not delay playback start.

## Marks across devices
- G22. Mark on one device with the same account on another. Pass: the mark appears after a sync; a delete on one removes it on the other.
