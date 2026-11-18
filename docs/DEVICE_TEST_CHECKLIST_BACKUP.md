# Device test checklist: iCloud backup of generated data

Items from docs/BACKUP.md (decision R163). Needs a real Apple TV signed in to iCloud, a source with real files, and for some
items a second Apple TV (or a reinstall). The CloudKit adapter has NOT run anywhere yet: until B1 passes, nothing below is
known to work. Ids B1 onward. "Record" means write down what happened, with the time it took.

Before the first Production (TestFlight) build: deploy the CloudKit schema with the record types `BKManifest` (fields
`generation` Int, `payload` Asset) and `BKChunk` (fields `codec` String, `data` Asset) in zone `LibraryBackup`, next to
`UDRecord` (docs/STORAGE_MODEL.md section 1: unknown types are an error in Production).

## The screen

- B1. Settings > Backup opens. Pass: three switches (Library Data, Artwork, Settings and Watch State shown as "Kept by
  iCloud Sync"), each with what it includes; the sentence that it uses your own iCloud storage, shared with other iCloud
  features; "Never included: your videos, passwords, sign-in tokens and API keys."; Size in iCloud; Last Backup "Never".
- B2. Turn Artwork off, then on. Pass: "Only Artwork for Items in Your Library" appears only while Artwork is on; the
  choices survive quitting the app.
- B3. Focus moves through every row with the Siri Remote; nothing is cut off at the largest text size.

## Backing up

- B4. Signed in, with a scanned library: Back Up Now. Pass: "Backing up the library: N %", then pictures; afterwards Last
  Backup shows today's time and Size in iCloud is above zero. Record the size, the number of items and the time taken.
- B5. Play a video while a backup runs. Pass: playback starts and seeks as normal (no stall, no dropped frames you notice).
- B6. Back Up Now again with no change. Pass: it finishes much faster (only changed pieces go up); the size stays about the same.
- B7. Add a source and let the scan finish; wait 3 minutes. Pass: Last Backup changes without pressing anything.
- B8. Quit, wait a day (or change the clock forward a day if that is practical), open the app. Pass: a backup runs at launch.
- B9. In the iCloud settings (on any device) check the storage used by Video Player. Record it next to the size the screen shows.

## Status texts (each state once)

- B10. Signed out of iCloud (Settings app > Users and Accounts): open Settings > Backup. Pass: "Sign in to iCloud in the
  Settings app on this Apple TV to back up your library."; Back Up Now does not upload.
- B11. No network (unplug the network): Back Up Now. Pass: "iCloud could not be reached. The backup will try again later."
- B12. iCloud full (an account with almost no free space): Back Up Now. Pass: the library is backed up or the screen says
  iCloud is full; for pictures, "N files were left out (size) because iCloud is full."
- B13. A backup from a newer version: install a newer build on another Apple TV, back up there, then restore on this one
  with the older build. Pass: "The backup in iCloud was made by a newer version of Video Player..." and nothing changes.
- B14. In progress: the percentage moves while backing up and while restoring.
- B15. Last error: after B11, reconnect and open the screen. Pass: the last problem is shown until the next backup finishes.

## Restoring

- B16. Automatic restore after a cleanup: delete the app's data the way the system would (reinstall the app), open it.
  Pass: "Restoring your library from iCloud" with progress at the bottom of the screen; the Home rows fill with posters
  first; the library is back before the scan would have finished. Record the time to a full Home screen.
- B17. Watch state after B16: what you watched before is still marked watched, and the place in a half-watched film is kept.
- B18. Restore from iCloud (manual): the confirmation names what it replaces; Restore. Pass: the library matches the backup;
  anything changed more recently on this Apple TV (a picture, a Fix Match) is kept.
- B19. Interrupt a restore (quit the app halfway, once while the library loads and once while the pictures load), open it
  again. Pass: it finishes without starting over (faster the
  second time) and the library is complete.
- B20. A second Apple TV signed in to the same iCloud: fresh install. Pass: the library from the first Apple TV appears
  without a scan of every source (the sources still need their passwords entered, as before).

## What must never happen

- B21. A source password, a sign-in token or an API key never appears in iCloud. The pieces are compressed, so looking at
  them in Apple's CloudKit Console proves little; this item only records that the `BKManifest` and `BKChunk` records exist
  in zone `LibraryBackup` and that no other record type appears. The real guard is the engine, which searches every file
  BEFORE compression and refuses it with "a file held a password or key, so nothing was uploaded" (WSL test
  testNoPasswordTokenOrAPIKeyCanBeUploaded). Optional: put a test password in a source, back up, and check the status line.
- B22. No video file is ever uploaded: Size in iCloud stays far below the size of your videos.
