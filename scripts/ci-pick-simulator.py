#!/usr/bin/env python3
"""CI only. Picks an available tvOS simulator from `xcrun simctl list devices available -j` (read on stdin) and prints
its UDID on stdout. Every runtime found, every candidate, the choice and the reason go to stderr (the log). No UDID is
hard-coded.

    ci-pick-simulator.py [--sdk 27.2] [--exclude-runtime KEY ...] [--runtime-out FILE]

Order (#21 A): the RUNTIME first, then the device name.
  1. The runtime whose version equals the Simulator SDK (--sdk, e.g. 27.2 from appletvsimulator27.2), then the newest
     other runtime. An older runtime is used only when no newer one is available. A runtime given with
     --exclude-runtime (one that failed to load in this job) is never picked.
  2. On that runtime: Apple TV 4K (3rd generation) (at 1080p), Apple TV 4K (4th generation) (at 1080p), any other
     "Apple TV 4K ... (at 1080p)", then the same without "(at 1080p)", then any Apple TV.
Run 44424319207 picked the 3rd generation on tvOS 27.0 (the name came first), whose runtime bundle then failed to load,
although tvOS 27.2 was there; this order picks 27.2.
--runtime-out FILE receives the chosen runtime's key, so scripts/ci-sim.sh can exclude it if it fails to load.
"""
import argparse
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
    m = re.search(r"tvOS-(\d+)-(\d+)(?:-(\d+))?", key)
    return tuple(int(g or 0) for g in m.groups()) if m else (0, 0, 0)


def version_text(v):
    return "%d.%d" % v[:2] + (".%d" % v[2] if v[2] else "")


def sdk_version(text):
    m = re.search(r"(\d+)\.(\d+)(?:\.(\d+))?", text or "")
    return tuple(int(g or 0) for g in m.groups()) if m else None


def name_rank(name):
    if name in PREFERRED:
        return PREFERRED.index(name)
    if name.startswith("Apple TV 4K") and name.endswith("(at 1080p)"):
        return len(PREFERRED)
    if name.startswith("Apple TV 4K"):
        return len(PREFERRED) + 1
    return len(PREFERRED) + 2


def main(argv=None):
    ap = argparse.ArgumentParser()
    ap.add_argument("--sdk", default="")
    ap.add_argument("--exclude-runtime", action="append", default=[])
    ap.add_argument("--runtime-out", default="")
    args = ap.parse_args(argv)
    sdk = sdk_version(args.sdk)
    log = lambda s: print(s, file=sys.stderr)

    data = json.load(sys.stdin)
    runtimes = {}
    for runtime, devices in data.get("devices", {}).items():
        if "tvOS" not in runtime:
            continue
        usable = [d for d in devices if d.get("isAvailable", True)]
        runtimes[runtime] = usable
    log("SDK: %s" % (version_text(sdk) if sdk else "not given"))
    for runtime in sorted(runtimes, key=runtime_version, reverse=True):
        state = "EXCLUDED (failed to load in this job)" if runtime in args.exclude_runtime else "%d device(s)" % len(runtimes[runtime])
        log("runtime found: tvOS %s | %s | %s" % (version_text(runtime_version(runtime)), runtime, state))
        for d in runtimes[runtime]:
            log("  available: %s | %s" % (d["name"], d["udid"]))

    usable = {r: ds for r, ds in runtimes.items() if ds and r not in args.exclude_runtime}
    if not usable:
        log("::error::no available tvOS simulator%s" % (" on a runtime that has not failed" if args.exclude_runtime else ""))
        return 1

    def runtime_rank(r):
        v = runtime_version(r)
        return (0 if sdk and v[:2] == sdk[:2] else 1, tuple(-x for x in v))

    runtime = sorted(usable, key=runtime_rank)[0]
    v = runtime_version(runtime)
    if sdk and v[:2] == sdk[:2]:
        why = "it matches the Simulator SDK %s" % version_text(sdk)
    elif sdk and v[:2] > sdk[:2]:
        why = "no runtime matches the SDK %s; this is the newest" % version_text(sdk)
    elif sdk:
        why = "no runtime matches the SDK %s and none is newer; older runtime used" % version_text(sdk)
    else:
        why = "newest runtime"
    if args.exclude_runtime:
        why += "; excluded: %s" % ", ".join(args.exclude_runtime)
    device = sorted(usable[runtime], key=lambda d: name_rank(d["name"]))[0]
    log("chosen: tvOS %s | %s | %s | %s" % (version_text(v), runtime, device["name"], device["udid"]))
    log("why: runtime: %s; device: the first preferred name on it" % why)
    if args.runtime_out:
        with open(args.runtime_out, "w") as f:
            f.write(runtime + "\n")
    print(device["udid"])
    return 0


if __name__ == "__main__":
    sys.exit(main())
