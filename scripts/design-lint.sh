#!/usr/bin/env bash
# design-lint: static checks for the native-tvOS-27 standard (docs/DESIGN_SYSTEM.md). No Swift toolchain needed:
# plain bash, grep and POSIX awk, so it runs in WSL (mawk), on a Mac build host, or in Git Bash (gawk).
#
# Usage:
#   bash scripts/design-lint.sh                    lint App/ and TopShelf/ with every rule (every .swift and .xcstrings
#                                                  file, and the image sets in their asset catalogs), plus the package
#                                                  modules that hold UI text (Packages/VideoPlayerCore/Sources/AppLogic,
#                                                  LibraryBackup, PlaybackStatus, SourceLinks, UserData) with the names rules only
#                                                  (unknown-name, claim-wording, brand-logo)
#   bash scripts/design-lint.sh FILE_OR_DIR ...    lint only these paths with every rule (the fixtures use this)
#   bash scripts/design-lint.sh --names-only P ... lint the paths after the flag with the names rules only
#   bash scripts/design-lint.sh --list-allows      list every `design-lint:allow <reason>` in the default scope
# Environment: DESIGN_LINT_NAMES=<file> reads the names allowlist from that file instead of docs/NAMES.md (the tests use
# this); DESIGN_LINT_TARGET=<x.y> overrides the deployment target read from project.yml.
# Exit code: 0 clean, 1 at least one violation, 2 usage error (also: names allowlist missing or empty).
# Output: one line per violation, `file:line: [rule] message`, then a summary line.
#
# Exceptions: put `design-lint:allow <reason>` in a comment on the offending line, or alone on the line above it.
# The reason is required (a bare marker is itself the violation `allow-without-reason`). Every exception in App/
# must also be listed, with its reason, in docs/DESIGN_SYSTEM.md (`--list-allows` prints them).
#
# Rules (id: what it catches). Interpretation of each is in docs/DESIGN_SYSTEM.md, section "Lint".
#   color-literal          hex/RGB/white-gray colour literals, #colorLiteral, fixed Color.white / Color.black
#   fixed-font             .system(size:), .custom(...), UIFont sizes, .dynamicTypeSize(...) limits
#   custom-focus           own focus visuals: focusEffectDisabled, hoverEffect, isFocused, focusable, custom ButtonStyle
#   custom-glass           hand-made blur / glass / material / scrim, and any glassEffect use (needs a recorded reason)
#   image-control          an Image that is not an SF Symbol (Image(systemName:)) inside Button/Menu/Toggle/Picker/NavigationLink
#   tap-gesture            onTapGesture / gestures standing in for a Button or contextMenu
#   hard-padding           numeric padding / frame sizes / spacing / safe-area bypass duplicating system layout
#   unknown-name           a third-party name in a UI string that is not in the docs/NAMES.md allowlist
#   brand-logo             logos and brand image assets: the Apple logo glyph or symbol, company-logo SF Symbols,
#                          image assets named after a logo, badge, brand or a listed company / product
#   claim-wording          trademark symbols and certification / endorsement claims in UI strings
#   pointless-availability availability checks that the deployment target (project.yml) already guarantees
#   motion                 animation or transition with no Reduce Motion handling in the same file
#   allow-without-reason   design-lint:allow with no reason text
#   upper-case             manual upper case for headers: textCase(.uppercase) (rule L4: one system header style)
#   row-background         custom row or pill backgrounds in Settings, source and form screens (rule L2: system styles)
#   fixed-card             a fixed height (or sheet detents) on a screen with scrolling content (rule L7)
#   short-line             .lineLimit(1) with no .minimumScaleFactor within 3 lines (rule S1: fit by scaling, never "...")
#   pushed-title           a .navigationTitle with the navigation bar left visible (rule D1: no dim duplicate title)
#   fixture-claim          "Tested against a real server" or .realServer in sample or fixture data (rule D7)
#   section-title-closure  Section("Title") { } followed by header: or footer: (no such SwiftUI initializer; #23 A)
#   form-sheet             any .sheet( presentation (#30: every task screen is a full-screen .taskCover, never a small sheet)
#   focus-room             a ScrollView, List or Form in a file with fewer .scrollClipDisabled() than containers, or a
#                          .clipped() / .clipShape( / .mask in such a file (R345: a focused row is never clipped)
#
# The names rule (unknown-name), exactly. It reads UI strings only (string literals in .swift files, keys and values in
# .xcstrings files), never comments or code identifiers. Per string: interpolations \(...), escapes, URLs, paths and
# file / host names (anything with a dot followed by a lowercase letter, such as nas.local or video.mkv), locale
# identifiers (en_US, en_US_POSIX) and date-format fields (a word made only of runs of one pattern letter, such as EEE,
# MMM, yyyy or HH:mm:ss) are blanked; then
# every name in the `names-allowlist` block of docs/NAMES.md and every term in its `names-generic` block is blanked
# (longest first, case-sensitive, whole words). A string that is a single word in identifier shape (starts lowercase,
# is camel case, or contains _ . /) is treated as a key, extension, folder or API constant and skipped unless it is a
# KNOWN name. What is left is checked for:
#   (a) a KNOWN third-party name from the list below (single-word names the shape tests cannot see);
#   (b) a word with an inner capital after a lowercase letter (camel shape, e.g. a product spelled like "FooBar");
#   (c) a word mixing letters and digits (e.g. "XY10", "AB-3");
#   (d) an all-capitals word of two or more characters (e.g. "XYZ");
#   (e) in a sentence (at least three lowercase-initial words, at least 40% of all words), a capitalised word that is not
#       the first word and does not follow . ! ? : > ( " or a dash;
#   (f) a capitalised word directly followed by a format-like token (a channel layout such as 7.1, a number, or "Profile").
# Each hit is reported once per token per line. Limits: strings built at run time and data from servers are not seen; a
# third-party name spelled as one ordinary capitalised word at the start of a sentence or inside a Title Case string is
# only caught when it is in the KNOWN list; an ordinary word that trips (b) to (f) must be added to `names-generic`; a
# code-only string in a package module that trips them (an HTTP method, a codec ID part) takes a design-lint:allow.
# claim-wording: in UI strings, the signs TM / R / SM (as characters or as "(TM)" "(R)"), "Works with", "Made for",
# "Designed for", "Certified by/for", "Approved by", "Endorsed by", "Licensed by", "Official" before a capitalised word,
# or a capitalised word followed by Certified / Ready / Approved / Compatible / Official. A string that says "not
# endorsed / affiliated / certified / approved / sponsored" (the required notices) is exempt, as is "Not Approved Yet".
# brand-logo: the Apple logo character U+F8FF anywhere; Image(systemName:) with applelogo, apple.logo or logo.*; an
# Image("...") / UIImage(named: "...") or an asset-catalog image set (outside the system .brandassets app-icon set)
# whose name contains logo, badge, brand, or an allowlisted / KNOWN name. No design-lint:allow marker works for this
# rule. The one exception is TMDB's attribution logo (TMDB_LOGO_* below): one image set at one path with the unaltered
# file, loaded only on the About screen.
#
# KNOWN third-party names (companies, services, formats; deliberately no media-player applications: the allowlist makes a
# ban list unnecessary). A name here that is also in the allowlist is allowed.
KNOWN_NAMES="Dolby Atmos Vision DTS Plex Jellyfin Emby Netflix Disney Hulu Amazon Google YouTube Spotify Trakt TVDB
Dropbox OneDrive Microsoft Samba Synology QNAP Sonos Roku Samsung Sony Nvidia Twitch Vimeo Crunchyroll Peacock Paramount
Fandango Fandom Metacritic Rotten Tomatoes JustWatch TMDB TMDb OMDb IMDb Apple Siri AirPlay iCloud HomePod Safari FaceTime
iTunes AirPods HomeKit CloudKit Bonjour Xiph Opus Vorbis Matroska Bluetooth HDMI Wi-Fi Xperi FFmpeg Linux Windows"
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TARGET="${DESIGN_LINT_TARGET:-}"
if [ -z "$TARGET" ] && [ -f "$HERE/project.yml" ]; then
  TARGET="$(grep -E '^[[:space:]]+tvOS:[[:space:]]*"?[0-9]' "$HERE/project.yml" | head -1 | sed -E 's/.*tvOS:[[:space:]]*"?([0-9]+(\.[0-9]+)?).*/\1/')"
