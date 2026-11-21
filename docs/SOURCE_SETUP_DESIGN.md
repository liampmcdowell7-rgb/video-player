# Source setup screens: tvOS design (owner's request of 20 Nov 2026)

Status: **PROVISIONAL. Designed here; built in the commits that follow; not yet compiled for tvOS or seen on a device.** Every decision has an R number
(R320 to R331) in OPEN_QUESTIONS.md with its alternatives. The owner's words: the source screens were "generally really
poorly built", not Apple HIG, not Apple TV design compatible or standard. Pictures named below are from the compile run of
20 Nov 2026 (screenshots_7).

Screens: Add a Source (10), About Source Types (10-add-source-learn-more), the types that are not available (20), every
form (11 WebDAV, 12 SMB, 13 NFS, 14 SFTP, 15 FTP, 16 UPnP/DLNA, 17 Jellyfin, 18 Emby, 19 Web Link), the keyboard
(11-form-webdav-keyboard-name), Search Your Network (21, 21-search-your-network-result), Server Details
(21-search-your-network-server-details), and the Larger Text and Bold Text variants (93, 94, 99, 100, 110, 111).

## Apple pages read (20 Nov 2026) and what they say

Quoted lines are exact. **NOT STATED** means the page was read and says nothing about it.

| Page | What it says that this design uses |
|---|---|
| HIG Designing for tvOS | "Embrace the tvOS focus system, letting it gently highlight and expand onscreen items as people move among them"; people sit "often 8 feet or more" away; inputs include "apps running on their other devices". Text input: NOT STATED. |
| HIG Text fields | "**Minimize text entry in your tvOS and watchOS apps.**"; "**Show a hint in a text field to help communicate its purpose.** A text field can contain placeholder text … when there's no other text"; "Because placeholder text disappears when people start typing, it can also be useful to include a separate label"; "**In iOS, iPadOS, tvOS, and visionOS apps, show the appropriate keyboard type.**"; "**Use secure text fields to hide private data.**"; tvOS platform considerations: "No additional considerations for tvOS or visionOS." "Optional" as a hint: NOT STATED. |
| HIG Keyboards | Physical keyboards only; "No additional considerations for iOS, iPadOS, macOS, or tvOS." |
| HIG Virtual keyboards (linked from Text fields) | "**Choose a keyboard that matches the type of content people are editing.**"; tvOS: "tvOS displays a linear virtual keyboard when people select a text field using the Siri Remote." and "A grid keyboard screen appears when people use devices other than the Siri Remote". |
| HIG Managing accounts | tvOS: "Most people interact with Apple TV using a remote, not a keyboard, so ask for the minimum amount of information necessary."; "**Prefer letting people use another device to sign up or authenticate.**" |
| HIG Focus and selection | "**Rely on system-provided focus effects.**"; "**Avoid changing focus without people's interaction.**"; "you need to make sure that people can bring focus to every element in your app"; "use a highlight in a list or collection". Default focus: NOT STATED. |
| HIG Lists and tables | tvOS: a focused row "highlights and slightly increases in size"; "A focused row's corners can also become rounded … don't add your own masks"; "iOS Settings uses a hierarchy of lists to help people choose options"; "the grouped style uses headers, footers, and additional space to separate groups of data" (said of iOS and iPadOS). Disclosure indicator: only under "iOS, iPadOS, visionOS". Trailing secondary values and a tvOS grouped style: NOT STATED. |
| HIG Buttons | "**In general, use a button that has a prominent visual style for the most likely action in a view.**"; "Keep the number of prominent buttons to one or two per view."; "**Use style — not size — to visually distinguish the preferred choice**"; tvOS: "No additional considerations for tvOS." |
| HIG Remotes (linked from Designing for tvOS) | "**In almost all cases, open the parent of the current screen when people press the Back button.**"; table: Back "Returns to previous screen. Exits to Apple TV Home Screen." |
| HIG Modality | "**Always give people an obvious way to dismiss a modal view.** … in macOS and tvOS apps, people expect to find a button in the main content view."; "If a modal task must contain subviews, provide a single path through the hierarchy and avoid including buttons that people might mistake for the button that dismisses the modal view." |
| HIG Layout | tvOS: "Inset primary content 60 points from the top and bottom of the screen, and 80 points from the sides."; "**Be prepared for text-size changes.** … table rows or other containers may need to grow in height so that text isn't cropped". tvOS Dynamic Type specifics: NOT STATED. |
| SwiftUI Form | tvOS 13.0+; "SwiftUI applies platform-appropriate styling to views contained inside a form"; tvOS rendering and footers: NOT STATED. |
| SwiftUI TextField | tvOS 13.0+; "Each text field style determines where and when the text field uses a prompt and label."; `onSubmit` is called "When the user submits their completed entry". What tvOS shows as the keyboard screen's heading: NOT STATED. |
| SwiftUI keyboardType(_:) | "tvOS 13.0+". The cases `.URL` and `.numberPad` are on the Virtual keyboards page, not on this one. |
| SwiftUI NavigationLink | tvOS 13.0+; value-based links with `navigationDestination(for:destination:)`. Chevron: NOT STATED. |

