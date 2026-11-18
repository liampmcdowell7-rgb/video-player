# Device test checklist: artwork, online lookups, Discover, letter jump, ledger sync

New items from docs/ARTWORK_DISCOVER.md. The parent merges them into the main checklist. Needs a real Apple TV, your own TMDB key (and optionally an OMDb key), a source with real files, and two devices for the sync items. Nothing in App/ has been compiled or run. Ids A1 onward. "Record" means write down what happened.

## Keys and the no-key states

- A1. Fresh install, no keys. Open the Search tab and leave the field empty (Discover lives there, R167 (c)). Pass: it says "Discover Needs a Key" and where to enter it; nothing else.
- A2. Open any item, choose Fix Match. Pass: it says Fix Match needs your own key and where; there is no search box.
- A3. With no key, watch the network (router or proxy log) while browsing, scanning and opening Discover. Pass: no request to any online service.
- A4. Settings > Online Lookup: read the text. Pass: it states what is sent and where, and that nothing is sent until a key is entered.
- A5. Enter a key with the on-screen keyboard. Pass: it saves, shows masked (only the last 4 characters), Discover now loads. Replace it with a wrong key. Pass: Discover or Fix Match says the key was not accepted and where to fix it.
- A6. Remove Key. Pass: a confirmation; afterwards the screens say a key is needed again.
- A7. Sign in on a second device with the same iCloud account (Apple Account). Pass: the key arrives (masked) after the first launch. Record how long.

## Artwork

- A8. A movie with poster.jpg or folder.jpg next to it. Pass: the card shows it without any key.
- A9. A show folder with poster.jpg above the season folders. Pass: the series card and its episodes show it (episodes without their own thumb).
- A10. With a key, a movie without any picture file. Pass: after a short wait the matched poster appears; opening the item again is instant. Record titles that matched wrongly.
- A11. Replace poster.jpg on the server with a different picture and rescan. Pass: the new picture shows.
- A12. Browse a large library quickly. Pass: no stutter that blocks scrolling; memory stays reasonable (record).
- A13. Settings > Storage: free space low or a system cleanup (if you can force one). Pass: the pictures reappear on demand; nothing breaks.
- A14. Top Shelf: after a scan, leave the app. Pass: Continue Watching items with pictures show on the Top Shelf; items without a picture are left out. Record whether a PNG or JPEG picture saved with a .jpg name is accepted.

## Fix Match

- A15. A wrong match on a movie: search, choose the right title. Pass: title, year and picture update; it is still right after a rescan.
- A16. An episode: choose each scope in turn (this file, this season, the whole show) on different files. Pass: the right episodes change, the others do not; after a rescan the choice holds (it was saved).

## Discover

- A17. With a library of matched shows missing a few episodes. Pass: Missing Episodes lists only aired episodes of seasons you have, with names.
- A18. A movie that belongs to a collection. Pass: the other released parts are listed with "You have N of this collection."
- A19. Play or favorite a few titles. Pass: Similar lists titles you do not own, each with a reason.
- A20. Press a poster to add to the watchlist, press again to remove. Pass: the label changes at once; the watchlist shelf follows; it survives a restart and appears on the second device.
- A21. Where to watch: for a title streaming in your region, the line lists services; for others it says not listed. Change the region in Settings. Pass: the lists change after reload. Record any wrong service names.
- A22. The attribution text is at the bottom of Discover and in About. Record whether the required logo is missing (it is not included).
- A23. Settings > Home Screen > Show Discover off. Pass: the Search tab with an empty field shows only "Search Your Library", and no request is sent.
- A24. Search tab with a key set: empty field shows Discover; type a letter. Pass: only library results, no Discover row among them. Clear the field. Pass: Discover is back at once, with no new loading (it was not reloaded).
- A25. Search tab, empty field: press Menu. Pass: focus goes to the tab bar. Six tabs in the bar, in this order: Home, Movies, Shows, Files, Search, Settings, none faded or cut off (record where the system puts Search if it differs).

## Letter jump list

- A24. Movies sorted by title: open Jump to Letter. Pass: only letters with titles, with counts; choosing one starts the grid there and scrolling on continues. Record whether the grid starts at the top after a jump.
- A25. Change the sort to date added. Pass: the jump menu disappears.
- A26. Shows: choose a letter. Pass: the grid scrolls to the first show of that letter.
- A27. Open the menu with the remote. Pass: 27 entries are reachable with the focus engine without trouble.

## Ledger cloud sync

- A28. Mark something watched on device 1. Pass: after about 5 seconds the status says last synced; device 2 shows it after it returns to the foreground or within 15 minutes.
- A29. Sign out of iCloud. Pass: the status says not signed in with the number of waiting changes; no repeated requests (watch the log). Sign in again. Pass: it uploads the waiting changes without a restart (account-change notification NOT CHECKED: if it does not, Sync Now must work and the 15 minute pull must).
- A30. Turn off the network, change something, turn it on. Pass: the status says offline with waiting changes, then synced.
- A31. Sync Now. Pass: the status changes to syncing and then to last synced.
- A32. Delete the app's cached data (system cleanup or reinstall) while signed in to iCloud. Pass: watch state, saved views, sources and the watchlist come back after the first launch.
