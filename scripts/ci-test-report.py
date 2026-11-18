#!/usr/bin/env python3
"""CI only. Counts passed / skipped / failed test cases per test target from an xcodebuild test log and lists the failures.

Usage: ci-test-report.py <xcodebuild log> <output markdown>
Reads lines such as
  Test Case '-[LibraryIndexTests.FoundationTests testX]' passed (0.010 seconds).
  Test case 'FoundationTests.testX()' failed on 'Clone 1 of ...' (0.010 seconds)
  /path/File.swift:12: error: -[LibraryIndexTests.FoundationTests testX] : XCTAssertEqual failed ...
A report only, never a gate: the exit status is always 0.
"""
import collections
import re
import sys

CASE = re.compile(r"Test [Cc]ase '-?\[?(?:(?P<mod>[\w]+)\.)?(?P<cls>\w+)[ .](?P<test>\w+)(?:\(\))?\]?' (?P<res>passed|failed|skipped)")
FAILURE = re.compile(r"^(?P<loc>/[^:]+:\d+): error: -\[(?P<mod>\w+)\.(?P<cls>\w+) (?P<test>\w+)\] : (?P<msg>.*)$")


def main():
    log, out = sys.argv[1], sys.argv[2]
    counts = collections.defaultdict(lambda: collections.Counter())
    failures = []
    seen = set()
    try:
        lines = open(log, encoding="utf-8", errors="replace").read().splitlines()
    except FileNotFoundError:
        lines = []
    for line in lines:
        m = CASE.search(line)
        if m:
            key = (m.group("mod") or "?", m.group("cls"), m.group("test"))
            if (key, m.group("res")) in seen:
                continue
            seen.add((key, m.group("res")))
            counts[key[0] if key[0] != "?" else m.group("cls")][m.group("res")] += 1
            continue
        f = FAILURE.match(line)
        if f:
            failures.append("%s.%s.%s  %s  (%s)" % (f.group("mod"), f.group("cls"), f.group("test"), f.group("msg")[:300], f.group("loc")))
    total = collections.Counter()
    rows = []
    for target in sorted(counts):
        c = counts[target]
        total.update(c)
        rows.append("| %s | %d | %d | %d |" % (target, c["passed"], c["skipped"], c["failed"]))
    with open(out, "w", encoding="utf-8") as fh:
        fh.write("## Package tests on the tvOS Simulator (report only, not a gate)\n\n")
        fh.write("| Test target | Passed | Skipped | Failed |\n|---|---|---|---|\n")
        fh.write("\n".join(rows) + ("\n" if rows else "| (no test results found in the log) | 0 | 0 | 0 |\n"))
        fh.write("| **Total** | **%d** | **%d** | **%d** |\n\n" % (total["passed"], total["skipped"], total["failed"]))
        fh.write("### Failures (%d)\n\n" % len(failures))
        fh.write("\n".join("- " + f for f in failures) + ("\n" if failures else "None found in the log.\n"))
    print(open(out, encoding="utf-8").read())
    return 0


if __name__ == "__main__":
    sys.exit(main())
