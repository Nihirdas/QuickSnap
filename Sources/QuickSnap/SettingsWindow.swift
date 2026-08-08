import AppKit
import Carbon.HIToolbox

/// The Settings window (AppKit): pick a save folder and record a capture shortcut.
final class SettingsWindowController: NSWindowController {

    /// Called after any change so the app can re-register the hotkey / refresh the menu.
    private let onChange: () -> Void

    private let pathLabel = NSTextField(labelWithString: "")
    private let recorder = RecorderView()

    init(onChange: @escaping () -> Void) {
        self.onChange = onChange
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 250),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "QuickSnap Settings"
        window.isReleasedWhenClosed = false
        super.init(window: window)
        buildUI()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    // MARK: - Layout

    private func buildUI() {
        guard let window = window else { return }

        let title = label("QuickSnap", font: .systemFont(ofSize: 20, weight: .bold))
        let saveHeading = label("Save screenshots to", font: .boldSystemFont(ofSize: 13))

        pathLabel.stringValue = Preferences.shared.saveFolderURL.path
        pathLabel.lineBreakMode = .byTruncatingMiddle
        pathLabel.textColor = .secondaryLabelColor
        pathLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)
        pathLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let desktopButton = NSButton(title: "Desktop", target: self, action: #selector(chooseDesktop))
        let downloadsButton = NSButton(title: "Downloads", target: self, action: #selector(chooseDownloads))
        let chooseButton = NSButton(title: "Choose…", target: self, action: #selector(chooseCustom))

        let folderRow = NSStackView(views: [pathLabel, desktopButton, downloadsButton, chooseButton])
        folderRow.orientation = .horizontal
        folderRow.spacing = 8

        let shortcutHeading = label("Capture shortcut", font: .boldSystemFont(ofSize: 13))

        recorder.display = Preferences.shared.shortcutDisplay
        recorder.onCapture = { [weak self] keyCode, modifiers, text in
            Preferences.shared.keyCode = keyCode
            Preferences.shared.carbonModifiers = modifiers
            Preferences.shared.shortcutDisplay = text
            self?.onChange()
        }
        recorder.translatesAutoresizingMaskIntoConstraints = false
        recorder.heightAnchor.constraint(equalToConstant: 34).isActive = true
        recorder.widthAnchor.constraint(equalToConstant: 220).isActive = true

        let caption = label("Click the field, then press your combination (include ⌘, ⌥ or ⌃).",
                            font: .systemFont(ofSize: 11))
        caption.textColor = .secondaryLabelColor

        let stack = NSStackView(views: [title, saveHeading, folderRow, shortcutHeading, recorder, caption])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.setCustomSpacing(20, after: title)
        stack.setCustomSpacing(20, after: folderRow)

        let content = NSView()
        content.addSubview(stack)
        window.contentView = content

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -24),
            stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 24),
            folderRow.widthAnchor.constraint(equalTo: stack.widthAnchor)
        ])
    }

    private func label(_ text: String, font: NSFont) -> NSTextField {
        let field = NSTextField(labelWithString: text)
        field.font = font
        return field
    }

    // MARK: - Actions

    @objc private func chooseDesktop() { setFolder(Preferences.desktopURL) }
    @objc private func chooseDownloads() { setFolder(Preferences.downloadsURL) }

    @objc private func chooseCustom() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        if panel.runModal() == .OK, let url = panel.url {
            setFolder(url)
        }
    }

    private func setFolder(_ url: URL) {
        Preferences.shared.saveFolderURL = url
        pathLabel.stringValue = url.path
        onChange()
    }
}

// MARK: - Shortcut recorder

/// A small clickable field that records the next key combination pressed.
final class RecorderView: NSView {

    var onCapture: ((UInt32, UInt32, String) -> Void)?
    var display: String = "" {
        didSet { textField.stringValue = recording ? "Press keys…" : display }
    }

    private var recording = false
    private let textField = NSTextField(labelWithString: "")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 6
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.separatorColor.cgColor
        layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor

        textField.alignment = .center
        textField.translatesAutoresizingMaskIntoConstraints = false
        addSubview(textField)
        NSLayoutConstraint.activate([
            textField.centerXAnchor.constraint(equalTo: centerXAnchor),
            textField.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
        textField.stringValue = display
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var intrinsicContentSize: NSSize { NSSize(width: 220, height: 34) }
    override var acceptsFirstResponder: Bool { true }

    override func mouseDown(with event: NSEvent) {
        recording = true
        textField.stringValue = "Press keys…"
        window?.makeFirstResponder(self)
    }

    override func keyDown(with event: NSEvent) {
        guard recording else {
            super.keyDown(with: event)
            return
        }

        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let carbon = carbonModifiers(from: flags)

        // Require at least one of ⌘/⌥/⌃ so we don't hijack plain typing.
        guard carbon & UInt32(cmdKey | optionKey | controlKey) != 0 else {
            NSSound.beep()
            return
        }

        let keyCode = UInt32(event.keyCode)
        let keyLabel = (event.charactersIgnoringModifiers ?? "").uppercased()
        let text = modifierSymbols(flags) + keyLabel

        recording = false
        display = text
        textField.stringValue = text
        onCapture?(keyCode, carbon, text)

        window?.makeFirstResponder(nil)
    }

    override func resignFirstResponder() -> Bool {
        recording = false
        textField.stringValue = display
        return super.resignFirstResponder()
    }
}

private func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
    var carbon: UInt32 = 0
    if flags.contains(.command) { carbon |= UInt32(cmdKey) }
    if flags.contains(.option)  { carbon |= UInt32(optionKey) }
    if flags.contains(.control) { carbon |= UInt32(controlKey) }
    if flags.contains(.shift)   { carbon |= UInt32(shiftKey) }
    return carbon
}

private func modifierSymbols(_ flags: NSEvent.ModifierFlags) -> String {
    var symbols = ""
    if flags.contains(.control) { symbols += "⌃" }
    if flags.contains(.option)  { symbols += "⌥" }
    if flags.contains(.shift)   { symbols += "⇧" }
    if flags.contains(.command) { symbols += "⌘" }
    return symbols
}