fi
TARGET="${TARGET:-27.0}"
NAMES_FILE="${DESIGN_LINT_NAMES:-$HERE/docs/NAMES.md}"

LIST_ALLOWS=0
PATHS=()      # entries "1:path" (all rules) or "0:path" (names-only: unknown-name, claim-wording, brand-logo)
FULL=1
for a in "$@"; do
  case "$a" in
    --list-allows) LIST_ALLOWS=1 ;;
    --names-only) FULL=0 ;;
    -h|--help) awk 'NR > 1 && /^#/ { print; next } NR > 1 { exit }' "$0"; exit 0 ;;
    -*) echo "design-lint: unknown option $a" >&2; exit 2 ;;
    *) PATHS+=("$FULL:$a") ;;
  esac
done
if [ "${#PATHS[@]}" -eq 0 ]; then
  PATHS=("1:$HERE/App")
  [ -d "$HERE/TopShelf" ] && PATHS+=("1:$HERE/TopShelf")
  # The package modules that hold UI text (screen models, status wording, source and link messages, sync and backup text):
  # names rules only (the layout and colour rules are about SwiftUI views, which live in App/).
  for m in AppLogic LibraryBackup PlaybackStatus SourceLinks UserData; do
    [ -d "$HERE/Packages/VideoPlayerCore/Sources/$m" ] && PATHS+=("0:$HERE/Packages/VideoPlayerCore/Sources/$m")
  done
fi

FILES=()      # entries "1:file" or "0:file", as above
ASSETS=()
for e in "${PATHS[@]}"; do
  fl="${e%%:*}"; p="${e#*:}"
  if [ -d "$p" ]; then
    while IFS= read -r f; do FILES+=("$fl:$f"); done < <(find "$p" -type f \( -name '*.swift' -o -name '*.xcstrings' \) | LC_ALL=C sort)
    while IFS= read -r f; do ASSETS+=("$f"); done < <(find "$p" -type d \( -name '*.imageset' -o -name '*.imagestack' -o -name '*.symbolset' \) | grep -v '\.brandassets/' | LC_ALL=C sort)
  elif [ -f "$p" ]; then FILES+=("$fl:$p")
  else echo "design-lint: no such path: $p" >&2; exit 2; fi
done

TMP="$(mktemp -d "${TMPDIR:-/tmp}/design-lint.XXXXXX")"; trap 'rm -rf "$TMP"' EXIT
VIOLATIONS=0
ALLOWED=0

