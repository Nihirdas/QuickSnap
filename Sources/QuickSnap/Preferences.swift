import AppKit
import Carbon.HIToolbox

/// Small wrapper over `UserDefaults` for the two things the user configures:
/// where screenshots are saved, and which shortcut triggers a capture.
final class Preferences {

    static let shared = Preferences()
    private let defaults = UserDefaults.standard

    private enum Key {
        static let saveFolder = "saveFolderPath"
        static let keyCode = "hotKeyCode"
        static let modifiers = "hotKeyModifiers"
        static let display = "hotKeyDisplay"
        static let annotateKeyCode = "annotateHotKeyCode"
        static let annotateModifiers = "annotateHotKeyModifiers"
        static let annotateDisplay = "annotateHotKeyDisplay"
    }

    // MARK: - Save folder

    static var desktopURL: URL {
        FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser
    }

    static var downloadsURL: URL {
        FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser
    }

    var saveFolderURL: URL {
        get {
            if let path = defaults.string(forKey: Key.saveFolder) {
                return URL(fileURLWithPath: path, isDirectory: true)
            }
            return Preferences.desktopURL  // default: the Desktop, like macOS itself
        }
        set { defaults.set(newValue.path, forKey: Key.saveFolder) }
    }

    // MARK: - Capture (save & copy) hotkey — defaults to ⌃⇧C

    var keyCode: UInt32 {
        get {
            guard defaults.object(forKey: Key.keyCode) != nil else {
                return UInt32(kVK_ANSI_C)
            }
            return UInt32(defaults.integer(forKey: Key.keyCode))
        }
        set { defaults.set(Int(newValue), forKey: Key.keyCode) }
    }

    var carbonModifiers: UInt32 {
        get {
            guard defaults.object(forKey: Key.modifiers) != nil else {
                return UInt32(controlKey | shiftKey)
            }
            return UInt32(defaults.integer(forKey: Key.modifiers))
        }
        set { defaults.set(Int(newValue), forKey: Key.modifiers) }
    }

    var shortcutDisplay: String {
        get { defaults.string(forKey: Key.display) ?? "⌃⇧C" }
        set { defaults.set(newValue, forKey: Key.display) }
    }

    // MARK: - Annotate hotkey — defaults to ⌃⇧Q (⇧⌘Q is macOS Log Out, so avoided)

    var annotateKeyCode: UInt32 {
        get {
            guard defaults.object(forKey: Key.annotateKeyCode) != nil else {
                return UInt32(kVK_ANSI_Q)
            }
            return UInt32(defaults.integer(forKey: Key.annotateKeyCode))
        }
        set { defaults.set(Int(newValue), forKey: Key.annotateKeyCode) }
    }

    var annotateCarbonModifiers: UInt32 {
        get {
            guard defaults.object(forKey: Key.annotateModifiers) != nil else {
                return UInt32(controlKey | shiftKey)
            }
            return UInt32(defaults.integer(forKey: Key.annotateModifiers))
        }
        set { defaults.set(Int(newValue), forKey: Key.annotateModifiers) }
    }

    var annotateShortcutDisplay: String {
        get { defaults.string(forKey: Key.annotateDisplay) ?? "⌃⇧Q" }
        set { defaults.set(newValue, forKey: Key.annotateDisplay) }
    }
}
