#!/usr/bin/env python3
"""CI only (compile-check.yml, job "screenshots"). Turns the attachments exported by
`xcrun xcresulttool export attachments --path R --output-path RAW` into a viewing-order folder:

  screenshots/01-first-launch.png, 02-..., ...   (name = the XCTAttachment name the UI test gave, e.g. "01-first-launch")
  screenshots/index.md                            every screenshot in order, then every screen NOT reached with its reason

Usage: ci-screenshots-index.py RAW_DIR OUT_DIR
RAW_DIR must contain manifest.json (written by xcresulttool export attachments, Xcode 16 and later). Its exact layout is
read defensively: any object with "exportedFileName" and "suggestedHumanReadableName" anywhere in the JSON is used.
Exit status: 0 when at least one screenshot was copied, 1 otherwise (the step then shows red; the upload still runs).
"""
import json
import os
import re
import shutil
import sys

# #21 G: changes marked "fixed in code, verify in next screenshots". Each is (what changed, what to look for, the screenshot
# name prefixes that show it). index.md lists every item whose screenshots are in this folder (or were not reached), with
# links, so the review goes item by item. Items whose screenshots belong to another job's folder are left out there.
VERIFY = [
    ("The movie page's hero picture is dimmed instead of a dark band behind the text (OPEN_QUESTIONS R182)",
     "the text over the picture is readable and there is no separate dark band", ["57-movie-detail", "60-movie-detail-two-versions"]),
    ("Play has the focus when the movie page opens",
     "Play is the focused (raised, highlighted) button on arrival", ["57-movie-detail"]),
    ("The episode shelves on the show page",
     "each season's episodes in one row with stills, the season 2 row reachable", ["55-show-page", "56-show-season-2-episode-row"]),
    ("The new Needs Review button",
     "the button sits in the row above the grid and opens the Needs Review list", ["63-movies-needs-review-button", "64-needs-review"]),
    ("The Settings two-pane layout",
     "the list on one side and the selected page's content on the other", ["30-settings", "31-settings", "32-settings", "33-settings",
                                                                           "35-settings", "36-settings", "37-settings", "38-settings"]),
    ("The Add a Source sheet and forms",
     "the type list, then each form with its fields and buttons fully on screen", ["10-add-source-types", "11-form", "12-form", "13-form",
                                                                                   "14-form", "15-form", "16-form", "17-form", "18-form",
                                                                                   "19-form", "20-add-source-not-available"]),
    ("The playback error is a system alert over the page",
     "a centred alert with Try Again (when offered) and Done, the page still behind it", ["62-playback-error"]),
    ("Shows has the Movies row: Sort, Filter, Saved Views, Jump to Letter, count (#21 F)",
     "the same buttons in the same order as on Movies (53), and each menu opens", ["07-shows-toolbar"]),
    ("The card long-press menu: Go to Movie / Go to Show and Remove from Continue Watching (#21 F)",
     "Go to ... is first; Remove from Continue Watching shows on a card in that row; Go to opens the page; each of the three "
     "items has its icon (film, tv, minus.circle: names written from memory, and a wrong name is a blank icon, not a build "
     "error; docs/SYMBOLS.md)", ["52-card-long-press-menu", "08-card"]),
    ("The show page has the movie page's synopsis and cast (#22 B, R193)",
     "three lines of synopsis above Play that open the whole text, the cast shelf under the buttons, nothing cut off; "
     "Sample Show 2 has no empty band", ["77-show-long-synopsis", "78-show-no-synopsis-or-cast"]),
    ("About: short page, long legal texts on Learn More pages (#24 C, #25 B9)",
     "40 shows the version, data note, TMDB logo at the row's leading edge with its notice, then Source Code, Full Licence "
     "Texts, Licence Notices and Trademarks rows; 41 scrolls to the end (an UNCHANGED warning is expected once the page "
     "ends); the soft scroll-edge effect under the tab bar", ["40-about", "41-about-scrolled"]),
    ("The Sort by Filename toggle with and without the focus (#24 C)",
     "69 has the focus on Check Connection, 69-…-focused on the toggle; the two pictures differ",
     ["69-source-sort-by-filename"]),
    ("#25 B1: the Add a Source sheet is one column",
     "the title on top, each type one row with its name and ONE short line, nothing cut with an ellipsis, placeholders in "
     "full; the type notes on the About Source Types page; the same at Larger Text and Bold Text",
     ["10-add-source", "11-form", "12-form", "13-form", "14-form", "15-form", "16-form", "17-form", "18-form", "19-form",
      "93-larger-text-add-source", "94-larger-text-source-form", "99-bold-text-add-source", "100-bold-text-source-form",
      "110-default-add-source", "111-default-source-form"]),
    ("#25 B2: the Movies and Shows toolbars on one line",
     "all controls one height on one line; at Larger Text Saved Views, Needs Review and Jump to Letter are in a More menu",
     ["53-movies", "07-shows-toolbar", "63-movies-needs-review-button", "81-larger-text-movies"]),
    ("#25 B3 and B11: Settings rows on one line",
     "Backup shows \"iCloud Sync\" as the value, the longer wording in the footer; no row label or value wraps; the "
     "Jellyfin/Emby toggle reads \"Sort by Filename\"", ["92-larger-text-settings-backup", "69-source-sort-by-filename"]),
    ("#25 B4: titles shrink to fit instead of “…”",
     "Continue Watching and file names on one line, smaller where needed, never cut", ["50-home-rows", "51-home-rows-lower",
                                                                                    "80-larger-text-home", "73-files-movie-folder"]),
    ("#25 B5 and B6: movie page buttons and Media Info",
     "each button's symbol next to its title with the system gap, all buttons one height; Media Info rows with separators, "
     "\"Not checked yet\" for an unread file, frame rate and audio tracks shown", ["57-movie-detail", "58-movie-detail-scrolled",
                                                                                    "60-movie-detail-two-versions", "61-movie-detail-two-versions-scrolled"]),
    ("#25 B7: show page order and cast",
     "the cast after the episode shelves, a person symbol in a circle where there is no photo, a role under every name; "
     "episode labels \"S2 E1 · Second chances\"", ["55-show-page", "56-show-season-2-episode-row", "77-show-long-synopsis-cast"]),
    ("#25 B9: File Details and the Files title",
     "File Details has no empty button: name, size, date, location and Done; Files shows its title", ["70-files-sources", "74-file-details"]),
    ("#25 B10: the movie page opens with Play focused",
     "Play is focused in 57 and 78 (the -FOCUS notes say FOCUS OK)", ["57-movie-detail", "78-movie-no-synopsis-or-cast"]),
    ("#25 A3: menus open in their pictures",
     "the menu is open in each: Shows Sort, Filter, Saved Views (07), the card menu (08, 52), More (44 to 46), Versions (47), "
     "Extras (48), Fix Match (59), the player's audio and subtitles menus (25, 26), Needs Review choice (65), and the move "
     "sheet after its animation (66)", ["07-shows-toolbar", "08-card", "52-card-long-press-menu", "44-movie-more-menu", "45-movie",
                                       "46-movie", "47-movie-versions-menu", "48-movie-extras", "59-fix-match", "25-player",
                                       "26-player", "65-needs-review-choice", "66-move-sheet"]),
]

