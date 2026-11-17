# Top Shelf

What it is: the row of titles the system shows above the app's icon on the Home Screen when the app is selected. This app shows Continue Watching first, then Next Up.

## How it works
1. The app (`AppServices.writeTopShelf`) asks `TopShelfBuilder` (AppLogic, tested) for the titles and writes `topshelf.json` into the App Group folder `group.com.liamp.videoplayer/TopShelf` (`TopShelfSnapshotStore.write`, UserData, tested).
2. The extension (`TopShelf/TopShelfProvider.swift`, never compiled) reads that folder with `TopShelfSnapshotStore.read`, which never throws: a missing, empty, oversized, damaged or wrong-version file, or an item whose picture is missing, means "show nothing".
3. Each item carries a `videoplayer://item/<id>` link (`DeepLink`, tested). Choosing it opens the app on that title's page (`RootView.onOpenURL`). Links hold only a number: never a path, server address or password.

## Honest state
- **No pictures exist yet** (OPEN_QUESTIONS.md R74: no source supplies artwork), so the row stays empty. The extension leaves out items without a picture rather than show a blank card.
- The folder is not durable storage: the system may delete it when space is low (docs/STORAGE_MODEL.md). The app rewrites it after every scan.
- Settings > Home Screen says the Top Shelf row follows the same Continue Watching length.
- API pages the extension code was checked against: docs/API_USAGE.md (TVTopShelfSectionedContent, TVTopShelfSectionedItem).
- Never compiled, never shown on an Apple TV. Needs the App Group identifier registered in the developer account before the first signed build (docs/CODEMAGIC_SETUP.md).