# --- names allowlist (docs/NAMES.md) --------------------------------------------------------------------------
# Two fenced blocks: ```names-allowlist (third-party names, one per line, `#` lines are group headings) and
# ```names-generic (ordinary words and the app's own terms that the shape tests would otherwise report).
block() { tr -d '\r' <"$NAMES_FILE" | awk -v want="$1" '
  /^```/ { if (inb) { inb = 0; next } if ($0 == "```" want) { inb = 1; next } }
  inb && $0 !~ /^[[:space:]]*#/ && $0 !~ /^[[:space:]]*$/ { sub(/^[[:space:]]+/, ""); sub(/[[:space:]]+$/, ""); print }'; }
if [ "$LIST_ALLOWS" = 0 ]; then
  if [ ! -f "$NAMES_FILE" ]; then echo "design-lint: names allowlist not found: $NAMES_FILE" >&2; exit 2; fi
  block names-allowlist >"$TMP/allow.txt"
  block names-generic >"$TMP/generic.txt"
  if [ ! -s "$TMP/allow.txt" ]; then echo "design-lint: no \`\`\`names-allowlist block in $NAMES_FILE" >&2; exit 2; fi
  printf '%s\n' $KNOWN_NAMES >"$TMP/known.txt"
fi

# --- helpers -------------------------------------------------------------------------------------------------
# norm FILE OUT: LF endings, no BOM.
norm() { tr -d '\r' <"$1" | sed '1s/^\xEF\xBB\xBF//' >"$2"; }

# splitcode IN CODE TEXT STR: CODE = the file with string-literal contents and comments blanked (line numbers kept);
# TEXT = only the string-literal contents and comments of each line; STR = only the string-literal contents.
# Handles // /* */ """ and escapes.
splitcode() {
  awk -v codeout="$2" -v textout="$3" -v strout="$4" '
    BEGIN { inBlock = 0; inTriple = 0 }
    {
      line = $0; n = length(line); i = 1; code = ""; text = ""; str = ""; inStr = 0
      while (i <= n) {
        c = substr(line, i, 1); c2 = substr(line, i, 2); c3 = substr(line, i, 3)
        if (inBlock) { if (c2 == "*/") { inBlock = 0; i += 2; text = text " " } else { text = text c; i++ } code = code " "; continue }
        if (inTriple) { if (c3 == "\"\"\"") { inTriple = 0; i += 3; text = text " "; str = str " | " } else { text = text c; str = str c; i++ } code = code " "; continue }
        if (inStr) {
          if (c == "\\") { text = text substr(line, i, 2); str = str substr(line, i, 2); i += 2 }
          else if (c == "\"") { inStr = 0; i++; text = text " "; str = str " | "; code = code "\"" }
          else { text = text c; str = str c; i++ }
          code = code " "; continue
        }
        if (c3 == "\"\"\"") { inTriple = 1; i += 3; code = code "   "; continue }
        if (c == "\"") { inStr = 1; i++; code = code "\""; continue }
        if (c2 == "//") { text = text substr(line, i + 2); i = n + 1; continue }
        if (c2 == "/*") { inBlock = 1; i += 2; code = code "  "; continue }
        code = code c; i++
      }
      print code > codeout; print text > textout; print str > strout
    }' "$1"
}

# xcstrings_strings IN OUT: the keys and values of a string catalog, one output line per input line (JSON structure
# words, Info.plist keys and language codes dropped).
xcstrings_strings() {
  awk '{
    s = $0; out = ""
    while (match(s, /"([^"\\]|\\.)*"/)) {
      t = substr(s, RSTART + 1, RLENGTH - 2); s = substr(s, RSTART + RLENGTH)
      if (t ~ /^(sourceLanguage|strings|localizations|stringUnit|state|value|version|comment|extractionState|translated|new|needs_review|stale|manual|variations|plural|device|substitutions|formatSpecifier|argNum|zero|one|two|few|many|other|appletv|en|[a-z][a-z](-[A-Za-z]+)?|[0-9.]+)$/) continue
      if (t ~ /^(CF|NS|UI|LS)[A-Za-z]+$/) continue
      out = out " | " t
    }
    print out }' "$1" >"$2"
}

# has_allow FILE LINE: does this line, or a comment-only line directly above, carry design-lint:allow <reason>?
has_allow() {
  local f="$1" ln="$2" cur prev
  cur="$(sed -n "${ln}p" "$f")"
  if printf '%s' "$cur" | grep -qE 'design-lint:allow[[:space:]]+[^[:space:]]'; then return 0; fi
  if [ "$ln" -gt 1 ]; then
    prev="$(sed -n "$((ln - 1))p" "$f")"
    if printf '%s' "$prev" | grep -qE '^[[:space:]]*(//|/\*)' && printf '%s' "$prev" | grep -qE 'design-lint:allow[[:space:]]+[^[:space:]]'; then return 0; fi
  fi
  return 1
}

# report DISPLAYNAME NORMFILE LINE RULE MESSAGE
report() {
  # brand-logo cannot be allowed with a marker: the one logo exception (TMDB, see TMDB_LOGO_* below) is fixed in this
  # script by asset name, file content and screen, so no other logo can be let in by a comment.
  if [ "$4" != brand-logo ] && has_allow "$2" "$3"; then ALLOWED=$((ALLOWED + 1)); return; fi
  echo "$1:$3: [$4] $5"; VIOLATIONS=$((VIOLATIONS + 1))
}

# scan NAME NORMFILE STREAMFILE RULE REGEX MESSAGE: grep -E the stream, report each matching line.
scan() {
  local name="$1" nf="$2" stream="$3" rule="$4" re="$5" msg="$6" ln
  while IFS= read -r ln; do [ -n "$ln" ] && report "$name" "$nf" "$ln" "$rule" "$msg"; done < <(grep -nE -- "$re" "$stream" | cut -d: -f1)
}

