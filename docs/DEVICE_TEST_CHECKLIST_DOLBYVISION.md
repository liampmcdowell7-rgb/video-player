# Device test checklist: Dolby Vision profile 7, HDR10+ (Apple TV only)

What WSL cannot prove (docs/DOLBY_VISION.md section 8). Use your own legally owned files; the FIXTURE streams from
`scripts/test-dovi.sh` (`~/vp-dovi/media/*.mkv`, synthetic pictures) can be copied to a test share for DV-1 to DV-4.
For each line write the model (Settings > General > About), tvOS version, TV model, result, and the two status lines.

| ID | Check | How | Pass when |
|---|---|---|---|
| DV-1 | Profile 7 FEL plays as Dolby Vision | Play a profile 7 FEL Matroska file on a Dolby Vision TV with Match Dynamic Range on | TV shows its Dolby Vision badge; status "Dolby Vision (converted from Profile 7)" with the FEL note; no stutter |
| DV-2 | Profile 7 MEL | Same with a MEL file | As DV-1, note says nothing is lost |
| DV-3 | Same on each model | Repeat DV-1 on Apple TV 4K 2nd gen, 3rd gen and the current model (Apple's older spec pages list profile 5 only) | Dolby Vision on every model, or a recorded failure per model |
| DV-4 | Seeking | In DV-1, jump forward and back 10 times, including to the last minute | Picture stays in Dolby Vision, no green or magenta frames, no mode flicker |
| DV-5 | Picture check | Compare a FEL title converted here with the same title's HDR10 base layer (status "HDR10 (base layer)" when the conversion is unavailable) on the same TV | Converted picture is not darker / brighter in a broken way; record any visible difference |
| DV-6 | CPU / frame pacing | Play a 4K60 profile 7 file for 10 minutes; open Playback Stats | Dropped frames stay at 0 or same as an 8.1 file of the same bitrate |
| DV-7 | Non-Dolby-Vision TV | Play DV-1 on an HDR10-only TV | Status "HDR10 (base layer)" with "This display does not support Dolby Vision, so the HDR10 base layer plays."; picture normal (the converted 8.1 stream falls back to its HDR10 base layer) |
| DV-8 | Conversion failure path | Play a profile 7 file whose RPU is damaged (if one is available) | HDR10 base layer plays; status says "conversion failed for this file"; no crash |
| DV-9 | Mid-file profile switch | Play a file whose first part is profile 7 and later part 8.1 (if one is available) | No mode change, no glitch at the switch point |
| DV-10 | HDR10+ on 3rd gen or later | Play an HEVC HDR10+ file on a TV that supports HDR10+ | TV's info screen reports HDR10+; status "HDR10+ or HDR10" and the note |
| DV-11 | HDR10+ variant signalling | Same as DV-10 | The variant with `SUPPLEMENTAL-CODECS=".../cdm4"` plays at all (if not, the PROVISIONAL `cdm4` for HEVC must be removed) |
| DV-12 | HDR10+ on 2nd gen | Play the DV-10 file on Apple TV 4K 2nd gen | Plays as HDR10; status note "This Apple TV model does not support HDR10+" |
| DV-13 | Static HDR10 and HLG unchanged | Play an HDR10 file with mastering display / MaxCLL and an HLG file | TV reports HDR10 / HLG; Playback Stats show the same values as before this change |
| DV-14 | Profile 5 and 8.1 unchanged | Play a profile 5 and a profile 8.1 file | Dolby Vision as before; status "Dolby Vision" |
| DV-15 | Link check (first Mac / CI build) | Build the app for a device and for the simulator | No duplicate-symbol or missing-symbol errors from the RPU library |
