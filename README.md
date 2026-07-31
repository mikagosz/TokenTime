# TokenTime

A macOS menu bar app that tracks when your Claude usage windows reset — across as
many accounts and as many Macs as you use.

Click the menu bar icon and you get every account with a live countdown. The label
in the menu bar always shows the one resetting soonest, so a glance is enough.

> The interface is in Polish.

---

## Why

If you work across several Claude accounts, the only thing you actually need to
know is *when does the next window open again*. That answer normally lives in your
head or in a note somewhere. TokenTime puts it in the menu bar and keeps it there.

## Features

### Accounts and countdowns

- **Any number of accounts**, each with an editable name (double-click or the
  pencil icon).
- **Set a reset with one text field.** Type `4h`, `1h30m`, `90m`, `45s` — or just
  `4`, which means four hours. The popover previews the resulting clock time and
  rejects anything it can't parse.
- **Native countdowns** via `Text(timerInterval:)`, so the numbers tick without a
  timer of our own running behind the window.
- **Status at a glance**, mirrored by both the card colour and its progress bar:
  - **blue** — running, more than an hour left
  - **amber** — running, under an hour
  - **green** — the window has reset and is ready to use again
- **Reset** clears the counter and immediately opens the field for the next one.
- **Progress bar** measured against a configurable window length (5 hours by
  default).

### Across your Macs

- **Which computer is this account logged in on?** Each account carries toggles
  for your machines — Mac mini, iMac, MacBook, Mac Studio — so you can see at a
  glance where a profile is currently signed in. Pick which of the four you
  actually own in Settings and only those appear.
- **Sync via iCloud Drive.** Accounts live in
  `~/Library/Mobile Documents/com~apple~CloudDocs/TokenTime/accounts.json`, polled
  every seven seconds, so a reset you set on one Mac shows up on the others.
  Changes arriving from another machine don't bounce back out as a new write.
- **Local fallback** — if iCloud Drive isn't available the accounts are kept in
  `UserDefaults`, and nothing is lost.

### Menu bar behaviour

- The label shows the **shortest active countdown**, refreshed every 30 seconds by
  a lightweight task (`Text(timerInterval:)` doesn't animate inside a
  `MenuBarExtra` label).
- Separate light and dark icon variants.
- **No Dock icon** — the app runs as an accessory (`setActivationPolicy(.accessory)`),
  so it stays out of ⌘-Tab and the Dock without any `Info.plist` surgery.
- **Launch at login**, via `SMAppService`.

---

## Privacy

TokenTime makes **no network connections** and talks to no API — not Anthropic's,
not anyone's. It knows nothing about your accounts beyond the names you type and
the times you enter. There is no telemetry and no analytics. The only thing that
leaves your Mac is the accounts file, and only into your own iCloud Drive.

## Requirements

- macOS 26 or later
- Xcode 26 or later to build

## Building

```bash
git clone https://github.com/mikagosz/TokenTime.git
cd TokenTime
open TokenTime.xcodeproj
```

Then press ⌘R.

The project pins a local code-signing identity that won't be in your keychain. Set
**Signing & Capabilities → Signing Certificate** to *Sign to Run Locally*, or point
it at your own.

The app is deliberately **not sandboxed**: reaching the iCloud Drive folder
directly is what lets it sync without a paid Apple Developer account. That also
means it isn't headed for the App Store.

## Project layout

| File | Role |
|---|---|
| `ContentView.swift` | `@main` app with `MenuBarExtra` and the `AppDelegate` |
| `Account.swift` | account model, reset status, computer list |
| `AccountStore.swift` | storage, iCloud sync, menu bar summary |
| `MenuBarView.swift` | the main panel |
| `AccountCardView.swift` | a single account card |
| `MenuBarLabel.swift` | the menu bar label |
| `SettingsView.swift` | which computers you own |
| `LaunchAtLogin.swift` | login item registration |
| `TokenTimeGlyph.swift` | app glyph |

## Licence

MIT — see [LICENSE](LICENSE).
