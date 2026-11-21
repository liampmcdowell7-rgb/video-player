# Sources wiring (SOURCES area)

How every source type is connected to Add a Source, browsing, scanning and playback. Written from the code; nothing here has
been compiled for tvOS or run on a device (see the never-compiled list in the report and DEVICE_TEST_CHECKLIST_SOURCES.md).

## Per kind

| Kind | Setup fields | Built by | Trust pinned | Playback | Verification label (SourceCatalog.statusLine) |
|---|---|---|---|---|---|
| WebDAV | address, user, password | WebDAVClient + PinnedTransport | TLS (https only) | URL (or loopback when a certificate is pinned) | Tested against a real server |
| SMB | server, port, share, user, password | SMBClients.real (AMSMB2) inside SubfolderSource(share) | none (SMB signs/encrypts itself) | loopback range proxy | Tested with recorded replies only; not yet verified against a real server |
| NFS | server, exported folder | NFSBackends.libnfs + NFSSource | none (NFSv3 has no encryption) | loopback range proxy | same as SMB |
| SFTP | server, port, start folder, user, password | CitadelSFTPBackend in PinningSFTPBackend, SFTPSource | SSH host key (SHA256:...) | loopback range proxy | same as SMB |
| FTP / FTPS | server, port, encryption, start folder, user, password | FTPClient + NetworkFTPConnector(pin) | TLS when explicit or implicit | loopback range proxy | Tested against a real server (plain FTP only, see caveat) |
| Media server (DLNA) | device description address | UPnPClient | none | URL | Tested against a real server |
| Jellyfin | address, user, password | JellyfinClient + PinnedTransport | TLS (https only) | URL (or loopback when pinned) | Tested against a real server |
| Emby | address, user, password | EmbyClient + PinnedTransport | TLS (https only) | URL (or loopback when pinned) | Tested against a real server |
| Web Link | link | LinksSource | none | URL | same as SMB |
| OneDrive | none yet | OneDriveSource | none | URL | blocked: needs an app registration (no client ID exists; SourceConfiguration.oneDriveClientID is nil) |
| Plex | `PlexSetupView` (code, then server list) | none (no form fields) | `SourceBuilder` `.plex` → `PlexClient` (address that answered, server token as the secret) | none | available since R304; fixtures only |
| Dropbox, Google Drive | none | none | none | none | blocked, existing notes kept |

The label text comes from one function, `SourceCatalog.statusLine`, and is shown in three places: the type list (SourceKindRow),
the setup form (SourceFormView), and Settings (SourcesSettingsView row and SourceDetailView "Tested"). Tests in
`SourceWiringTests` pin the exact text per kind. `SourceCatalog.caveat` adds a second sentence where the label is not the whole truth
(FTPS and SFTP have no real-server run, DLNA discovery, etc.).

## Trust (certificate and host key)

- `CertificatePin` (VideoPlayerCore) decides on a fingerprint and remembers a refusal. `TrustGuardedSource` turns any vague
  transport failure into `TrustRefusedError` when the pin refused, so scan, browse and play all end in the same typed error.
- The approved value is stored in `UDSourceDefinition.trustedFingerprint` (part of the source's atomic group, so it syncs and is copied
  to the essentials). TLS: SHA-256 of the leaf certificate as hex. SSH: `SHA256:...` as ssh-keygen prints it.
- First use: nothing approved, so the pin refuses and the setup flow shows the fingerprint (TrustPrompt). The user must press
  "Trust This Server"; the value is saved with the definition. A certificate the system already trusts is accepted without a pin.
- Every later connection (`SourceFactory.makeSource`, `LiveSourceConnector`) builds a pin from the saved value. A different value is refused,
  reported to `TrustCenter`, and shown as "The Server's Certificate/Host Key Changed" with both fingerprints. Only the button
  "Trust the New ..." (behind a confirmation) saves the new value (`AppServices.trustNewFingerprint`). "Keep Blocking" changes nothing.
- Editing host, port or address in the setup form drops an approval given earlier in that flow.

## Passwords and tokens

Passwords and sign-in tokens go through `MirroredSecrets` only (never into a definition, never logged). No error text includes a secret.

## Bonjour host resolution (BUILD 5)

`BonjourBrowser` browses each service type with `NWBrowser`; for each result it opens a short `NWConnection` to the service endpoint
(IPv4 only), and when it is ready reads `currentPath?.remoteEndpoint` (a `.hostPort` address) and cancels. `BonjourMapping.discovered`
(tested) turns that into the host and port for the form (default ports dropped; webdavs gives an https address; a scoped IPv6 address counts as
unresolved). If the connection fails or 6 seconds pass, the name plus ".local" stays (the previous behaviour), editable in the form.
Alternative recorded: `NetService.resolve` (Foundation), which resolves to addresses directly but is documented as deprecated in favour of Network.

## Range proxy (SourceRangeProxy) and the PLAYBACK agent

Sources with no URL (`PlaybackAccess.byteReader`: SMB, NFS, SFTP, FTP) are played by serving the file on a loopback address.
`SourceRangeProxy` (package target, depends on RemuxEngine's `POSIXLoopbackServer`, changes nothing in it) answers GET/HEAD with
`Range` as 206 windows of at most 8 MiB and its own `Content-Range` (the loopback server itself would otherwise return the whole body).

Interface the PLAYBACK agent should call (in the app target, `App/Support/SourceFactory.swift`, reached as `services.sourceFactory`):

```swift
enum PlaybackLocation { case url(URL, headers: [String: String]); case proxied(URL) }
func playbackLocation(for file: StoredFile) async throws -> PlaybackLocation   // @MainActor
func byteReader(for file: StoredFile) async throws -> any ByteRangeReader     // for the converting player
func stopProxies()                                                            // call when playback ends
```

- `.url` for sources with a link (WebDAV, Jellyfin, Emby, DLNA, Web Link, cloud). `.proxied` for byte-reader kinds and for a
  pinned-certificate HTTPS source (the system player would not trust that certificate, this app's connection does).
- One proxy at a time; starting another stops the previous one. A refused certificate or key throws `TrustRefusedError`
  (render with `SourceErrorText.state(for:doing:)`).
- `AppServices.resolvePlayback` still calls `makeSource` + `playbackAccess` and throws `notReadable` for `.byteReader`: switching it to
  `playbackLocation` is the PLAYBACK agent's edit (not done here to avoid editing that function).

## What is NOT done

- OneDrive sign-in code exists (device code, tokens in MirroredSecrets) but stays unreachable until a client ID is configured. None is invented.
- DLNA/SSDP discovery in the app: the multicast entitlement is not offered for tvOS; discovery is by typed address. The SSDP parser is in the package.
- Key-file SFTP login (password only in the form).
- SMB/NFS/SFTP/FTPS have never run on a device; FTPS pinning (`sec_protocol_options_set_verify_block`) is uncompiled Apple-only code.
- `project.yml` lists SourceSFTPCitadel, which only exists after `scripts/setup-citadel.sh`; generate the project after the setup scripts.
