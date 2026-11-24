#!/usr/bin/env python3
"""GitHub Actions TestFlight workflow only (.github/workflows/testflight.yml; OPEN_QUESTIONS R466 and R467, PROVISIONAL,
NEVER RUN ON A MAC). A READ-ONLY look at what the archived app and its Top Shelf extension are actually signed with, before
the export and the upload. R466: build 202611242205 crashed at launch inside CloudKit; the first thing to rule out is that
the signed app lacks the iCloud container or the CloudKit service.

  gh-entitlement-check.py bundles APP.app [TOPSHELF.appex]
        on the Mac: reads each bundle's signed entitlements, in this order, and stops at the first form that gives a plist:
          1. `codesign -d --entitlements :- BUNDLE`            (source word: codesign)
          2. `codesign -d --entitlements - --xml BUNDLE`       (source word: codesign)
          3. BUNDLE/archived-expanded-entitlements.xcent       (source word: xcent; Xcode writes the final entitlements of
                                                                an archived app into this file)
        and its embedded provisioning profile (`security cms -D -i BUNDLE/embedded.mobileprovision`)
  gh-entitlement-check.py plists APP_SIGNED APP_PROFILE TOPSHELF_SIGNED TOPSHELF_PROFILE
        the same checks on four decoded plist files (the Linux self-test, scripts/test-ci-testflight-log.sh)

Prints ONLY the key names (Apple's public names) with `yes` or `no`: never a value, an identifier, a Team ID, a certificate
or any text of a plist or of a command's output (the repository is public and so is the log).
EXIT CODE (R467): 1 only when the app's signed entitlements WERE read and lack the iCloud container or the CloudKit service.
When no form can read them (run #5 of the TestFlight workflow: all four reads printed n/a) the keys print `n/a`, ONE
WARNING line says the check could not run, only safe facts are printed (the exit codes of codesign, whether
embedded.mobileprovision and archived-expanded-entitlements.xcent exist as yes or no, and the bundle's top-level file names
that are on a fixed safe list; any other name is only counted), and the exit code is 0, so the export and the upload go on.
An unreadable check is NOT a pass: the last line says so. A readable embedded profile that lacks the container or the
service is a WARNING line, not a failure. The Top Shelf extension is only reported (it has no iCloud by design, project.yml).
Standard library only.
"""
import importlib.util
import os
import plistlib
import re
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))


def _constants():
    """The container and App Group names come from cm-profile-check.py, the one place that holds them."""
    spec = importlib.util.spec_from_file_location("cm_profile_check", os.path.join(HERE, "cm-profile-check.py"))
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


C = _constants()
CLOUDKIT = "CloudKit"
SERVICES_KEY = "com.apple.developer.icloud-services"
XCENT = "archived-expanded-entitlements.xcent"
PROFILE_FILE = "embedded.mobileprovision"
KEYS = [
    ("icloud-container-identifiers", C.ICLOUD_KEY),
    ("icloud-services (CloudKit)", SERVICES_KEY),
    ("application-groups", C.GROUP_KEY),
    ("aps-environment", C.APS_KEY),
]

# Top-level names of a bundle that may be printed when nothing can be read: the names the repository's scripts already
# use for these bundles (Info.plist, PlugIns, *.appex: cm-testflight.sh, ci-inspect-*.sh; embedded.mobileprovision and the
# .xcent file: this script) and the usual resource folders. A name is printed only if it is on this list or ends in one of
# these suffixes AND does not look like it carries an identifier; every other name is only counted (R467).
SAFE_NAMES = {"Info.plist", "PkgInfo", PROFILE_FILE, XCENT, "_CodeSignature", "Frameworks", "PlugIns", "Assets.car"}
SAFE_SUFFIXES = (".lproj", ".bundle", ".storyboardc", ".nib", ".car", ".appex", ".framework")
LOOKS_LIKE_ID = re.compile(r"[A-Z0-9]{10}|[0-9A-Fa-f]{32}|[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-|[@\s:]")
MAX_NAMES = 30