# image-control on the code stream: Image that is not an SF Symbol inside a control's braces / same statement.
image_control() {
  awk '
    function count(s, ch,   k, c) { c = 0; for (k = 1; k <= length(s); k++) if (substr(s, k, 1) == ch) c++; return c }
    BEGIN { depth = 0; sp = 0 }
    {
      line = $0
      isctrl = (line ~ /(^|[^A-Za-z0-9_])(Button|Menu|Toggle|Picker|NavigationLink)[ (\{]/)
      if (isctrl) { sp++; stack[sp] = depth }
      if (sp > 0 && line ~ /(^|[^A-Za-z0-9_])Image\(/ && line !~ /(^|[^A-Za-z0-9_])Image\(systemName:/) print NR
      depth += count(line, "{") - count(line, "}")
      while (sp > 0 && depth <= stack[sp]) sp--
    }' "$1"
}

# section_title_closure CODEFILE (#23 A): lines of a Section(<title>) { ... } that is followed by a header: or footer:
# closure. SwiftUI has Section(_:content:) and Section(content:header:footer:), but no initializer that takes a title AND
# a header or footer closure, so this fails to compile ("generic parameter 'Content' could not be inferred"). Brace and
# parenthesis matching runs on the code stream (strings blanked, comments removed), across lines.
section_title_closure() {
  awk '
    { all = all $0 "\n" }
    END {
      n = length(all); line = 1
      for (i = 1; i <= n; i++) { ch[i] = substr(all, i, 1); ln[i] = line; if (ch[i] == "\n") line++ }
      for (i = 1; i <= n - 8; i++) {
        if (substr(all, i, 8) != "Section(") continue
        if (i > 1 && ch[i - 1] ~ /[A-Za-z0-9_.]/) continue
        j = i + 8; while (j <= n && ch[j] ~ /[ \t\n]/) j++
        if (ch[j] == ")") continue
        if (ch[j] != "\"") { k = j; while (k <= n && ch[k] ~ /[A-Za-z0-9_]/) k++; if (k > j && ch[k] == ":") continue }
        d = 0
        for (k = i + 7; k <= n; k++) { if (ch[k] == "(") d++; else if (ch[k] == ")") { d--; if (d == 0) break } }
        k++; while (k <= n && ch[k] ~ /[ \t\n]/) k++
        if (ch[k] != "{") continue
        d = 0
        for (; k <= n; k++) { if (ch[k] == "{") d++; else if (ch[k] == "}") { d--; if (d == 0) break } }
        k++; while (k <= n && ch[k] ~ /[ \t\n]/) k++
        if (substr(all, k, 7) == "header:" || substr(all, k, 7) == "footer:") print ln[i]
      }
    }' "$1"
}

# pointless_availability CODEFILE: lines whose tvOS version is <= the deployment target, or any iOS/macOS-only check.
pointless_availability() {
  awk -v target="$TARGET" '
    BEGIN { split(target, t, "."); tmaj = t[1] + 0; tmin = (t[2] == "" ? 0 : t[2] + 0) }
    /(#available|#unavailable|@available)[ ]*\(/ {
      s = $0; hit = 0
      while (match(s, /tvOS[ ]*[0-9]+(\.[0-9]+)?/)) {
        v = substr(s, RSTART, RLENGTH); sub(/tvOS[ ]*/, "", v); split(v, p, ".")
        maj = p[1] + 0; mi = (p[2] == "" ? 0 : p[2] + 0)
        if (maj < tmaj || (maj == tmaj && mi <= tmin)) hit = 1
        s = substr(s, RSTART + RLENGTH)
      }
      if (hit) print NR
    }' "$1"
}

# unknown_names STRFILE: prints `LINE<TAB>TOKEN<TAB>WHY` for every candidate third-party name left after the allowlist and
# the generic terms are blanked (rule text in the header). Strings on one line are separated by " | ".
unknown_names() {
  awk -v allowf="$TMP/allow.txt" -v genf="$TMP/generic.txt" -v knownf="$TMP/known.txt" '
    function isalnum(ch) { return ch ~ /^[A-Za-z0-9]$/ }
    # blank every whole-word occurrence of w in s (case-sensitive)
    function blank(s, w,   out, p, L, pre, post, rest) {
      L = length(w); out = ""; rest = s
      while ((p = index(rest, w)) > 0) {
        pre = (p > 1) ? substr(rest, p - 1, 1) : ""
        post = substr(rest, p + L, 1)
        if ((pre == "" || !isalnum(pre)) && (post == "" || !isalnum(post) || substr(w, L, 1) !~ /[A-Za-z0-9]/)) {
          out = out substr(rest, 1, p - 1) sprintf("%" L "s", ""); rest = substr(rest, p + L)
        } else { out = out substr(rest, 1, p); rest = substr(rest, p + 1) }
      }
      return out rest
    }
    BEGIN {
      n = 0
      while ((getline w < allowf) > 0) { n++; W[n] = w }
      while ((getline w < genf) > 0) { n++; W[n] = w; GEN[w] = 1 }
      # longest first (insertion sort; the lists are small)
      for (i = 2; i <= n; i++) { v = W[i]; j = i - 1; while (j > 0 && length(W[j]) < length(v)) { W[j + 1] = W[j]; j-- } W[j + 1] = v }
      while ((getline w < knownf) > 0) KNOWN[w] = 1
    }
    {
      s = $0
      gsub(/\\\(([^()]|\([^()]*\))*\)/, " ", s)        # interpolations (one level of nested parentheses)
      gsub(/\\[nrt0"\\]/, " ", s); gsub(/\\u\{[0-9A-Fa-f]+\}/, " ", s)
      gsub(/[A-Za-z][A-Za-z0-9+.-]*:\/\/[^ |]*/, " ", s) # URLs
      gsub(/(^|[ (])\/[^ |]*/, " ", s)                  # absolute paths
      gsub(/[A-Za-z0-9_~-]*\.[a-z][A-Za-z0-9._-]*/, " ", s) # file and host names (nas.local, video.mkv, e.g.)
      gsub(/%[0-9$.]*(@|lld|ld|d|f|s)/, " ", s)        # format specifiers
      gsub(/[a-z][a-z][a-z]?_[A-Z][A-Z](_[A-Z]+)?/, " ", s) # locale identifiers (en_US, en_US_POSIX)
      nw = split(s, DW, / /); r = ""                    # date-format fields: runs of one pattern letter (EEE, MMM, yyyy, HH:mm:ss)
      for (i = 1; i <= nw; i++) {
        if (DW[i] ~ /^[,]*(EE+|MM+|LL+|yy+|dd+|HH+|hh+|mm+|ss+|SS+|zz+|ZZ+|XX+|xx+)([:.,-](EE+|MM+|LL+|yy+|dd+|HH+|hh+|mm+|ss+|SS+|zz+|ZZ+|XX+|xx+))*[,]*$/) DW[i] = ""
        r = r (i > 1 ? " " : "") DW[i]
      }
      s = r
      for (i = 1; i <= n; i++) if (index(s, W[i]) > 0) s = blank(s, W[i])
      nseg = split(s, seg, / \| /)
      delete SEEN
      for (k = 1; k <= nseg; k++) {
        t = seg[k]
        # a one-word string in identifier shape (lowercase start, camel case, or containing _ . /) is a key, file
        # extension, folder or API constant, not UI text: skipped unless it is a KNOWN name
        tt = t; gsub(/^ +| +$/, "", tt)
        if (tt !~ / / && (tt ~ /^[a-z]/ || tt ~ /[_.\/]/ || tt ~ /[a-z][A-Z]/) && !(tt in KNOWN)) continue
        # sentence test
        nw = split(t, words, /[^A-Za-z0-9+:.-]+/); lower = 0; total = 0
        for (q = 1; q <= nw; q++) { if (words[q] ~ /^[A-Za-z]/) { total++; if (words[q] ~ /^[a-z]/) lower++ } }
        sentence = (lower >= 3 && lower * 10 >= total * 4)
        rest = t; pos = 0; first = 1
        while (match(rest, /[A-Za-z][A-Za-z0-9]*([-:.+][A-Za-z0-9]+)*\+?/)) {
          tok = substr(rest, RSTART, RLENGTH); before = substr(t, 1, pos + RSTART - 1); after = substr(rest, RSTART + RLENGTH)
          pos += RSTART + RLENGTH - 1; rest = after
          sub(/[.:-]+$/, "", tok)
          why = ""
          if (tok in GEN) why = ""
          else if (tok in KNOWN) why = "a known third-party name"
          else if (tok ~ /[a-z][A-Z]/) why = "an inner capital (product-name shape)"
          else if (tok ~ /[A-Za-z]/ && tok ~ /[0-9]/) why = "letters mixed with digits (format or model shape)"
          else if (tok ~ /^[A-Z][A-Z0-9]+$/ || tok ~ /^[A-Z]+[-:][A-Z0-9:-]+$/) why = "all capitals (acronym or brand shape)"
          else if (tok ~ /^[A-Z][a-z]+$/) {
            b = before; sub(/[ \t]+$/, "", b); lastch = substr(b, length(b), 1)
            if (sentence && !first && b != "" && lastch !~ /[.!?:>("-]/) why = "a capitalised word inside a sentence"
            else if (after ~ /^ ([0-9]+(\.[0-9]+)?([^A-Za-z0-9]|$)|Profile)/) why = "a capitalised word before a format token"
          }
          first = 0
          if (why != "" && !((tok) in SEEN)) { SEEN[tok] = 1; printf "%d\t%s\t%s\n", NR, tok, why }
        }
      }
    }' "$1"
}

# claim_lines STRFILE: lines with trademark symbols or certification / endorsement claims (rule text in DESIGN_SYSTEM).
claim_lines() {
  # trademark, registered and service-mark signs as UTF-8 bytes (the script itself stays ASCII)
  awk -v tm="$(printf '\342\204\242')" -v reg="$(printf '\302\256')" -v sm="$(printf '\342\204\240')" '
    {
      s = $0
      if (s ~ /not (endorsed|affiliated|certified|approved|sponsored)|nor (endorsed|affiliated|certified)/) next
      if (index(s, tm) || index(s, reg) || index(s, sm) || s ~ /\(TM\)|\(R\)/) { print NR; next }
      if (s ~ /(Works [Ww]ith|Made [Ff]or|Designed [Ff]or|Certified [Bb]y|Certified [Ff]or|Approved [Bb]y|Endorsed [Bb]y|Licensed [Bb]y|Official) [A-Z]/) { print NR; next }
      t = s; gsub(/(Not|Is|Are|Be|Been|Yet) (Certified|Ready|Approved|Compatible|Official)/, " ", t)
      if (t ~ /[A-Z][A-Za-z0-9+:-]* (Certified|Ready|Approved|Compatible|Official)([^A-Za-z]|$)/) { print NR; next }
    }' "$1"
}

# The ONE logo exception (user decision, OPEN_QUESTIONS R148): TMDB's logo, exactly as published on
# https://www.themoviedb.org/about/logos-attribution ("Primary long (blue)"), required by TMDB's API terms section 3.
# Allowed only as the image set App/Assets.xcassets/TMDBAttributionLogo.imageset holding Contents.json and the unaltered
# TMDBAttributionLogo.svg (sha256 below), and only loaded as Image("TMDBAttributionLogo") in
# App/Features/Settings/AboutView.swift (Settings > About > Data Sources). Anything else named like a logo still fails.
TMDB_LOGO_ASSET="TMDBAttributionLogo"
TMDB_LOGO_SCREEN="App/Features/Settings/AboutView.swift"
TMDB_LOGO_SET="App/Assets.xcassets/TMDBAttributionLogo.imageset"
TMDB_LOGO_SHA256="9665a76b1ae401a510ec1e0ca40ddcb3b0cfe45f1d51b77a308fea0845885648"
sha256_of() { if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1"; else shasum -a 256 "$1"; fi | cut -d' ' -f1; }

# logo_image_names RAWFILE [REALPATH]: lines that load an image asset whose name says logo / badge / brand or contains a
# listed name. Image("TMDBAttributionLogo") is skipped only when REALPATH is the About screen.
logo_image_names() {
  local exempt=""
  case "${2:-}" in *"/$TMDB_LOGO_SCREEN") exempt="$TMDB_LOGO_ASSET" ;; esac
  awk -v allowf="$TMP/allow.txt" -v knownf="$TMP/known.txt" -v exempt="$exempt" '
    function norm(x) { x = tolower(x); gsub(/[^a-z0-9]/, "", x); return x }
    BEGIN {
      while ((getline w < allowf) > 0) { w = norm(w); if (length(w) >= 3) N[w] = 1 }
      while ((getline w < knownf) > 0) { w = norm(w); if (length(w) >= 3) N[w] = 1 }
    }
    {
      s = $0
      while (match(s, /(Image|UIImage)\((named:[ ]*)?"[^"]*"/)) {
        m = substr(s, RSTART, RLENGTH); s = substr(s, RSTART + RLENGTH)
        sub(/^[^"]*"/, "", m); sub(/"$/, "", m); x = norm(m)
        if (exempt != "" && m == exempt) continue
        hit = (x ~ /logo|badge|brand/)
        for (w in N) if (!hit && ((length(w) >= 4 && index(x, w) > 0) || x == w)) hit = 1
        if (hit) { print NR; break }
      }
    }' "$1"
}

# --- per-file checks ------------------------------------------------------------------------------------------
LOGO_GLYPH="$(printf '\357\243\277')"   # U+F8FF, the Apple logo in Apple fonts
names_rule() { # NAME NF STRFILE
  local name="$1" nf="$2" sf="$3" ln tok why
  while IFS="$(printf '\t')" read -r ln tok why; do
    [ -n "$ln" ] && report "$name" "$nf" "$ln" unknown-name "'$tok' looks like a third-party name ($why) and is not in the names allowlist (docs/NAMES.md): add it to names-allowlist if it names a technology, service or company the app uses, or to names-generic if it is an ordinary word"
  done < <(unknown_names "$sf")
  while IFS= read -r ln; do [ -n "$ln" ] && report "$name" "$nf" "$ln" claim-wording 'trademark symbol or certification / endorsement claim in a UI string: name formats and services plainly and say what the app does, never "Certified", "Ready", "Works with", "Made for" or (TM)/(R)'; done < <(claim_lines "$sf")
}

for e in "${FILES[@]}"; do
  full="${e%%:*}"; f="${e#*:}"
  IDX=$((${IDX:-0} + 1)); base="f$IDX"
  nf="$TMP/$base.raw"; cf="$TMP/$base.code"; tf="$TMP/$base.text"; sf="$TMP/$base.str"
  norm "$f" "$nf"
  if [ "$LIST_ALLOWS" = 1 ]; then
    grep -nE 'design-lint:allow' "$nf" | sed "s|^|$f:|"
    continue
  fi
  scan "$f" "$nf" "$nf" brand-logo "$LOGO_GLYPH" 'the Apple logo glyph: no logo of any company anywhere (text names only)'
  case "$f" in
    *.xcstrings)
      # String catalogs are JSON: only the name rules apply, on the keys and values.
      xcstrings_strings "$nf" "$sf"
      names_rule "$f" "$nf" "$sf"
      continue ;;
  esac
  splitcode "$nf" "$cf" "$tf" "$sf"

  # allow-without-reason (raw)
  while IFS= read -r ln; do
    [ -z "$ln" ] && continue
    sed -n "${ln}p" "$nf" | grep -qE 'design-lint:allow[[:space:]]+[^[:space:]]' || { echo "$f:$ln: [allow-without-reason] design-lint:allow needs a reason after it"; VIOLATIONS=$((VIOLATIONS + 1)); }
  done < <(grep -n 'design-lint:allow' "$nf" | cut -d: -f1)

  # fixture-claim (#16 item 1.11, rule D7): sample and fixture data never claim a real-server test. Every scope.
  case "$(basename "$f")" in
    *[Ff]ixture*) scan "$f" "$nf" "$nf" fixture-claim 'Tested against a real server|\.realServer([^A-Za-z0-9_]|$)' 'sample or fixture data must not claim a real-server test: use the honest "not tested" status (rule D7)' ;;
  esac

  if [ "$full" = 0 ]; then names_rule "$f" "$nf" "$sf"; continue; fi
  scan "$f" "$nf" "$cf" color-literal '(Color|UIColor|CGColor)\((red|white|hue|hex|\.sRGB|\.displayP3|\.extendedSRGB|\.sRGBLinear|\.genericGray)|#colorLiteral|0x[0-9A-Fa-f]{6,8}([^0-9A-Za-z_]|$)|Color\.(white|black)([^A-Za-z0-9_]|$)|[(,: ]\.(white|black)([^A-Za-z0-9_]|$)' 'colour literal or fixed white/black: use a semantic colour (.primary, .secondary, Color.accentColor, system colours)'
  scan "$f" "$nf" "$nf" color-literal '"#[0-9A-Fa-f]{3,8}"' 'hex colour string: use a semantic colour'
  scan "$f" "$nf" "$cf" fixed-font '\.system\(size|\.custom\(|UIFont\.(systemFont|boldSystemFont|monospaced|preferredFont\(forTextStyle: \.[a-z]+\)\.withSize)|UIFont\(name|NSFont|\.dynamicTypeSize\(|\.minimumScaleFactor\(' 'fixed or restricted font size: use a system text style (.body, .title, ...) so Larger Text and Bold Text work'
  scan "$f" "$nf" "$cf" custom-focus 'focusEffectDisabled|\.hoverEffect\(|\.isFocused|UIFocusHaloEffect|\.focusable\(|:[[:space:]]*(Button|PrimitiveButton|Toggle|Label|Menu)Style([^A-Za-z0-9_]|$)|ButtonStyleConfiguration' 'custom focus visuals or custom control style: use the system focus engine and system styles'
  scan "$f" "$nf" "$cf" custom-glass '\.blur\(|UIVisualEffectView|UIBlurEffect|VisualEffect|\.(ultraThin|thin|regular|thick|ultraThick|bar)Material|\.glassEffect|GlassEffectContainer|\.backgroundExtensionEffect|\.background\([^)]*\.opacity\(|\.background\(\.(black|white)|\.(black|white)\.opacity\(' 'hand-made blur, glass or scrim: standard components adopt Liquid Glass; custom glass only through the documented API with a recorded reason'
  scan "$f" "$nf" "$cf" tap-gesture '\.onTapGesture|TapGesture\(|\.onLongPressGesture|LongPressGesture\(|\.gesture\(|\.simultaneousGesture\(|\.highPriorityGesture\(|DragGesture' 'gesture standing in for a control: use Button (and .contextMenu for long-press actions) so the focus engine sees it'
  scan "$f" "$nf" "$cf" hard-padding '\.padding\((\.[a-zA-Z]+,[[:space:]]*)?-?[0-9]|\.padding\(\.[a-zA-Z]+,[[:space:]]*[0-9]|\.safeAreaPadding\(|\.ignoresSafeArea\(|\.edgesIgnoringSafeArea|EdgeInsets\(|\.frame\((.*,[[:space:]]*)?(width|height|minWidth|minHeight|maxWidth|maxHeight|idealWidth|idealHeight):[[:space:]]*[0-9]|\.offset\(|\.(contentMargins|listRowInsets)\(|spacing:[[:space:]]*[0-9]' 'hard-coded layout value or safe-area bypass: use system layout; a number taken from the HIG goes with a design-lint:allow that cites the page'
  while IFS= read -r ln; do [ -n "$ln" ] && report "$f" "$nf" "$ln" image-control 'Image that is not an SF Symbol inside a control: use Image(systemName:) or a Label'; done < <(image_control "$cf")
  scan "$f" "$nf" "$nf" brand-logo 'systemName:[[:space:]]*"(applelogo|apple\.logo|logo\.[A-Za-z0-9.]+)"' 'logo SF Symbol (Apple logo or a company logo): SF Symbols are fine, logos are not'
  while IFS= read -r ln; do [ -n "$ln" ] && report "$f" "$nf" "$ln" brand-logo 'image asset named after a logo, badge, brand or a listed company/product: no logos or brand-coloured badges, text names only'; done < <(logo_image_names "$nf" "$f")
  names_rule "$f" "$nf" "$sf"
  while IFS= read -r ln; do [ -n "$ln" ] && report "$f" "$nf" "$ln" pointless-availability "availability check already guaranteed by the deployment target tvOS $TARGET (project.yml): remove it"; done < <(pointless_availability "$cf")
  # #16 item 1.11: the layout rules of #15 that can be checked in the code.
  scan "$f" "$nf" "$cf" upper-case 'textCase\(\.uppercase\)' 'manual upper case: section headers keep the one system style (rule L4)'
  if printf '%s' "$f" | grep -qE '/(Settings|Sources)/' || grep -qE '(^|[^A-Za-z0-9_])Form[[:space:]]*(\{|\()' "$cf"; then
    scan "$f" "$nf" "$cf" row-background '\.listRowBackground\(|\.background\([^)]*(RoundedRectangle|Capsule|Circle|\.fill|Color|\.quaternary|\.tertiary|\.secondary)|\.clipShape\((RoundedRectangle|Capsule)|\.cornerRadius\(' 'custom row or pill background in a Settings or form screen: system List / Form row styles only (rule L2)'
  fi
  if grep -qE '(^|[^A-Za-z0-9_])(ScrollView|List|Form)[[:space:]]*(\{|\()' "$cf"; then
    while IFS= read -r ln; do [ -n "$ln" ] && report "$f" "$nf" "$ln" fixed-card 'fixed height on a screen with scrolling content: let it size to its content or scroll (rule L7)'; done \
      < <(grep -nE '\.frame\([^)]*(height|maxHeight):|\.presentationDetents\(' "$cf" | grep -v 'infinity' | cut -d: -f1)
  fi
  while IFS= read -r ln; do [ -n "$ln" ] && report "$f" "$nf" "$ln" short-line '.lineLimit(1) without .minimumScaleFactor: short texts scale to fit, never end in "..." (rule S1; App/Shared/FittingLine.swift)'; done < <(
    awk '{ l[NR] = $0 } END { for (i = 1; i <= NR; i++) if (l[i] ~ /\.lineLimit\(1\)/) { ok = 0; for (j = i - 3; j <= i + 3; j++) if (j >= 1 && j <= NR && l[j] ~ /minimumScaleFactor/) ok = 1; if (!ok) print i } }' "$cf")
  if grep -q '\.navigationTitle(' "$cf" && ! grep -qE 'toolbarVisibility\(\.hidden, for: \.navigationBar\)|\.(pushedScreen|tabRootScreen)\(' "$cf"; then
    scan "$f" "$nf" "$cf" pushed-title '\.navigationTitle\(' 'navigation title with the bar left visible: use .pushedScreen(title) so no dim duplicate title is drawn (rule D1)'
  fi

  while IFS= read -r ln; do [ -n "$ln" ] && report "$f" "$nf" "$ln" section-title-closure 'Section("Title") { } with a header: or footer: closure does not compile: write Section { } header: { Text("Title") } footer: { } (#23 A)'; done < <(section_title_closure "$cf")
  # #30 (OPEN_QUESTIONS R228): every task screen opens full screen through `.taskCover` (or `.addSourceCover`); any
  # `.sheet(` presentation is reported (a small card over the page, the tab bar above it: 10, 11, 17, 21, 74, 94).
  scan "$f" "$nf" "$cf" form-sheet '\.sheet\(' 'presented as a sheet: present task screens full screen with .taskCover(isPresented:) or .taskCover(item:) (#30, R228)'
  # R345 (compile run of 21 Nov 2026): the system focus effect grows a focused row past its container, and a List, Form or
  # scroll view clips it to its bounds (31: the row cut flat at x 990). Every container gives the focus room the system way,
  # `.scrollClipDisabled()`; a container that holds no focusable row takes a design-lint:allow with the reason.
  if grep -qE '(^|[^A-Za-z0-9_])(ScrollView|List|Form)[[:space:]]*(\{|\()' "$cf"; then
    need=0; lines=""
    while IFS= read -r ln; do
      [ -z "$ln" ] && continue
      if has_allow "$nf" "$ln"; then ALLOWED=$((ALLOWED + 1)); else need=$((need + 1)); lines="$lines $ln"; fi
    done < <(grep -nE '(^|[^A-Za-z0-9_])(ScrollView|List|Form)[[:space:]]*(\{|\()' "$cf" | cut -d: -f1)
    have="$(grep -c 'scrollClipDisabled' "$cf")"
    if [ "$have" -lt "$need" ]; then
      for ln in $lines; do report "$f" "$nf" "$ln" focus-room 'ScrollView, List or Form without .scrollClipDisabled(): the system focus effect grows a focused row past the container, which clips it (R345)'; done
    fi
    scan "$f" "$nf" "$cf" focus-room '\.clipped\(\)|\.clipShape\(|\.mask[[:space:]]*[({]' 'clipping modifier in a file with a scrolling container: never clip a container that holds focusable rows (R345)'
  fi
  if ! grep -q 'accessibilityReduceMotion' "$cf"; then
    scan "$f" "$nf" "$cf" motion 'withAnimation|\.animation\(|\.transition\(|\.contentTransition\(|\.symbolEffect\(|\.phaseAnimator\(|\.keyframeAnimator\(' 'animation with no @Environment(\.accessibilityReduceMotion) in this file: honour Reduce Motion'
  fi
done

# --- asset catalogs: image sets named after a logo, badge, brand or a listed name (no allow marker possible) ----------
if [ "$LIST_ALLOWS" = 0 ]; then
  for a in "${ASSETS[@]}"; do
    nm="$(basename "$a")"; nm="${nm%.*}"
    if [ "$nm" = "$TMDB_LOGO_ASSET" ]; then
      # The one exception: right place, exactly two files, the logo file byte for byte as TMDB publishes it.
      why=""
      case "$a" in *"/$TMDB_LOGO_SET") ;; *) why="the TMDB logo image set is allowed only at $TMDB_LOGO_SET" ;; esac
      if [ -z "$why" ]; then
        list="$(cd "$a" && ls -A | LC_ALL=C sort | tr '\n' ' ')"
        if [ "$list" != "Contents.json $TMDB_LOGO_ASSET.svg " ]; then why="the TMDB logo image set must hold only Contents.json and $TMDB_LOGO_ASSET.svg (found: $list)"
        elif [ "$(sha256_of "$a/$TMDB_LOGO_ASSET.svg")" != "$TMDB_LOGO_SHA256" ]; then why="$TMDB_LOGO_ASSET.svg differs from the file TMDB publishes (sha256 $TMDB_LOGO_SHA256): do not recolour or alter it"; fi
      fi
      if [ -n "$why" ]; then echo "$a:1: [brand-logo] $why"; VIOLATIONS=$((VIOLATIONS + 1)); fi
      continue
    fi
    printf 'Image("%s")\n' "$nm" >"$TMP/asset.txt"
    if [ -n "$(logo_image_names "$TMP/asset.txt")" ]; then
      echo "$a:1: [brand-logo] image set named after a logo, badge, brand or a listed company/product: no logos in the app"; VIOLATIONS=$((VIOLATIONS + 1))
    fi
  done
fi

if [ "$LIST_ALLOWS" = 1 ]; then exit 0; fi
if [ "$VIOLATIONS" -gt 0 ]; then
  echo "design-lint: $VIOLATIONS violation(s), $ALLOWED allowed by design-lint:allow, ${#FILES[@]} file(s) checked (target tvOS $TARGET)"
  exit 1
fi
echo "design-lint: clean, $ALLOWED allowed by design-lint:allow, ${#FILES[@]} file(s) checked (target tvOS $TARGET)"
exit 0