tvOS Settings itself has no Apple developer page; "the tvOS Settings pattern" below is the owner's description (one row per
field, label leading, value trailing, Select opens a keyboard page) and is UNVERIFIED against an Apple document.

## Screen by screen

### Forms 11 to 19 (R320, R321, R322, R323)

- **Fault:** each field was a box inside a box (the row platter plus the field), an iOS-style form; typing happened in
  place; the empty fields showed "Optional" or an example in the value position (11 to 19); the field contrast at rest was
  1.11:1 (11-form-webdav-FIELDS-AT-REST, R273).
- **Pattern:** one system row per field (`NavigationLink` with `LabeledContent`): the field name leading, the current value
  trailing in the Form's secondary level, nothing when empty, the password as dots. Select opens a page of its own with the
  field name as its heading and ONE system text field (prompt: the example, for example "https://nas.local"); Select on it
  shows the system keyboard (Virtual keyboards: "tvOS displays a linear virtual keyboard when people select a text field");
  Done or Return (`onSubmit`) stores the value and goes back to the form. Back without Done keeps the old value. The rows
  are system rows, so the focus look is the system's (Focus and selection: "Rely on system-provided focus effects"); the
  field contrast problem of R273 is gone because the form no longer draws fields.
- **Keyboard per field (R323):** Address, Device Address, Link and Server: URL keyboard; Port: number pad; Password:
  secure field; User Name, Address, Server, folders and shares: no capitalisation, no autocorrection; Name: words
  capitalised, no autocorrection. Content types: user name, password and URL, so the system can offer what it has (Virtual
  keyboards: "When you specify a semantic meaning for a text input area, the system can automatically provide a keyboard
  that matches").
- **Optional fields (R322):** said once, in the section footer ("Optional: Port, User Name and Password."), never in the
  value position. Why: Text fields says placeholder text shows "when there's no other text" to communicate purpose; in the
  value position of a row a grey word reads as the value (the owner's fault), and the footer is where a grouped list puts
  notes (Lists and tables: "the grouped style uses headers, footers").
- **System components:** `Form`, `Section` with footer, `NavigationLink`, `LabeledContent`, `TextField`, `SecureField`,
  `Picker` (FTP Encryption, unchanged: a system picker row already shows its value trailing).
- **UNVERIFIED:** that a `NavigationLink` row in a tvOS Form draws a chevron (NavigationLink page: NOT STATED); that
  `LabeledContent` puts the value trailing in secondary style on tvOS 27; that `textContentType` and
  `textInputAutocapitalization` exist on tvOS (not on the pages read); that Select on the row and then Select on the field
  is the fewest presses SwiftUI allows (R321 alternative (a) is the one-press version).

### The keyboard screen (11-form-webdav-keyboard-name, R262, R321)

- **Fault:** the heading read "Living Room" (the example) instead of "Name": the field's title was empty (R262), so tvOS
  showed the prompt.
- **Pattern:** the field's TITLE is now the field name and its prompt is the example. The entry page's own heading is the
  field name too, so the name is on screen whether or not tvOS draws the title on its keyboard screen.
- **UNVERIFIED:** which of title and prompt tvOS 27 draws as the keyboard screen's heading (TextField page: "Each text field
  style determines where and when the text field uses a prompt and label"; tvOS: NOT STATED). The new check
  `-KEYBOARD-HEADING` fails if "Name" is not on the keyboard screen or the example is drawn as a heading.

### Connect and leaving a form (R324, R325)

- **Fault:** Connect and Cancel were drawn alike, side by side (11 to 19).
- **Pattern:** Connect is the one action button of a form, `.borderedProminent`, alone in its row (Buttons: "use a button
  that has a prominent visual style for the most likely action in a view"). **No Cancel on the forms:** a form is a page
  inside the Add a Source cover; the remote's Back opens the parent, the type list (Remotes: "open the parent of the current
  screen when people press the Back button"), and a Cancel there would be a second way out that "people might mistake for
  the button that dismisses the modal view" (Modality). **Cancel stays on Add a Source's first page**, the cover's root: it
  closes the whole cover (Modality: in tvOS "people expect to find a button in the main content view").
- **Focus (R325):** the form opens on Connect when every required field is already filled (a server found on the network),
  otherwise on the first empty required row; after Done fills the last empty required field, the focus moves to Connect.
  This follows a press (Focus and selection: "Avoid changing focus without people's interaction"), so it is never moved on
  its own.
- **UNVERIFIED:** that `.borderedProminent` looks different from a row at rest on tvOS 27 (the new `-ACTIONS` check
  measures Connect's fill at rest); that setting the focus when the form reappears after the entry page works (SwiftUI
  may restore the focus to the row first).

### Errors (R327)

- **Pattern:** what is wrong with a field is plain text in the fields' section footer after Connect, naming the field
  ("Enter the address."), as before; never an alert. A connection failure, a certificate or host key to approve, and a
  device sign-in code stay system alerts: they are not validation, and each needs a decision or an acknowledgement.

### Discovery first (R326)

- **Fault:** discovery was only on the Add a Source list; a type's form offered typing only.
- **Pattern:** Add a Source keeps **Search Your Network** as its first row (all types). The form of every type the system
  can find by itself (WebDAV, SMB, NFS, SFTP, FTP, UPnP/DLNA) starts with a **Search Your Network** row (that type only);
  choosing a server there fills the form's rows and comes back to the form, with the Server Details section added and the
  focus on Connect (R325). Typing the rows is the fallback below it. The search starts only when the row is chosen, so
  opening a form never asks for local-network permission.
- **Paste and the Continuity keyboard (R330):** both come from the system text field, not from the app. What the app
  must do: use the system `TextField` and `SecureField` only (no custom keyboard or input view), set the keyboard type and
  content type, and keep the field editable while the keyboard is up. Whether an iPhone offers to type or paste into these
  fields: UNVERIFIED (none of the pages read says how the Continuity keyboard or paste works on tvOS); device checklist.

### Search Your Network (21) and Server Details (21-search-your-network-server-details, R328)

- **Fault:** the searching state was a spinner and a long sentence in a row (21); the found server's raw ID needed its own
  handling (R294, #30 item 3).
- **Pattern:** a system Form: the found servers as rows (name, type as a second line); while none is found, the
  searching sentence is the section footer (rule L3: status is never a row). Server Details is a section of the form with
  system value rows: Server ID (the whole identifier one press away, unchanged) and the address the search found.
- **UNVERIFIED:** the footer's look while the list is empty.

### Add a Source (10), not available (20), About Source Types (10-add-source-learn-more) (R329)

- **Fault:** a type that cannot be set up opened one long text about every type (20); About Source Types was a scrolling
  block of text, not a list (10-add-source-learn-more).
- **Pattern:** a hierarchy of lists (Lists and tables: "iOS Settings uses a hierarchy of lists"). About Source Types is a
  Form with one row per type; each row opens that type's About page: a Form with the type's summary, then rows for what was
  tested, what was not, or why it cannot be set up yet and what to use instead. A row for a type that is not available
  opens its own About page directly. A form's "About WebDAV" row opens the same page.
- **UNVERIFIED:** that a text row made focusable (so the remote can scroll a long page at Larger Text) gets the system
  highlight and not an odd look.

### Larger Text and Bold Text (93, 94, 99, 100, 110, 111; R295, R331)

- The rows grow with the text (Layout: "table rows or other containers may need to grow in height"); labels and values
  stay on one line each and scale (rule S1, `FittingText`). The new check `-ROWS-REACHABLE` presses Down from the top of
  the WebDAV form at Larger Text and fails unless every field row and Connect took the focus and Connect was inside the
  60 pt safe area when focused (it replaces R295's measurement of text fields, which the form no longer has).

## Checks (R331)

| Check | What it proves | Where |
|---|---|---|
| `-KEYBOARD-HEADING` (new) | the keyboard screen from the Name row shows "Name" and does not show "Living Room" as a heading; the entry page's heading is "Name" | UI test 11, `ScreenRules.keyboardHeading` (Linux tests) |
| `-NO-PLACEHOLDER-VALUES` (new) | on every empty form (11 to 19) no field row's value is "Optional", "Required" or the field's example | UI tests 11 to 19, `ScreenRules.noPlaceholderValues` |
| `-ACTIONS` (new) | exactly one action button on a form (Connect), no Cancel, Connect's fill differs from the page at rest | UI tests 11 to 19, `ScreenRules.oneProminentAction` |
| `-ROWS-REACHABLE` (new) | at Larger Text, Down from the top reaches every field row and Connect | UI test 94, `ScreenRules.everyRowReached` |
| `-FIELDS-AT-REST` (removed from the forms) | applied only to text fields drawn on the form; the form draws none now | was UI tests 11 to 19; `ScreenRules.fieldShapeAtRest` stays (Linux tests) for any later text field on a form |
| `-SAFE-AREA` of text fields (removed) | measured text fields and Cancel on the form; replaced by `-ROWS-REACHABLE` | was UI tests 11 and 94 |
| `-NAME` at 21 (changed) | now reads the Name row's value, not a text field's | UI test 21 |

## Device checklist additions (owner, Apple TV and iPhone)

1. Each form: rows look like tvOS Settings (value trailing, chevron); Select opens the entry page; the keyboard heading
   says the field name; Done fills the row.
2. The URL keyboard on Address, the number pad on Port, dots on Password.
3. With an iPhone nearby: the iPhone offers to type into the field; paste from the iPhone works.
4. Back on a form returns to the type list; Cancel on Add a Source closes it.
5. Search Your Network on a WebDAV form fills the rows from a found server.
6. Larger Text: every row and Connect reachable with Down.
