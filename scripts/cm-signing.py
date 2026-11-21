#!/usr/bin/env python3
"""Codemagic only (codemagic.yaml, OPEN_QUESTIONS R266). Helpers for the signing step of scripts/cm-testflight.sh. They
read files the Codemagic CLI wrote and never call a server themselves. NOTHING HERE MAKES, REVOKES OR DELETES A
CERTIFICATE OR A KEY: the certificate is the owner's stored distribution certificate, which Codemagic installs by type
and bundle identifier (codemagic.yaml ios_signing: distribution_type app_store, bundle_identifier).

  cm-signing.py cert-id CERTS_JSON IDENTITIES CERT_ID_OUT CERT_SHA1_OUT
      CERTS_JSON: `app-store-connect certificates list --json`; IDENTITIES: `security find-identity -v -p codesigning`.
      Finds the ONE App Store Connect certificate whose SHA-1 (of its DER content) is a signing identity in this
      machine's keychain, i.e. the certificate ios_signing installed, and writes its resource ID and SHA-1.
  cm-signing.py bundle-rid BUNDLE_JSON IDENTIFIER OUT
      BUNDLE_JSON: `app-store-connect bundle-ids list --bundle-id-identifier ID --strict-match-identifier --json`.
      Writes the resource ID of the one Bundle ID with exactly that identifier.
  cm-signing.py profile-ids PROFILES_JSON OUT
      PROFILES_JSON: `app-store-connect bundle-ids profiles ... --json`. Writes one profile resource ID per line (maybe none).
  cm-signing.py pick DIR IDENTIFIER CERT_SHA1_FILE OUT_DIR
      Among the profile files in DIR, picks the App Store tvOS profile for IDENTIFIER that contains the certificate and is
      valid for at least one more day (the one that expires last), and copies it to OUT_DIR/<UUID>.mobileprovision.
      Exit 0 found, 3 none found (the caller may then create a profile), 1 error.

Prints only result lines: never a resource ID, certificate, serial number, profile content or a holder's name.
The CLI's JSON layout is UNVERIFIED (its docs give only "--json: Whether to show the resource in JSON format"), so the
readers accept a list or {"data": [...]} and fields at the top level or under "attributes", camelCase or snake_case.
Standard library only.
"""
import base64
import datetime
import glob
import hashlib
import importlib.util
import json
import os
import re
import shutil
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
_spec = importlib.util.spec_from_file_location("cm_profile_check", os.path.join(HERE, "cm-profile-check.py"))
pc = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(pc)

NOT_FOUND = 3


def resources(path):
    with open(path, "rb") as f:
        data = json.loads(f.read().decode("utf-8") or "[]")
    if isinstance(data, dict):
        data = data.get("data", [data])
    return [r for r in data if isinstance(r, dict)] if isinstance(data, list) else []


def field(res, camel):
    snake = re.sub(r"([A-Z])", lambda m: "_" + m.group(1).lower(), camel)
    for d in (res.get("attributes") or {}, res):
        for k in (camel, snake):
            if isinstance(d, dict) and d.get(k) not in (None, ""):
                return d[k]
    return None


def parse_date(value):
    if isinstance(value, datetime.datetime):
        return value if value.tzinfo else value.replace(tzinfo=datetime.timezone.utc)
    if not isinstance(value, str):
        return None
    try:
        d = datetime.datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError:
        return None
    return d if d.tzinfo else d.replace(tzinfo=datetime.timezone.utc)


def now():
    return datetime.datetime.now(datetime.timezone.utc)


def write(path, text):
    with open(path, "w") as f:
        f.write(text)