def _as_list(value):
    if value is None:
        return []
    return list(value) if isinstance(value, (list, tuple)) else [value]


def has_key(ent, key, profile):
    """True/False for one key of an entitlements dictionary (a signed app's, or a profile's `Entitlements`)."""
    ent = ent or {}
    value = ent.get(key)
    if key == C.ICLOUD_KEY:
        return C.ICLOUD_CONTAINER in _as_list(value)
    if key == SERVICES_KEY:
        # A profile may carry the wildcard string for the services; a signed app carries the list.
        return CLOUDKIT in _as_list(value) or (profile and value == "*")
    if key == C.GROUP_KEY:
        return C.APP_GROUP in _as_list(value)
    if key == C.APS_KEY:
        return value == "production"
    return False


def parse_signed(raw):
    """The plist inside `codesign -d --entitlements` output (the XML text, with anything around it ignored)."""
    start = raw.find(b"<?xml")
    end = raw.rfind(b"</plist>")
    if start < 0 or end < 0:
        return None
    try:
        parsed = plistlib.loads(raw[start:end + len(b"</plist>")])
    except Exception:
        return None
    return parsed if isinstance(parsed, dict) else None


def read_xcent(bundle):
    """The entitlements Xcode wrote into the archived app (XML or binary plist), or None."""
    try:
        with open(os.path.join(bundle, XCENT), "rb") as f:
            parsed = plistlib.load(f)
    except Exception:
        return None
    return parsed if isinstance(parsed, dict) else None


def read_signed(bundle):
    """(entitlements or None, source word 'codesign' or 'xcent' or None, list of codesign exit codes as text)."""
    codes = []
    for form in (["codesign", "-d", "--entitlements", ":-", bundle], ["codesign", "-d", "--entitlements", "-", "--xml", bundle]):
        try:
            p = subprocess.run(form, capture_output=True)
        except OSError:
            codes.append("not-run")
            continue
        codes.append(str(p.returncode))
        # The plist is on stdout; stderr is looked at too, but nothing of either is ever printed.
        ent = parse_signed(p.stdout)
        if ent is None:
            ent = parse_signed(p.stderr)
        if ent is not None:
            return ent, "codesign", codes
    ent = read_xcent(bundle)
    return ent, ("xcent" if ent is not None else None), codes


def read_profile(bundle):
    path = os.path.join(bundle, PROFILE_FILE)
    if not os.path.isfile(path):
        return None
    try:
        p = subprocess.run(["security", "cms", "-D", "-i", path], capture_output=True)
        if p.returncode != 0 or not p.stdout:
            return None
        return (plistlib.loads(p.stdout).get("Entitlements")) or {}
    except Exception:
        return None


def safe_names(bundle):
    """(names that may be printed, count of the names that are not shown). File NAMES only, never contents."""
    try:
        names = sorted(os.listdir(bundle))
    except OSError:
        return [], 0
    own = os.path.splitext(os.path.basename(bundle.rstrip("/\\")))[0]
    shown = []
    for n in names:
        listed = n in SAFE_NAMES or n == own or n.endswith(SAFE_SUFFIXES)
        if listed and len(n) <= 48 and not (LOOKS_LIKE_ID.search(n) and n not in SAFE_NAMES and n != own):
            shown.append(n)
    shown = shown[:MAX_NAMES]
    return shown, len(names) - len(shown)


def facts_of(bundle, codes):
    """Safe facts about a bundle whose signed entitlements could not be read: no value, no content."""
    shown, hidden = safe_names(bundle)
    return {"codes": codes,
            "profile_file": os.path.isfile(os.path.join(bundle, PROFILE_FILE)),
            "xcent_file": os.path.isfile(os.path.join(bundle, XCENT)),
            "names": shown, "hidden": hidden}


