import AppKit

/// Owns the menu-bar item, the global hotkey, and the capture flow.
final class AppDelegate: NSObject, NSApplicationDelegate {

    private var statusItem: NSStatusItem!
    private let captureHotKey = HotKey(id: 1)
    private let annotateHotKey = HotKey(id: 2)
    private var settingsController: SettingsWindowController?
    private var annotateEditor: AnnotationEditorWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        setUpStatusItem()
        registerHotKeys()
    }

    // MARK: - Menu bar

    private func setUpStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "camera.viewfinder",
                                   accessibilityDescription: "QuickSnap")
            button.image?.isTemplate = true
        }
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
        captureHotKey.register(keyCode: Preferences.shared.keyCode,
                               carbonModifiers: Preferences.shared.carbonModifiers)

        annotateHotKey.onFire = { [weak self] in self?.triggerAnnotate() }
        annotateHotKey.register(keyCode: Preferences.shared.annotateKeyCode,
                                carbonModifiers: Preferences.shared.annotateCarbonModifiers)
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

    private func openAnnotationEditor(with image: CGImage) {
        let editor = AnnotationEditorWindowController(
            image: image,
            saveFolder: Preferences.shared.saveFolderURL,
            onClose: { [weak self] in self?.annotateEditor = nil }
        )
        annotateEditor = editor
        NSApp.activate(ignoringOtherApps: true)
        editor.showWindow(nil)
        editor.window?.makeKeyAndOrderFront(nil)
    }

    /// Briefly swap the menu-bar icon to a checkmark as capture feedback.
    private func flashSuccess() {
        guard let button = statusItem.button else { return }
        let original = button.image
        button.image = NSImage(systemSymbolName: "checkmark.circle.fill",
                               accessibilityDescription: "Captured")
        button.image?.isTemplate = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
            button.image = original
        }
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
