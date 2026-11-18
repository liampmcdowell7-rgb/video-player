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

NAME = re.compile(r"^(\d\d)-([A-Za-z0-9][A-Za-z0-9-]*?)(-NOT-REACHED)?(?:_\d+)?(?:_[0-9A-Fa-f-]{8,})?(?:\.[A-Za-z0-9]+)?$")


def entries(node):
    if isinstance(node, dict):
        if "exportedFileName" in node:
            yield node
        for v in node.values():
            yield from entries(v)
    elif isinstance(node, list):
        for v in node:
            yield from entries(v)


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
    for key in sorted(set(shots) | set(missing)):
        if key in shots:
            lines.append("- [%s](%s)" % (key, shots[key]))
        if key in missing:
            lines.append("- %s: NOT REACHED. %s" % (key, missing[key]))
    lines += ["", "Screenshots: %d. Screens not reached: %d." % (len(shots), len(missing))]
    if unnamed:
        lines += ["", "Attachments without a numbered name (not renamed):"] + ["- " + u for u in unnamed]
    with open(os.path.join(out, "index.md"), "w", encoding="utf-8") as fh:
        fh.write("\n".join(lines) + "\n")
    print("\n".join(lines))
    return 0 if shots else 1


if __name__ == "__main__":
    sys.exit(main())
