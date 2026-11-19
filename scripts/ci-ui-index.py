#!/usr/bin/env python3
"""CI only (scripts/ci-ui-tests.sh, #24 A and D). Writes DEST/index.md for one screenshot artifact folder:

  - "TEST STOPPED BY THE TIME BUDGET: pictures up to <name>" first, when the budget stopped a test;
  - one row per test: result, seconds, pictures, seconds per picture;
  - counts against the plan (scripts/screenshot-plan.tsv) for the tests of this job: planned, taken, missing, failed
    (a NOT-REACHED note instead of the picture), warnings (-UNCHANGED notes) and pictures not in the plan;
  - every picture with its size, in viewing order;
  - the failed ones with their reason, the missing ones, the warnings;
  - the "fixed in code, verify in these screenshots" list (VERIFY in scripts/ci-screenshots-index.py).

Usage: ci-ui-index.py DEST PLAN.tsv RESULTS.tsv TEST...
DEST holds the pictures (NN-name.png or .jpg) and notes/ (NN-name-NOT-REACHED.txt, NN-name-UNCHANGED.txt, ...).
RESULTS.tsv: test<TAB>result<TAB>seconds<TAB>pictures, with a header line (written by ci-ui-tests.sh).
Exit status: 0 when DEST has at least one picture, 1 otherwise.
"""
import importlib.util
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
PICTURE = (".png", ".jpg", ".jpeg", ".heic")


def load_index_module():
    spec = importlib.util.spec_from_file_location("ci_screenshots_index", os.path.join(HERE, "ci-screenshots-index.py"))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def order(key):
    number, _, rest = key.partition("-")
    return (int(number) if number.isdigit() else 0, rest)


def size_text(n):
    return "%d KB" % max(1, round(n / 1024)) if n < 1024 * 1024 else "%.1f MB" % (n / 1048576)


def first_line(path):
    try:
        with open(path, encoding="utf-8", errors="replace") as fh:
            text = fh.read().strip()
    except OSError:
        return ""
    return text.splitlines()[0] if text else ""


def main():
    dest, plan_path, results_path, tests = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4:]
    plan = []  # (test, name) in plan order
    with open(plan_path, encoding="utf-8") as fh:
        for line in fh:
            if line.startswith("#") or not line.strip():
                continue
            test, name = line.rstrip("\n").split("\t")[:2]
            if test in tests:
                plan.append((test, name))
    results = []
    if os.path.exists(results_path):
        with open(results_path, encoding="utf-8") as fh:
            rows = [l.rstrip("\n").split("\t") for l in fh if l.strip()]
        results = [r for r in rows[1:] if len(r) >= 4]

    pictures = {}  # name without extension -> file name
    for f in sorted(os.listdir(dest)) if os.path.isdir(dest) else []:
        base, ext = os.path.splitext(f)
        if ext.lower() in PICTURE and os.path.isfile(os.path.join(dest, f)):
            pictures[base] = f
    notes_dir = os.path.join(dest, "notes")
    notes = set(os.listdir(notes_dir)) if os.path.isdir(notes_dir) else set()

    planned = [name for _, name in plan]
    taken = [n for n in planned if n in pictures]
    failed = [n for n in planned if n not in pictures and (n + "-NOT-REACHED.txt") in notes]
    missing = [n for n in planned if n not in pictures and n not in failed]
    # A picture can be taken AND have a NOT-REACHED note (72-files-folder: the picture, then the check after it failed).
    taken_but_failed = [n for n in taken if (n + "-NOT-REACHED.txt") in notes]
    warnings = sorted((f[:-len("-UNCHANGED.txt")] for f in notes if f.endswith("-UNCHANGED.txt")), key=order)
    extra = sorted((k for k in pictures if k not in planned), key=order)

    lines = ["# Screenshots: %s (viewing order)" % os.path.basename(os.path.normpath(dest)), ""]
    stopped = [r for r in results if r[1].startswith("stopped") or r[1].startswith("not started")]
    if stopped:
        first_stopped = stopped[0][0]
        before = [t for t in tests[: tests.index(first_stopped) + 1]] if first_stopped in tests else tests
        last = [n for t, n in plan if t in before and n in pictures]
        lines += ["**TEST STOPPED BY THE TIME BUDGET: pictures up to %s** (stopped in %s; not run: %s)." % (
            last[-1] if last else "(none)", first_stopped,
            ", ".join(r[0] for r in results if r[1].startswith("not started")) or "none"), ""]
    lines += ["Made by the UI tests in UITests/ScreenshotTests.swift on the tvOS Simulator, with the debug-only sample library",
              "(synthetic titles and generated pictures; OPEN_QUESTIONS R160). Not a device: colours, HDR and focus effects",
              "can differ on a real Apple TV. Each test ran as its own xcodebuild call; its pictures were copied right after it.", ""]
    lines += ["## Tests", "", "| Test | Result | Time | Pictures | Seconds per picture |", "|---|---|---|---|---|"]
    for t, result, secs, pics in (r[:4] for r in results):
        s, p = int(secs or 0), int(pics or 0)
        lines.append("| %s | %s | %d:%02d | %d | %s |" % (t, result, s // 60, s % 60, p, ("%.1f" % (s / p)) if p else "-"))
    lines += ["", "## Counts", "",
              "Planned: %d. Taken: %d. Missing: %d. Failed (not reached): %d. Warnings (unchanged): %d. Pictures not in the plan: %d." % (
                  len(planned), len(taken), len(missing), len(failed), len(warnings), len(extra)), ""]
    lines += ["## Pictures", ""]
    for key in sorted(pictures, key=order):
        size = os.path.getsize(os.path.join(dest, pictures[key]))
        mark = "" if key in planned else " (not in the plan)"
        lines.append("- [%s](%s) %s%s" % (key, pictures[key], size_text(size), mark))
    if not pictures:
        lines.append("- no picture")
    if failed or taken_but_failed:
        lines += ["", "## Failed: not reached", ""]
        for n in sorted(failed + taken_but_failed, key=order):
            lines.append("- %s: NOT REACHED. %s" % (n, first_line(os.path.join(notes_dir, n + "-NOT-REACHED.txt"))))
    if missing:
        lines += ["", "## Missing: planned, no picture and no note (the test did not get there)", ""]
        lines += ["- %s" % n for n in sorted(missing, key=order)]
    if warnings:
        lines += ["", "## Warnings", ""]
        lines += ["- WARNING: %s: %s" % (n, first_line(os.path.join(notes_dir, n + "-UNCHANGED.txt"))) for n in warnings]
    try:
        module = load_index_module()
        not_reached = {n: "" for n in failed}
        verify = module.verify_lines({k: pictures[k] for k in pictures}, not_reached, order)
    except Exception as error:  # the list is a help for the review, never a reason to lose the index
        verify = ["- (the verify list could not be built: %s)" % error]
    if verify:
        lines += ["", "## Fixed in code, verify in these screenshots", ""] + verify
    with open(os.path.join(dest, "index.md"), "w", encoding="utf-8") as fh:
        fh.write("\n".join(lines) + "\n")
    print("\n".join(lines))
    return 0 if pictures else 1


if __name__ == "__main__":
    sys.exit(main())
