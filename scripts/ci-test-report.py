#!/usr/bin/env python3
"""CI only. Counts passed / skipped / failed test cases per test target from an xcodebuild test log and lists the failures.

Usage: ci-test-report.py <xcodebuild log> <output markdown> [TITLE]
TITLE (#24 D): the heading; default "Package tests on the tvOS Simulator". The UI-test jobs pass "UI tests and screenshots".
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


RUNTIME = re.compile(r"Failed to load requested runtime bundle|Failed to prepare device")


def no_tests_cause(lines):
    """The first log line that says the simulator runtime failed (shortened), or None."""
    for line in lines:
        if RUNTIME.search(line):
            return line.strip()[:400]
    return None


def main():
    log, out = sys.argv[1], sys.argv[2]
    title = sys.argv[3] if len(sys.argv) > 3 else "Package tests on the tvOS Simulator"
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
        fh.write("## %s (report only, not a gate)\n\n" % title)
        # #21 A: zero tests is never shown as only an empty table. The cause line comes first.
        if sum(total.values()) == 0 and not counts:
            cause = no_tests_cause(lines)
            if cause:
                fh.write("**NO TESTS RAN: simulator runtime failed to load**\n\nCause: `%s`\n\n" % cause)
            elif lines:
                fh.write("**NO TESTS RAN** (the log has no test result; see its last lines)\n\n```\n%s\n```\n\n"
                         % "\n".join(lines[-8:]))
            else:
                fh.write("**NO TESTS RAN** (no test log was written)\n\n")
        fh.write("| Test target | Passed | Skipped | Failed |\n|---|---|---|---|\n")
        fh.write("\n".join(rows) + ("\n" if rows else "| (no test results found in the log) | 0 | 0 | 0 |\n"))
        fh.write("| **Total** | **%d** | **%d** | **%d** |\n\n" % (total["passed"], total["skipped"], total["failed"]))
        fh.write("### Failures (%d)\n\n" % len(failures))
        fh.write("\n".join("- " + f for f in failures) + ("\n" if failures else "None found in the log.\n"))
    print(open(out, encoding="utf-8").read())
    return 0


if __name__ == "__main__":
    sys.exit(main())
