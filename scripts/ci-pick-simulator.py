#!/usr/bin/env python3
"""CI only. Picks an available tvOS simulator by NAME from `xcrun simctl list devices available -j` (read on stdin) and
prints its UDID on stdout; the choice and every candidate go to stderr (the log). No UDID is hard-coded.

Preference (screenshots at 1920x1080 first): Apple TV 4K (3rd generation) (at 1080p), Apple TV 4K (4th generation) (at 1080p),
any other "Apple TV 4K ... (at 1080p)", then the same without "(at 1080p)", then any Apple TV. Newest tvOS runtime first.
"""
import json
import re
import sys

PREFERRED = [
    "Apple TV 4K (3rd generation) (at 1080p)",
    "Apple TV 4K (4th generation) (at 1080p)",
    "Apple TV 4K (3rd generation)",
    "Apple TV 4K (4th generation)",
]


def runtime_version(key):
    m = re.search(r"tvOS-(\d+)-(\d+)", key)
    return (int(m.group(1)), int(m.group(2))) if m else (0, 0)


def main():
    data = json.load(sys.stdin)
    candidates = []
    for runtime, devices in data.get("devices", {}).items():
        if "tvOS" not in runtime:
            continue
        for d in devices:
            if d.get("isAvailable", True):
                candidates.append((runtime, d["name"], d["udid"]))
    for c in candidates:
        print("available: %s | %s | %s" % c, file=sys.stderr)
    if not candidates:
        print("::error::no available tvOS simulator", file=sys.stderr)
        return 1

    def rank(c):
        runtime, name, _ = c
        if name in PREFERRED:
            first = PREFERRED.index(name)
        elif name.startswith("Apple TV 4K") and name.endswith("(at 1080p)"):
            first = len(PREFERRED)
        elif name.startswith("Apple TV 4K"):
            first = len(PREFERRED) + 1
        else:
            first = len(PREFERRED) + 2
        v = runtime_version(runtime)
        return (first, -v[0], -v[1])

    best = sorted(candidates, key=rank)[0]
    print("chosen: %s | %s | %s" % best, file=sys.stderr)
    print(best[2])
    return 0


if __name__ == "__main__":
    sys.exit(main())
