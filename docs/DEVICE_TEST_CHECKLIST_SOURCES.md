# Device test checklist: sources (SOURCES area)

Each line is a thing only a real tvOS device and a real server can show.

- [ ] Add a Source lists every type; OneDrive, Dropbox and Google Drive appear under "Not Available Yet" with their notes; the others, Plex included ("Plex media server"), show their label.
- [ ] The label text matches SourceCatalog.statusLine in the list, the setup form, the Settings row and the source detail.
- [ ] WebDAV over https with a self-signed certificate: prompt shows the fingerprint, approving saves it, browse, scan and play all work afterwards.
- [ ] Change the server certificate: the source shows "The Server's Certificate Changed" in Settings; scan, browse and play are refused; nothing is trusted until "Trust the New Certificate" is confirmed.
- [ ] SMB with a share: sign in, browse the share, scan, play an MP4 through the loopback proxy (seek works).
- [ ] SMB as guest (no user name).
- [ ] NFS export: mount, browse, scan, play (NFSv3 only).
- [ ] SFTP first connect: host key prompt, approve, browse, scan, play via loopback; then change the host key and confirm it is refused with the "Host Key Changed" state.
- [ ] FTP plain, explicit FTPS and implicit FTPS (port 990): connect, list, play; for FTPS with a self-signed certificate, approve once, then change the certificate and confirm refusal.
- [ ] A system-trusted FTPS certificate connects without a prompt.
- [ ] DLNA: type the device description address, browse, play.
- [ ] Jellyfin and Emby: sign in with user name and password, browse, play; with https and a self-signed certificate, play goes through the loopback address.
- [ ] Plex (docs/PLEX_SOURCE.md; R302 to R304): Add a Source > Plex shows a code; entering it at plex.tv/link on a phone lists the account's servers with "Local" or "Remote"; choosing the home server saves it. The address it saved is local (https `*.plex.direct` first); with the Mac or PC switched off the page says the server did not answer and nothing is saved.
- [ ] Plex browse: the source shows one folder per Movies or TV Shows library with the server's own folders and file names below; a show's episodes appear under their season folders; the library scan finds and matches them like the same files over SMB.
- [ ] Plex playback (R305): an MP4 plays at once in the system player (direct, original quality); an MKV with DTS audio plays through the app's own conversion with sound; a 4K Dolby Vision file plays and the TV shows Dolby Vision; an MPEG-2 or VC-1 file says "The Apple TV cannot play this file" and the Plex server shows no conversion session.
- [ ] Plex watch state (R306): after adding the server, films watched in Plex show as watched and a film stopped halfway in Plex shows its resume point; watching something in this app does not change what Plex shows as watched on another device.
- [ ] Plex two-way watch state, stage 4 (R309, R310; the switch "Sync Watched Status with Plex" in the Plex source's settings, off by default). With the switch on: (1) play a film here for a few minutes and stop: another Plex app (phone or web) shows the same resume point; play it here to the end: the other app shows it watched. (2) Mark it as unwatched here: the other app shows it unwatched. (3) While it plays here, the Plex dashboard (Plex Web, Dashboard) shows this Apple TV playing it, paused when paused. (4) Whether Plex adds a history entry for a play here: record what was found (Plex Web, the server's history), and whether one play shows once or twice. (5) Switch the server off, stop a film here at a new point, switch the server on and scan: the other app shows the new point. (6) Change the resume point in the other app, then scan here: this app takes it (the newer change wins). (7) Turn the switch off, play and mark something here: nothing changes in the other app, and the dashboard shows nothing.
- [ ] Plex metadata (R307): a Plex film's page shows the synopsis as written in Plex and its card shows the Plex poster (a custom poster chosen in Plex shows here too); with a TMDB key the cast still appears; a film found only on WebDAV shows the online synopsis and poster as before (a film on both Plex and WebDAV is one item and shows the Plex synopsis).
- [ ] Plex resume and server off: stop a film halfway, play it again and it resumes there; switch the server off and play: one plain message (the server could not be reached, or the file could not be opened; which one is UNVERIFIED), no endless spinner.

Source setup screens (docs/SOURCE_SETUP_DESIGN.md; R320 to R331):

- [ ] Each form: rows look like tvOS Settings (value trailing, chevron); Select opens the entry page; the keyboard heading says the field name; Done fills the row.
- [ ] The URL keyboard on Address, the number pad on Port, dots on Password.
- [ ] With an iPhone nearby: the iPhone offers to type into the field; paste from the iPhone works.
- [ ] Back on a form returns to the type list; Cancel on Add a Source closes it.
- [ ] Search Your Network on a WebDAV form fills the rows from a found server.
- [ ] Larger Text: every row and Connect reachable with Down.

- [ ] Web Link: add a direct video link, play it.
- [ ] Bonjour: each advertised type appears; the form is filled with an IPv4 address (not name.local) when resolution worked, and with name.local when not.
- [ ] Info.plist: NSBonjourServices and NSLocalNetworkUsageDescription are honoured on tvOS (the pages checked do not state tvOS applicability); a local-network prompt appears.
- [ ] No multicast entitlement is requested, and the app still passes signing.
- [ ] Loopback range proxy: AVPlayer starts playback and seeks (ranges, 206, Content-Range), and the first request is not blocked by App Transport Security for 127.0.0.1.
- [ ] Citadel, AMSMB2 and libnfs link and run on tvOS 27 (never compiled).