NAME = re.compile(r"^(\d{2,3})-([A-Za-z0-9][A-Za-z0-9-]*?)(-NOT-REACHED)?(?:_\d+)?(?:_[0-9A-Fa-f-]{8,})?(?:\.[A-Za-z0-9]+)?$")


def entries(node):
    if isinstance(node, dict):
        if "exportedFileName" in node:
            yield node
        for v in node.values():
            yield from entries(v)
    elif isinstance(node, list):
        for v in node:
            yield from entries(v)


def verify_lines(shots, missing, order):
    """One line per VERIFY item that has a screenshot (or a not-reached note) in this folder."""
    out = []
    for what, look, prefixes in VERIFY:
        def hit(key):
            return any(key == p or key.startswith(p + "-") for p in prefixes)
        found = sorted((k for k in shots if hit(k)), key=order)
        lost = sorted((k for k in missing if hit(k)), key=order)
        if not found and not lost:
            continue
        links = ", ".join("[%s](%s)" % (k, shots[k]) for k in found) or "no screenshot"
        line = "- %s. Look for: %s. See %s." % (what, look, links)
        if lost:
            line += " NOT REACHED: %s." % ", ".join(lost)
        out.append(line)
    return out


def main():
    raw, out = sys.argv[1], sys.argv[2]
    os.makedirs(out, exist_ok=True)
    manifest = os.path.join(raw, "manifest.json")
    if not os.path.exists(manifest):
        print("::error::no manifest.json in %s (xcresulttool export attachments did not run or wrote another layout)" % raw)
        return 1
    with open(manifest, encoding="utf-8") as fh:
        data = json.load(fh)
    shots, missing, unnamed = {}, {}, []
    for e in entries(data):
        exported = e.get("exportedFileName", "")
        human = e.get("suggestedHumanReadableName") or e.get("name") or exported
        m = NAME.match(os.path.basename(human))
        src = os.path.join(raw, exported)
        if not m or not os.path.exists(src):
            # #17 E: "Complete Issue Description.txt" was listed here but not in the artifact. Text attachments without a
            # numbered name (such as the full text of a test issue) are now copied into other-attachments/ and linked;
            # pictures are not (an unnumbered picture would break the artifact check, ci-artifact-contents.sh).
            if os.path.exists(src) and not exported.lower().endswith((".png", ".jpg", ".jpeg", ".heic")):
                safe = re.sub(r"[^A-Za-z0-9._-]+", "-", os.path.splitext(os.path.basename(human))[0]).strip("-") or "attachment"
                dest_name = "%s-%s" % (safe, os.path.basename(exported))
                os.makedirs(os.path.join(out, "other-attachments"), exist_ok=True)
                shutil.copyfile(src, os.path.join(out, "other-attachments", dest_name))
                unnamed.append("[%s](other-attachments/%s)" % (human, dest_name))
            else:
                unnamed.append("%s (%s)" % (human, exported))
            continue
        key = "%s-%s" % (m.group(1), m.group(2))
        if m.group(3):
            with open(src, encoding="utf-8", errors="replace") as fh:
                missing[key] = fh.read().strip()
        elif exported.lower().endswith((".png", ".jpg", ".jpeg", ".heic")):
            ext = os.path.splitext(exported)[1].lower()
            dest = os.path.join(out, key + ext)
            if key in shots:  # same name twice (a retried step): keep both, numbered
                dest = os.path.join(out, "%s-%d%s" % (key, len(shots), ext))
            shutil.copyfile(src, dest)
            shots[os.path.splitext(os.path.basename(dest))[0]] = os.path.basename(dest)
    lines = ["# Screenshots (viewing order)", "",
             "Made by the UI tests in UITests/ScreenshotTests.swift on the tvOS Simulator, with the debug-only sample library",
             "(synthetic titles and generated pictures; see OPEN_QUESTIONS R160). Not a device: colours, HDR and focus effects",
             "can differ on a real Apple TV.", ""]
    # Numeric order (NN may have three digits since #16 item 1.10: 80-112 in the accessibility set), then by name.
    def order(key):
        number, _, rest = key.partition("-")
        return (int(number) if number.isdigit() else 0, rest)

    for key in sorted(set(shots) | set(missing), key=order):
        if key in shots:
            lines.append("- [%s](%s)" % (key, shots[key]))
        if key in missing:
            lines.append("- %s: NOT REACHED. %s" % (key, missing[key]))
    lines += ["", "Screenshots: %d. Screens not reached: %d." % (len(shots), len(missing))]
    verify = verify_lines(shots, missing, order)
    if verify:
        lines += ["", "## Fixed in code, verify in these screenshots", ""] + verify
    if unnamed:
        lines += ["", "Attachments without a numbered name (text ones copied to other-attachments/, pictures not copied):"] + ["- " + u for u in unnamed]
    with open(os.path.join(out, "index.md"), "w", encoding="utf-8") as fh:
        fh.write("\n".join(lines) + "\n")
    print("\n".join(lines))
    return 0 if shots else 1


if __name__ == "__main__":
    sys.exit(main())
