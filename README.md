# QuickSnap

A tiny, native macOS menu-bar app: press one shortcut to capture your whole
screen, save it as a PNG to a folder of your choice, and copy it to the
clipboard — all in a single keystroke.

No Dock icon, no window in the way, no dependencies. It just lives in your menu
bar and waits for the shortcut.

---

## What it does

- **Global shortcut** → capture the full screen (default `⌃⌥⌘S`, rebindable).
- **Saves a PNG** to the folder you pick (Desktop by default; switch to Downloads
  or any folder in Settings).
- **Copies the same image to the clipboard** so you can paste it straight away.
- Menu-bar only — lightweight and out of the way.

## Requirements

- macOS 14 or later
- Swift toolchain (comes with the Xcode Command Line Tools: `xcode-select --install`)

## Build & run

```bash
git clone https://github.com/Nihirdas/QuickSnap.git
cd QuickSnap
./build_app.sh
open build/QuickSnap.app
```

`build_app.sh` compiles the app and wraps it in a proper `QuickSnap.app`
bundle, then ad-hoc code-signs it.

### First run

1. QuickSnap appears in your menu bar (a small camera icon).
2. The first time you capture, macOS asks for **Screen Recording** permission —
   allow it under *System Settings › Privacy & Security › Screen Recording*, then
   capture again.
3. Press `⌃⌥⌘S` (or your custom shortcut) anywhere. The screen is saved and
   copied; the menu-bar icon flashes a checkmark to confirm.

> Because the app is ad-hoc signed (not notarized), macOS may re-ask for Screen
> Recording permission after a rebuild. That's expected for a local dev build.

## Settings

Open **Settings…** from the menu-bar menu to:

- choose the save folder (Desktop / Downloads / any folder), and
- record a new capture shortcut — click the field and press your combination.

## How it's built

A small, dependency-free Swift package. The interesting pieces:

| Concern            | How                                                                 |
| ------------------ | ------------------------------------------------------------------- |
| Menu-bar presence  | `NSStatusItem` + activation policy `.accessory` (no Dock icon)      |
| Global shortcut    | Carbon `RegisterEventHotKey` — fires app-wide, no Accessibility permission needed |
| Screen capture     | `ScreenCaptureKit` (`SCScreenshotManager`), Apple's modern capture API |
| Clipboard + saving | `NSPasteboard` and `NSBitmapImageRep` → PNG                         |
| Settings UI        | AppKit — an `NSWindow` with a custom `NSView` shortcut recorder     |

## Roadmap

- [ ] Region / window capture (not just full screen)
- [ ] Quick annotation (arrow, box, redaction) before copying
- [ ] Launch at login
- [ ] Optional cross-platform build (Windows)

## License

[MIT](LICENSE)
