#!/usr/bin/env python3
"""Codemagic only (codemagic.yaml, OPEN_QUESTIONS R266). Before the archive: the App Store profiles must carry the
capabilities project.yml asks for, or the archive fails later with a less clear message.

  cm-profile-check.py installed             reads the profiles installed on this machine (the folders the Codemagic CLI
                                            saves to), picks each target's App Store profile and checks it
  cm-profile-check.py dir DIR               the same for the profiles in DIR (the two the signing step chose)
  cm-profile-check.py plists APP TOPSHELF   checks two decoded profile plists (the Linux self-test)

Checked: the app's profile has the iCloud container iCloud.com.liamp.videoplayer and the App Group
group.com.liamp.videoplayer; the Top Shelf profile has the App Group. A missing one stops the build with one line per
capability, naming the App ID and where to fix it on developer.apple.com. Prints only result lines: never the profile's
content, certificates, serial numbers or names. Standard library only (python3 is on Codemagic's macOS image).
"""
import glob
import os
import plistlib
import shutil
import subprocess
import sys

APP_ID = "com.liamp.videoplayer"
TOPSHELF_ID = "com.liamp.videoplayer.topshelf"
ICLOUD_CONTAINER = "iCloud.com.liamp.videoplayer"
APP_GROUP = "group.com.liamp.videoplayer"
ICLOUD_KEY = "com.apple.developer.icloud-container-identifiers"
GROUP_KEY = "com.apple.security.application-groups"
PROFILE_DIRS = ("Library/MobileDevice/Provisioning Profiles", "Library/Developer/Xcode/UserData/Provisioning Profiles")


def missing_capabilities(app_plist, topshelf_plist):
    """One line per missing capability: which one, on which App ID, and where to fix it."""
    app = (app_plist or {}).get("Entitlements") or {}
    top = (topshelf_plist or {}).get("Entitlements") or {}
    out = []
    if ICLOUD_CONTAINER not in (app.get(ICLOUD_KEY) or []):
        out.append("iCloud container %s is missing on the App ID %s (developer.apple.com > Identifiers > %s > iCloud > "
                   "Configure: tick %s, Save)" % (ICLOUD_CONTAINER, APP_ID, APP_ID, ICLOUD_CONTAINER))
    if APP_GROUP not in (app.get(GROUP_KEY) or []):
        out.append("App Group %s is missing on the App ID %s (developer.apple.com > Identifiers > %s > App Groups > "
                   "Configure: tick %s, Save)" % (APP_GROUP, APP_ID, APP_ID, APP_GROUP))
    if APP_GROUP not in (top.get(GROUP_KEY) or []):
        out.append("App Group %s is missing on the App ID %s (developer.apple.com > Identifiers > %s > App Groups > "
                   "Configure: tick %s, Save)" % (APP_GROUP, TOPSHELF_ID, TOPSHELF_ID, APP_GROUP))
    return out


def bundle_id_of(plist):
    """The bundle ID from the application-identifier entitlement (TEAMID.bundle.id), or None."""
    aid = ((plist or {}).get("Entitlements") or {}).get("application-identifier", "")
    return aid.split(".", 1)[1] if "." in aid else None


def is_app_store(plist):
    """An App Store profile lists no devices, does not cover all devices and does not allow debugging."""
    ent = plist.get("Entitlements") or {}
    return not plist.get("ProvisionedDevices") and not plist.get("ProvisionsAllDevices") and not ent.get("get-task-allow")


def decode(path):
    """The plist inside a signed profile: `security cms -D` on macOS, `openssl cms` elsewhere (the self-test)."""
    if shutil.which("security"):
        p = subprocess.run(["security", "cms", "-D", "-i", path], capture_output=True)
    else:
        p = subprocess.run(["openssl", "cms", "-verify", "-noverify", "-inform", "DER", "-in", path], capture_output=True)
    if p.returncode != 0 or not p.stdout:
        return None
    try:
        return plistlib.loads(p.stdout)
    except Exception:
        return None


def installed_profiles(home, dirs=None):
    found = {}
    for folder in (dirs if dirs is not None else [os.path.join(home, rel) for rel in PROFILE_DIRS]):
        for path in sorted(glob.glob(os.path.join(folder, "*.mobileprovision"))):
            plist = decode(path)
            if not plist or not is_app_store(plist):
                continue
            bid = bundle_id_of(plist)
            if bid not in (APP_ID, TOPSHELF_ID):
                continue
            created = plist.get("CreationDate")
            old = found.get(bid)
            if old is None or (created and old.get("CreationDate") and created > old["CreationDate"]):
                found[bid] = plist
    return found


def report(app_plist, topshelf_plist):
    missing = missing_capabilities(app_plist, topshelf_plist)
    for m in missing:
        print("PROFILE CHECK ERROR: MISSING CAPABILITY: " + m)
    if missing:
        print("PROFILE CHECK ERROR: %d capability(ies) missing; fix them on developer.apple.com, then start a new build "
              "(docs/TESTFLIGHT.md, Codemagic route)" % len(missing))
        return 1
    print("PROFILE CHECK: %s has %s and %s; %s has %s" % (APP_ID, ICLOUD_CONTAINER, APP_GROUP, TOPSHELF_ID, APP_GROUP))
    return 0


def main(argv):
    if len(argv) == 4 and argv[1] == "plists":
        loaded = []
        for p in argv[2:4]:
            with open(p, "rb") as f:
                loaded.append(plistlib.load(f))
        return report(*loaded)
    if (len(argv) == 2 and argv[1] == "installed") or (len(argv) == 3 and argv[1] == "dir"):
        found = installed_profiles(os.path.expanduser("~"), [argv[2]] if argv[1] == "dir" else None)
        absent = [b for b in (APP_ID, TOPSHELF_ID) if b not in found]
        for b in absent:
            print("PROFILE CHECK ERROR: no App Store profile for %s is installed on this machine (the signing step "
                  "should have saved it)" % b)
        if absent:
            return 1
        print("PROFILE CHECK: App Store profiles found for %s and %s" % (APP_ID, TOPSHELF_ID))
        return report(found[APP_ID], found[TOPSHELF_ID])
    print(__doc__)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))
