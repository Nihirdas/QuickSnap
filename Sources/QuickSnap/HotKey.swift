import AppKit
import Carbon.HIToolbox

/// A system-wide hotkey built on Carbon's `RegisterEventHotKey`.
///
/// Why Carbon? It's the lightest way to get a *global* shortcut (fires even when
/// QuickSnap isn't the active app) and, unlike a CGEvent tap, needs no
/// Accessibility permission.
///
/// All hotkeys share ONE Carbon event handler that dispatches by id. Installing a
/// separate handler per hotkey does NOT work: a handler that returns `noErr` tells
/// Carbon the event was handled, so the other handlers never run — meaning only
/// the last-registered hotkey would ever fire.
final class HotKey {

    /// Called on the main thread when this hotkey is pressed.
    var onFire: (() -> Void)?

    private let id: UInt32
    private var hotKeyRef: EventHotKeyRef?

    private static let signature = fourCharCode("QSNP")
    private static var registry: [UInt32: HotKey] = [:]
    private static var sharedHandlerInstalled = false

    /// - Parameter id: a per-hotkey identifier used to route events.
    init(id: UInt32) {
        self.id = id
    }

    /// Registers (or re-registers) the hotkey.
    /// - Parameters:
    ///   - keyCode: a virtual key code (same values as `NSEvent.keyCode`).
    ///   - carbonModifiers: a mask of `cmdKey`, `optionKey`, `controlKey`, `shiftKey`.
    /// - Returns: `true` if the OS accepted the hotkey (false usually means the
    ///   combination is already claimed by another app).
    @discardableResult
    func register(keyCode: UInt32, carbonModifiers: UInt32) -> Bool {
        unregister()
        HotKey.installSharedHandlerIfNeeded()
        HotKey.registry[id] = self

        let hotKeyID = EventHotKeyID(signature: HotKey.signature, id: id)
        let status = RegisterEventHotKey(keyCode, carbonModifiers, hotKeyID,
                                         GetApplicationEventTarget(), 0, &hotKeyRef)
        return status == noErr && hotKeyRef != nil
    }

    func unregister() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
        HotKey.registry[id] = nil
    }

    /// Installed once for the whole app; routes each hotkey event to its instance.
    private static func installSharedHandlerIfNeeded() {
        guard !sharedHandlerInstalled else { return }
        sharedHandlerInstalled = true

        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                 eventKind: UInt32(kEventHotKeyPressed))

        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ -> OSStatus in
            guard let event else { return OSStatus(eventNotHandledErr) }

            var firedID = EventHotKeyID()
            GetEventParameter(event,
                              EventParamName(kEventParamDirectObject),
                              EventParamType(typeEventHotKeyID),
                              nil,
                              MemoryLayout<EventHotKeyID>.size,
                              nil,
                              &firedID)

            guard firedID.signature == HotKey.signature,
                  let hotKey = HotKey.registry[firedID.id] else {
                return OSStatus(eventNotHandledErr)
            }

            DispatchQueue.main.async { hotKey.onFire?() }
            return noErr
        }, 1, &spec, nil, nil)
    }

    deinit {
        unregister()
    }
}

/// Packs a 4-character string into an `OSType` (used for Carbon signatures).
private func fourCharCode(_ string: String) -> OSType {
    var result: OSType = 0
    for byte in string.utf8.prefix(4) {
        result = (result << 8) + OSType(byte)
    }
    return result
}