def cert_id(certs_json, identities, id_out, sha_out):
    with open(identities, errors="replace") as f:
        keychain = set(h.upper() for h in re.findall(r"\b([0-9A-Fa-f]{40})\b", f.read()))
    if not keychain:
        print("SIGNING ERROR: no code signing identity in this machine's keychain: Codemagic did not install the stored "
              "distribution certificate (codemagic.yaml ios_signing: distribution_type app_store, bundle_identifier "
              "com.liamp.videoplayer; Codemagic: Team settings > codemagic.yaml settings > Code signing identities > "
              "iOS certificates)")
        return 1
    matches = []
    for r in resources(certs_json):
        content = field(r, "certificateContent")
        if not isinstance(content, str):
            continue
        try:
            sha = hashlib.sha1(base64.b64decode(content)).hexdigest().upper()
        except Exception:
            continue
        if sha in keychain:
            matches.append((r, sha))
    if len(matches) != 1:
        print("SIGNING ERROR: %d App Store Connect certificate(s) match the keychain's signing identity (need exactly 1); "
              "this step never makes a certificate (R266)" % len(matches))
        return 1
    r, sha = matches[0]
    expires = parse_date(field(r, "expirationDate"))
    if expires is not None and expires <= now():
        print("SIGNING ERROR: the stored distribution certificate has expired (%s)" % expires.date())
        return 1
    if not r.get("id"):
        print("SIGNING ERROR: the matching certificate has no resource ID in the CLI output")
        return 1
    write(id_out, str(r["id"]))
    write(sha_out, sha)
    print("SIGNING: the stored distribution certificate is in the keychain and in App Store Connect (expires %s)"
          % (expires.date() if expires else "date not shown"))
    return 0


def bundle_rid(bundle_json, identifier, out):
    found = [r for r in resources(bundle_json) if field(r, "identifier") == identifier and r.get("id")]
    if len(found) != 1:
        print("SIGNING ERROR: %d Bundle ID(s) with the identifier %s (need exactly 1; register it on developer.apple.com "
              "> Identifiers)" % (len(found), identifier))
        return 1
    write(out, str(found[0]["id"]))
    return 0


def profile_ids(profiles_json, out):
    ids = [str(r["id"]) for r in resources(profiles_json) if r.get("id")]
    write(out, "".join(i + "\n" for i in ids))
    print("SIGNING: %d active TVOS_APP_STORE profile(s) listed" % len(ids))
    return 0


def pick(directory, identifier, sha_file, out_dir):
    with open(sha_file) as f:
        cert_sha = f.read().strip().upper()
    soon = now() + datetime.timedelta(days=1)
    best = None
    for path in sorted(glob.glob(os.path.join(directory, "*"))):
        if not os.path.isfile(path):
            continue
        plist = pc.decode(path)
        if not plist or not pc.is_app_store(plist) or pc.bundle_id_of(plist) != identifier:
            continue
        platforms = plist.get("Platform")
        if platforms is not None and "tvOS" not in platforms:
            continue
        certs = [hashlib.sha1(c).hexdigest().upper() for c in (plist.get("DeveloperCertificates") or [])
                 if isinstance(c, (bytes, bytearray))]
        if cert_sha not in certs:
            continue
        expires = parse_date(plist.get("ExpirationDate"))
        if expires is None or expires <= soon:
            continue
        if best is None or expires > best[1]:
            best = (path, expires, plist)
    if best is None:
        return NOT_FOUND
    path, expires, plist = best
    uuid = str(plist.get("UUID") or "")
    if not re.fullmatch(r"[0-9A-Fa-f-]{36}", uuid):
        print("SIGNING ERROR: the chosen profile for %s has no valid UUID" % identifier)
        return 1
    os.makedirs(out_dir, exist_ok=True)
    shutil.copyfile(path, os.path.join(out_dir, uuid + ".mobileprovision"))
    print("SIGNING: App Store tvOS profile for %s with the stored certificate (expires %s)" % (identifier, expires.date()))
    return 0


def main(argv):
    try:
        if len(argv) == 6 and argv[1] == "cert-id":
            return cert_id(*argv[2:])
        if len(argv) == 5 and argv[1] == "bundle-rid":
            return bundle_rid(*argv[2:])
        if len(argv) == 4 and argv[1] == "profile-ids":
            return profile_ids(*argv[2:])
        if len(argv) == 6 and argv[1] == "pick":
            return pick(*argv[2:])
    except (OSError, ValueError) as e:
        print("SIGNING ERROR: %s: %s" % (argv[1], type(e).__name__))
        return 1
    print(__doc__)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))
