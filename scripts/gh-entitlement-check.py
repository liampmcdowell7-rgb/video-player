#!/usr/bin/env python3
"""GitHub Actions TestFlight workflow only (.github/workflows/testflight.yml; OPEN_QUESTIONS R466, PROVISIONAL, NEVER RUN ON
A MAC). A READ-ONLY look at what the archived app and its Top Shelf extension are actually signed with, before the export
and the upload. R466: build 202611242205 crashed at launch inside CloudKit; the first thing to rule out is that the signed
app lacks the iCloud container or the CloudKit service.

  gh-entitlement-check.py bundles APP.app [TOPSHELF.appex]
        on the Mac: reads each bundle's signed entitlements (`codesign -d --entitlements :-`) and its embedded provisioning
        profile (`security cms -D -i BUNDLE/embedded.mobileprovision`)
  gh-entitlement-check.py plists APP_SIGNED APP_PROFILE TOPSHELF_SIGNED TOPSHELF_PROFILE
        the same checks on four decoded plist files (the Linux self-test, scripts/test-ci-testflight-log.sh)

Prints ONLY the key names (Apple's public names) with `yes` or `no`: never a value, an identifier, a Team ID, a certificate
or any text of a plist or of a command's output (the repository is public and so is the log). Exit 1, with one ERROR line,
when the APP
  - lacks the iCloud container in its signed entitlements, or lacks the CloudKit service there, or
  - has a READABLE embedded profile that lacks either.
An unreadable or missing embedded profile is printed as `n/a` and does not fail the step (only the signed entitlements decide
then): the profile's place inside a tvOS bundle is UNVERIFIED. The Top Shelf extension is only reported (it has no iCloud by
design, project.yml). Standard library only.
"""
import importlib.util
import os
import plistlib
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
KEYS = [
    ("icloud-container-identifiers", C.ICLOUD_KEY),
    ("icloud-services (CloudKit)", SERVICES_KEY),
    ("application-groups", C.GROUP_KEY),
    ("aps-environment", C.APS_KEY),
]


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
    """The plist inside `codesign -d --entitlements :-` output (the XML text, with anything around it ignored)."""
    start = raw.find(b"<?xml")
    end = raw.rfind(b"</plist>")
    if start < 0 or end < 0:
        return None
    try:
        return plistlib.loads(raw[start:end + len(b"</plist>")])
    except Exception:
        return None


def read_signed(bundle):
    try:
        p = subprocess.run(["codesign", "-d", "--entitlements", ":-", bundle], capture_output=True)
    except OSError:
        return None
    return parse_signed(p.stdout) if p.returncode == 0 else None


def read_profile(bundle):
    path = os.path.join(bundle, "embedded.mobileprovision")
    if not os.path.isfile(path):
        return None
    try:
        p = subprocess.run(["security", "cms", "-D", "-i", path], capture_output=True)
        if p.returncode != 0 or not p.stdout:
            return None
        return (plistlib.loads(p.stdout).get("Entitlements")) or {}
    except Exception:
        return None


def report(app_signed, app_profile, top_signed, top_profile, top_present=True):
    """Prints the yes/no table and returns the exit code (1 when the app lacks the iCloud container or CloudKit)."""
    print("ENTITLEMENT CHECK (read-only; yes or no only, never a value). The Top Shelf extension has no iCloud by design.")
    failures = []
    for label, signed, profile, is_app in (("app", app_signed, app_profile, True),
                                           ("topshelf", top_signed, top_profile, False)):
        if label == "topshelf" and not top_present:
            print("  topshelf: no extension found in the archive")
            continue
        for source, ent in (("signed", signed), ("profile", profile)):
            if ent is None:
                print("  %-8s %-7s all keys n/a (could not be read)" % (label, source))
                if is_app and source == "signed":
                    failures.append("the signed entitlements of the app could not be read")
                continue
            for name, key in KEYS:
                yes = bool(has_key(ent, key, profile=(source == "profile")))
                print("  %-8s %-7s %-30s %s" % (label, source, name, "yes" if yes else "no"))
                if is_app and key in (C.ICLOUD_KEY, SERVICES_KEY) and not yes:
                    what = "the iCloud container" if key == C.ICLOUD_KEY else "the CloudKit service"
                    failures.append(("the signed entitlements of the app lack " if source == "signed"
                                     else "the embedded profile of the app lacks ") + what)
    for f in failures:
        print("ENTITLEMENT ERROR: " + f)
    if failures:
        print("ENTITLEMENT ERROR: the app would call CloudKit without it (R466); nothing was exported or uploaded. "
              "Where it comes from: project.yml (entitlements, generated into App/VideoPlayer.entitlements) and the App Store profile "
              "(developer.apple.com > Identifiers > the App ID > iCloud).")
        return 1
    print("ENTITLEMENT CHECK: the app is signed with the iCloud container and the CloudKit service")
    return 0


def main(argv):
    if len(argv) == 6 and argv[1] == "plists":
        loaded = []
        for p in argv[2:6]:
            with open(p, "rb") as f:
                loaded.append(plistlib.load(f))
        # Files 2 and 4 are whole decoded profiles: only their Entitlements dictionary is read.
        loaded[1] = loaded[1].get("Entitlements") or {}
        loaded[3] = loaded[3].get("Entitlements") or {}
        return report(*loaded)
    if len(argv) in (3, 4) and argv[1] == "bundles":
        app = argv[2]
        top = argv[3] if len(argv) == 4 and argv[3] else None
        return report(read_signed(app), read_profile(app),
                      read_signed(top) if top else None, read_profile(top) if top else None, top_present=bool(top))
    print(__doc__)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))
