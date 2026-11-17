# Device test checklist: names (docs/NAMES.md, OPEN_QUESTIONS R138 to R144, R148, R149)

Nothing here has been seen on a device. Each line says what to do and what passes.

- N1. Settings > Sources > Add a Source. Pass: every type shows its real name (WebDAV, SMB, NFS, SFTP, FTP, FTPS, UPnP/DLNA, Jellyfin, Emby, Plex, OneDrive, Web Link ...); blocked types say "blocked:" and name the service and what is missing.
- N2. Add a source, then open Settings > Sources. Pass: each row reads "<type> · <host>".
- N3. Add a Source > discovery screen. Pass: the text names WebDAV, SMB, NFS, SFTP, FTP and Bonjour, and says UPnP/DLNA servers must be typed in.
- N4. Open a title with a Dolby Vision Profile 8 HEVC file with TrueHD Atmos. Pass: the version row reads like "2160p · HEVC · Dolby Vision Profile 8 / HDR10 · Dolby TrueHD with Dolby Atmos 7.1 · <size>"; the badge and filter chip say "Dolby Atmos".
- N5. A DTS 5.1 file. Pass: the row says "DTS 5.1" and never mentions Atmos.
- N6. Player audio and subtitle pickers and Playback Stats. Pass: formats by real name (Dolby Digital Plus, DTS-HD Master Audio, PGS, SubRip ...); no "Certified", "Ready" or "Works with" anywhere.
- N7. Settings > Storage and iCloud, signed in and signed out of iCloud. Pass: the texts name iCloud and Apple TV, not "the cloud" or "this device".
- N8. Settings > Online Lookup and Discover. Pass: TMDB is named; the TMDB notice and "Where-to-watch data is provided by JustWatch." are shown as text; no logo on these screens (the TMDB logo appears only in Settings > About, N12).
- N9. Settings > Home Screen. Pass: the text names the Top Shelf row on the Apple TV Home Screen.
- N10. Settings > About. Pass: Data Sources, Trademarks and Attributions (seven paragraphs, the "not affiliated" one first) and Open-Source Licences (eight rows) are shown word for word as docs/NAMES.md section 3; all text is reachable with the Siri Remote focus and readable with VoiceOver and Larger Text; no logo other than the TMDB logo (N12), no trademark signs.
- N11. Home Screen with the app in the top row. Pass: the app's own name and icon are neutral (no company logo, no brand colours).
- N12. Settings > About > Data Sources (the only logo in the app, R148). Pass: TMDB's logo is drawn directly above the TMDB notice, in its original colours (green-to-blue gradient, not black, not tinted by focus or the theme), sharp at 4K (vector), smaller than the "About" title; VoiceOver reads "TMDB"; no other screen shows it (Discover, Online Lookup, Top Shelf). If the gradient renders flat or black, the SVG needs a format change (PDF from the same file): record it and do not recolour.
- N13. Settings > About > Open Source (R149). Pass: the written offer, the five LGPL library rows (FFmpeg 8.1.3, libzvbi 0.2.46, libnfs 5.0.2, libsmb2, AMSMB2 4.0.3) each with its upstream address, and the repository line are shown word for word as docs/NAMES.md section 4a; all reachable with the Siri Remote and readable with VoiceOver.
- N14. Settings > About > Open-Source Licences > Full Licence Texts. Pass: ten entries; each opens the full text from the app bundle (never the "missing from this build" sentence), and the Siri Remote scrolls a long text to its end.
