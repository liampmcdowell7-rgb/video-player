# Plex fixtures: HAND-WRITTEN, not recorded

Every file here was written by hand from the field names on the Plex Media Server reference
(https://developer.plex.tv/pms/, read 20 Nov 2026) and docs/PLEX_SOURCE.md. None was recorded from a real server, and
no plex.tv or Plex server was contacted. Names are synthetic. Field names marked UNVERIFIED in
Sources/SourcePlex/PlexModels.swift (section `Directory`/`Location`, `viewOffset`, `viewCount`, `lastViewedAt`, PIN
`authToken`/`expiresIn`, resource `provides`) are guesses until a fixture is recorded from the owner's server
(scripts/record-mediaserver-fixtures.sh would need a Plex mode, with tokens redacted).

Tokens in these files are placeholders (`account-token-placeholder`, `server-token-placeholder`), not real values.

`media-providers.json` (added 21 Nov 2026, R308) is written by hand from the example of `GET /media/providers` in the
OpenAPI file of the PMS reference (read 21 Nov 2026), trimmed to the library provider and its `timeline` feature
(`key`, `scrobbleKey`, `unscrobbleKey`). Also not recorded.
