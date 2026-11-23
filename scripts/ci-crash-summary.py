#!/usr/bin/env python3
"""R423: a Markdown summary of the app's crash reports, for the job summary ($GITHUB_STEP_SUMMARY).

Usage: ci-crash-summary.py REPORT_DIR > summary.md

For each file in REPORT_DIR (the copies made by scripts/ci-crash-reports.sh): its file name, the exception type and
reason, the crashed thread number and the first 30 frames of the crashed thread, in a code block. An .ips file is a
JSON header line followed by a JSON body. The keys read here ("exception", "termination", "asi", "faultingThread",
"threads", "frames", "usedImages") are not documented on any Apple page read (Apple's "Analyzing a crash report" shows
the text form): UNVERIFIED, so whenever the body cannot be read that way, the summary shows the first 60 lines of the
file instead. Prints "No crash report of the app" when the folder holds none. Standard library only.
"""
import json
import os
import sys

FRAMES = 30
FALLBACK_LINES = 60


def fence(lines):
    """A code block that the report's own text cannot close."""
    return ["```text"] + [line.replace("```", "'''") for line in lines] + ["```"]


def first_lines(path):
    with open(path, encoding="utf-8", errors="replace") as handle:
        return [line.rstrip("\n") for _, line in zip(range(FALLBACK_LINES), handle)]


def frame_text(index, frame, images):
    image = "?"
    number = frame.get("imageIndex")
    if isinstance(number, int) and 0 <= number < len(images):
        image = images[number].get("name") or "?"
    symbol = frame.get("symbol") or "0x%x" % frame.get("imageOffset", 0)
    place = ""
    if frame.get("sourceFile"):
        place = " (%s:%s)" % (frame["sourceFile"], frame.get("sourceLine", "?"))
    return "%-3d %-24s %s%s" % (index, image, symbol, place)


def reason(body):
    parts = []
    exception = body.get("exception") or {}
    if exception.get("subtype"):
        parts.append(str(exception["subtype"]))
    termination = body.get("termination") or {}
    if termination.get("indicator"):
        parts.append(str(termination["indicator"]))
    for item in termination.get("reasons") or []:
        parts.append(str(item))
    for messages in (body.get("asi") or {}).values():
        parts.extend(str(message) for message in (messages if isinstance(messages, list) else [messages]))
    return "; ".join(parts) or "not in the report"


def parsed(path):
    """The summary lines of one .ips file, or None when it cannot be read as header line + JSON body."""
    with open(path, encoding="utf-8", errors="replace") as handle:
        text = handle.read()
    header, _, rest = text.partition("\n")
    json.loads(header)
    body = json.loads(rest)
    threads = body["threads"]
    crashed = body.get("faultingThread")
    if not isinstance(crashed, int):
        crashed = next(i for i, thread in enumerate(threads) if thread.get("triggered"))
    frames = threads[crashed]["frames"]
    images = body.get("usedImages") or []
    exception = body.get("exception") or {}
    kind = " ".join(str(exception[key]) for key in ("type", "signal") if exception.get(key)) or "not in the report"
    lines = ["- exception type: %s" % kind,
             "- reason: %s" % reason(body),
             "- crashed thread: %d" % crashed,
             "- first %d frames of the crashed thread (of %d):" % (min(FRAMES, len(frames)), len(frames)), ""]
    return lines + fence([frame_text(i, frame, images) for i, frame in enumerate(frames[:FRAMES])])


def main(folder):
    files = sorted(name for name in (os.listdir(folder) if os.path.isdir(folder) else [])
                   if os.path.isfile(os.path.join(folder, name)))
    out = ["## Crash reports of the app (R416, R423)", ""]
    if not files:
        out.append("No crash report of the app")
    for name in files:
        path = os.path.join(folder, name)
        out += ["### " + name, ""]
        lines = None
        if name.lower().endswith(".ips"):
            try:
                lines = parsed(path)
            except (ValueError, KeyError, IndexError, TypeError, StopIteration, OSError):
                lines = None
        if lines is None:
            why = "could not be read as a crash report's JSON" if name.lower().endswith(".ips") else "a text report"
            out += ["- %s; the first %d lines of the file:" % (why, FALLBACK_LINES), ""]
            lines = fence(first_lines(path))
        out += lines + [""]
    print("\n".join(out))


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else ".")
