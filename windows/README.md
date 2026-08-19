# QuickSnap for Windows

The Windows counterpart of QuickSnap — a tiny tray app that does the one thing
Windows can't do natively in a single silent keystroke: **capture the whole
screen, save a PNG to a folder you choose, *and* copy it to the clipboard — with
no overlay and no clicks.**

(`Win + PrtScn` saves a file but skips the clipboard; `Win + Shift + S` does both
but forces you through the Snipping Tool overlay. QuickSnap does both, silently.)

## What it does

- **Global shortcut** `Ctrl + Alt + S` → capture the full primary screen.
- **Saves a PNG** to your chosen folder (Pictures by default; switch to Desktop,
  Downloads, or any folder from the tray menu).
- **Copies the same image to the clipboard** — paste anywhere with `Ctrl + V`.
- Tray-only — no window, no taskbar clutter.

## Requirements

- Windows 10/11 (x64)
- [.NET 8 SDK](https://dotnet.microsoft.com/download) to build from source

## Build & run

```powershell
cd windows/QuickSnap
dotnet run
```

Or produce a standalone `.exe` (no .NET install needed to run it):

```powershell
dotnet publish windows/QuickSnap/QuickSnap.csproj -c Release -r win-x64 --self-contained true -p:PublishSingleFile=true -p:IncludeNativeLibrariesForSelfExtract=true -o publish
```

The exe lands at `publish/QuickSnap.exe`. **CI builds this automatically** on
every push (see `.github/workflows/windows-build.yml`) and uploads it as a
downloadable artifact.

## How it's built

Dependency-free C# / .NET (WinForms), mirroring the macOS app's design:

| Concern            | How                                                              |
| ------------------ | ---------------------------------------------------------------- |
| Tray presence      | `NotifyIcon` (no main window, no taskbar entry)                  |
| Global shortcut    | Win32 `RegisterHotKey` via P/Invoke (no low-level hook needed)   |
| Screen capture     | `Graphics.CopyFromScreen` into a `Bitmap`                        |
| Clipboard + saving | `Clipboard.SetImage` and `Bitmap.Save(..., ImageFormat.Png)`     |
| Settings           | JSON in `%AppData%\QuickSnap\settings.json`                      |

## Roadmap

- [ ] Rebindable shortcut (fixed at `Ctrl+Alt+S` for now)
- [ ] Multi-monitor / virtual-screen capture (currently the primary screen)
- [ ] Custom tray icon and an `.msi` installer (WiX)
- [ ] Launch at login
