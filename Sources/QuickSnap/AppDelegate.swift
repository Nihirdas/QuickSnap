import AppKit

/// Owns the menu-bar item, the global hotkey, and the capture flow.
final class AppDelegate: NSObject, NSApplicationDelegate {

    private var statusItem: NSStatusItem!
    private let captureHotKey = HotKey(id: 1)
    private let annotateHotKey = HotKey(id: 2)
    private let cropHotKey = HotKey(id: 3)
    private var settingsController: SettingsWindowController?
    private var annotateEditor: AnnotationEditorWindowController?
    private var cropController: CropSelectionController?

    /// The normal menu-bar icon. Kept as the single source of truth so the brief
    /// "success" flash always reverts to *this*, never to a stale checkmark.
    private let baseStatusIcon: NSImage? = {
        let image = NSImage(systemSymbolName: "camera.viewfinder", accessibilityDescription: "QuickSnap")
        image?.isTemplate = true
        return image
    }()
    private var flashRevert: DispatchWorkItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        setUpStatusItem()
        registerHotKeys()
    }

    // MARK: - Menu bar

    private func setUpStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = baseStatusIcon
        rebuildMenu()
    }

    /// The menu is rebuilt whenever preferences change so it always shows the
    /// current save folder and shortcut.
    private func rebuildMenu() {
        let menu = NSMenu()

        let capture = NSMenuItem(title: "Capture Now",
                                 action: #selector(captureNow),
                                 keyEquivalent: "")
        capture.target = self
        menu.addItem(capture)

        let annotate = NSMenuItem(title: "Capture & Annotate…",
                                  action: #selector(captureAnnotate),
                                  keyEquivalent: "")
        annotate.target = self
        menu.addItem(annotate)

        let cropAnnotate = NSMenuItem(title: "Crop & Annotate…",
                                      action: #selector(cropAnnotate),
                                      keyEquivalent: "")
        cropAnnotate.target = self
        menu.addItem(cropAnnotate)

        menu.addItem(.separator())

        // "Save To" submenu with the two common folders + a custom picker.
        let saveTo = NSMenuItem(title: "Save To", action: nil, keyEquivalent: "")
        let saveMenu = NSMenu()
        let current = Preferences.shared.saveFolderURL.standardizedFileURL
        for (label, url) in [("Desktop", Preferences.desktopURL),
                             ("Downloads", Preferences.downloadsURL)] {
            let item = NSMenuItem(title: label, action: #selector(selectFolder(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = url
            item.state = (url.standardizedFileURL == current) ? .on : .off
            saveMenu.addItem(item)
        }
        let choose = NSMenuItem(title: "Choose Folder…", action: #selector(chooseFolder), keyEquivalent: "")
        choose.target = self
        saveMenu.addItem(choose)
        saveTo.submenu = saveMenu
        menu.addItem(saveTo)

        let folderInfo = NSMenuItem(title: "→ \(Preferences.shared.saveFolderURL.path)",
                                    action: nil, keyEquivalent: "")
        folderInfo.isEnabled = false
        menu.addItem(folderInfo)

        menu.addItem(.separator())

        let captureShortcut = NSMenuItem(title: "Save & Copy: \(Preferences.shared.shortcutDisplay)",
                                         action: nil, keyEquivalent: "")
        captureShortcut.isEnabled = false
        menu.addItem(captureShortcut)

        let annotateShortcut = NSMenuItem(title: "Annotate: \(Preferences.shared.annotateShortcutDisplay)",
                                          action: nil, keyEquivalent: "")
        annotateShortcut.isEnabled = false
        menu.addItem(annotateShortcut)

        let cropShortcut = NSMenuItem(title: "Crop & Annotate: \(Preferences.shared.cropShortcutDisplay)",
                                      action: nil, keyEquivalent: "")
        cropShortcut.isEnabled = false
        menu.addItem(cropShortcut)

        let settings = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)

        menu.addItem(.separator())

        let quit = NSMenuItem(title: "Quit QuickSnap",
                              action: #selector(NSApplication.terminate(_:)),
                              keyEquivalent: "q")
        menu.addItem(quit)

        statusItem.menu = menu
    }

    // MARK: - Menu actions

    @objc private func captureNow() {
        triggerCapture()
    }

    @objc private func captureAnnotate() {
        triggerAnnotate()
    }

    @objc private func cropAnnotate() {
        triggerCropAnnotate()
    }

    @objc private func selectFolder(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL else { return }
        Preferences.shared.saveFolderURL = url
        rebuildMenu()
    }

    @objc private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        NSApp.activate(ignoringOtherApps: true)
        if panel.runModal() == .OK, let url = panel.url {
            Preferences.shared.saveFolderURL = url
            rebuildMenu()
        }
    }

    @objc private func openSettings() {
        NSApp.activate(ignoringOtherApps: true)
        if settingsController == nil {
            settingsController = SettingsWindowController(
                onChange: { [weak self] in self?.preferencesChanged() }
            )
        }
        settingsController?.window?.center()
        settingsController?.showWindow(nil)
        settingsController?.window?.makeKeyAndOrderFront(nil)
    }

    private func preferencesChanged() {
        registerHotKeys()
        rebuildMenu()
    }

    // MARK: - Hotkeys

    private func registerHotKeys() {
        captureHotKey.onFire = { [weak self] in self?.triggerCapture() }
        let captureOK = captureHotKey.register(keyCode: Preferences.shared.keyCode,
                                               carbonModifiers: Preferences.shared.carbonModifiers)

        annotateHotKey.onFire = { [weak self] in self?.triggerAnnotate() }
        let annotateOK = annotateHotKey.register(keyCode: Preferences.shared.annotateKeyCode,
                                                 carbonModifiers: Preferences.shared.annotateCarbonModifiers)

        cropHotKey.onFire = { [weak self] in self?.triggerCropAnnotate() }
        let cropOK = cropHotKey.register(keyCode: Preferences.shared.cropKeyCode,
                                         carbonModifiers: Preferences.shared.cropCarbonModifiers)

        var failures: [String] = []
        if !captureOK { failures.append("Save & Copy — \(Preferences.shared.shortcutDisplay)") }
        if !annotateOK { failures.append("Annotate — \(Preferences.shared.annotateShortcutDisplay)") }
        if !cropOK { failures.append("Crop & Annotate — \(Preferences.shared.cropShortcutDisplay)") }
        if !failures.isEmpty { warnRegistrationFailed(failures) }
    }

    private func warnRegistrationFailed(_ shortcuts: [String]) {
        let alert = NSAlert()
        alert.messageText = "Couldn’t register a shortcut"
        alert.informativeText = "Another app is already using "
            + (shortcuts.count == 1 ? "this shortcut" : "these shortcuts")
            + ", so QuickSnap couldn’t claim "
            + (shortcuts.count == 1 ? "it" : "them") + ":\n\n• "
            + shortcuts.joined(separator: "\n• ")
            + "\n\nPick a different combination in Settings."
        alert.addButton(withTitle: "Open Settings")
        alert.addButton(withTitle: "Later")
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn {
            openSettings()
        }
    }

    // MARK: - Capture flow

    private func triggerCapture() {
        Task { @MainActor in
            do {
                let image = try await ScreenCapturer.captureMainDisplay()
                try CaptureOutput.save(image: image, to: Preferences.shared.saveFolderURL)
                CaptureOutput.copyToClipboard(image: image)
                flashSuccess()
            } catch {
                showCaptureError(error)
            }
        }
    }

    // MARK: - Annotate flow

    private func triggerAnnotate() {
        Task { @MainActor in
            do {
                let image = try await ScreenCapturer.captureMainDisplay()
                openAnnotationEditor(with: image)
            } catch {
                showCaptureError(error)
            }
        }
    }

    private func openAnnotationEditor(with image: CGImage, autosave: Bool = false) {
        let editor = AnnotationEditorWindowController(
            image: image,
            saveFolder: Preferences.shared.saveFolderURL,
            autosaveOnClose: autosave,
            onClose: { [weak self] in self?.annotateEditor = nil }
        )
        if autosave {
            // "Crop Again" discards this editor and restarts the crop flow.
            editor.onCropAgain = { [weak self] in self?.triggerCropAnnotate() }
        }
        annotateEditor = editor
        NSApp.activate(ignoringOtherApps: true)
        editor.showWindow(nil)
        editor.window?.makeKeyAndOrderFront(nil)
    }

    // MARK: - Crop & Annotate flow

    private func triggerCropAnnotate() {
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                // Freeze the screen first so the selection overlay never ends up
                // in the shot, then let the user drag out a region.
                let image = try await ScreenCapturer.captureMainDisplay()
                let controller = CropSelectionController(image: image) { [weak self] cropped in
                    guard let self else { return }
                    self.cropController = nil
                    guard let cropped else { return }   // Esc or stray click = cancel

                    // On crop: save the raw region + copy it to the clipboard
                    // right away, as a safety net, before opening the editor.
                    do {
                        try CaptureOutput.save(image: cropped, to: Preferences.shared.saveFolderURL)
                    } catch {
                        self.showCaptureError(error)
                        return
                    }
                    CaptureOutput.copyToClipboard(image: cropped)
                    self.flashSuccess()

                    // Then open the editor in autosave mode: closing it saves the
                    // annotated version too (only if something was drawn).
                    self.openAnnotationEditor(with: cropped, autosave: true)
                }
                cropController = controller
                controller.begin()
            } catch {
                showCaptureError(error)
            }
        }
    }

    /// Briefly swap the menu-bar icon to a checkmark as capture feedback, plus a
    /// silent haptic nudge. Always reverts to `baseStatusIcon` and cancels any
    /// in-flight revert, so overlapping captures can't leave it stuck on the
    /// checkmark.
    private func flashSuccess() {
        guard let button = statusItem.button else { return }
        Feedback.nudge()

        flashRevert?.cancel()
        let check = NSImage(systemSymbolName: "checkmark.circle.fill",
                            accessibilityDescription: "Captured")
        check?.isTemplate = true
        button.image = check

        let revert = DispatchWorkItem { [weak self] in
            self?.statusItem.button?.image = self?.baseStatusIcon
        }
        flashRevert = revert
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8, execute: revert)
    }

    private func showCaptureError(_ error: Error) {
        let alert = NSAlert()
        alert.messageText = "Couldn’t capture the screen"
        alert.informativeText = """
            \(error.localizedDescription)

            If this is the first run, grant QuickSnap access under
            System Settings › Privacy & Security › Screen Recording,
            then try again.
            """
        alert.addButton(withTitle: "Open Privacy Settings")
        alert.addButton(withTitle: "Cancel")
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn {
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
                NSWorkspace.shared.open(url)
            }
        }
    }
}