def read_bundle(bundle):
    ent, how, codes = read_signed(bundle)
    return {"signed": ent, "how": how, "profile": read_profile(bundle),
            "facts": None if ent is not None else facts_of(bundle, codes)}


def yn(flag):
    return "yes" if flag else "no"


def report(app, top, top_present=True):
    """Prints the yes/no table and returns the exit code (1 only when the app's signed entitlements were read and lack the
    iCloud container or the CloudKit service). `app` and `top` are dicts: signed, how, profile, facts."""
    print("ENTITLEMENT CHECK (read-only; yes or no only, never a value). The Top Shelf extension has no iCloud by design.")
    failures, warnings = [], []
    undecided = False
    for label, b, is_app in (("app", app, True), ("topshelf", top, False)):
        if label == "topshelf" and not top_present:
            print("  topshelf: no extension found in the archive")
            continue
        for source, ent in (("signed", b["signed"]), ("profile", b["profile"])):
            if ent is None:
                print("  %-8s %-7s all keys n/a (could not be read)" % (label, source))
                if is_app and source == "signed":
                    undecided = True
                continue
            print("  %-8s %-7s source %s" % (label, source, (b["how"] or "codesign") if source == "signed" else "profile"))
            for name, key in KEYS:
                yes = bool(has_key(ent, key, profile=(source == "profile")))
                print("  %-8s %-7s %-30s %s" % (label, source, name, yn(yes)))
                if is_app and key in (C.ICLOUD_KEY, SERVICES_KEY) and not yes:
                    what = "the iCloud container" if key == C.ICLOUD_KEY else "the CloudKit service"
                    if source == "signed":
                        failures.append("the signed entitlements of the app lack " + what)
                    else:
                        warnings.append("the embedded profile of the app lacks " + what)
        f = b.get("facts")
        if f:
            names = ", ".join(f["names"]) if f["names"] else "none shown"
            print("  %-8s facts   codesign exit codes %s; %s %s; %s %s; top-level names: %s (+%d other names, not shown)"
                  % (label, ",".join(f["codes"]) or "none", PROFILE_FILE, yn(f["profile_file"]), XCENT, yn(f["xcent_file"]),
                     names, f["hidden"]))
    for w in warnings:
        print("WARNING: " + w)
    if undecided:
        print("WARNING: the signed entitlements of the app could not be read by any form (codesign, then the .xcent file); "
              "the check could not run, so nothing was verified; the export and the upload go on (R467).")
    for f in failures:
        print("ENTITLEMENT ERROR: " + f)
    if failures:
        print("ENTITLEMENT ERROR: the app would call CloudKit without it (R466); nothing was exported or uploaded. "
              "Where it comes from: project.yml (entitlements, generated into App/VideoPlayer.entitlements) and the App Store profile "
              "(developer.apple.com > Identifiers > the App ID > iCloud).")
        return 1
    if undecided:
        print("ENTITLEMENT CHECK: not decided (n/a); this is NOT a pass")
        return 0
    print("ENTITLEMENT CHECK: the app is signed with the iCloud container and the CloudKit service")
    return 0


def main(argv):
    if len(argv) == 6 and argv[1] == "plists":
        loaded = []
        for p in argv[2:6]:
            with open(p, "rb") as f:
                loaded.append(plistlib.load(f))
        # Files 2 and 4 are whole decoded profiles: only their Entitlements dictionary is read.
        app = {"signed": loaded[0], "how": "codesign", "profile": loaded[1].get("Entitlements") or {}, "facts": None}
        top = {"signed": loaded[2], "how": "codesign", "profile": loaded[3].get("Entitlements") or {}, "facts": None}
        return report(app, top)
    if len(argv) in (3, 4) and argv[1] == "bundles":
        topb = argv[3] if len(argv) == 4 and argv[3] else None
        return report(read_bundle(argv[2]), read_bundle(topb) if topb else {"signed": None, "profile": None, "how": None, "facts": None},
                      top_present=bool(topb))
    print(__doc__)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))
