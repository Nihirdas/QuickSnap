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

    // MARK: - Hotkey (defaults to ⌃⌥⌘S)

    var keyCode: UInt32 {
        get {
            guard defaults.object(forKey: Key.keyCode) != nil else {
                return UInt32(kVK_ANSI_S)
            }
            return UInt32(defaults.integer(forKey: Key.keyCode))
        }
        set { defaults.set(Int(newValue), forKey: Key.keyCode) }
    }

    var carbonModifiers: UInt32 {
        get {
            guard defaults.object(forKey: Key.modifiers) != nil else {
                return UInt32(controlKey | optionKey | cmdKey)
            }
            return UInt32(defaults.integer(forKey: Key.modifiers))
        }
        set { defaults.set(Int(newValue), forKey: Key.modifiers) }
    }

    var shortcutDisplay: String {
        get { defaults.string(forKey: Key.display) ?? "⌃⌥⌘S" }
        set { defaults.set(newValue, forKey: Key.display) }
    }
}
