import AppKit
import Carbon.HIToolbox

/// A single system-wide hotkey built on Carbon's `RegisterEventHotKey`.
///
/// Why Carbon? It's the lightest way to get a *global* shortcut (one that fires
/// even when QuickSnap isn't the active app) and, unlike a CGEvent tap, it does
/// not require Accessibility permission. It's an old API but still fully
/// supported, and it keeps QuickSnap dependency-free.
final class HotKey {

    /// Called on the main thread when the hotkey is pressed.
    var onFire: (() -> Void)?

    private var hotKeyRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    private let hotKeyID = EventHotKeyID(signature: fourCharCode("QSNP"), id: 1)

    /// Registers (or re-registers) the hotkey.
    /// - Parameters:
    ///   - keyCode: a virtual key code (same values as `NSEvent.keyCode`).
    ///   - carbonModifiers: a mask of `cmdKey`, `optionKey`, `controlKey`, `shiftKey`.
    func register(keyCode: UInt32, carbonModifiers: UInt32) {
        unregister()
        installHandlerIfNeeded()
        RegisterEventHotKey(keyCode, carbonModifiers, hotKeyID,
                            GetApplicationEventTarget(), 0, &hotKeyRef)
    }

    func unregister() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
    }

    private func installHandlerIfNeeded() {
        guard eventHandler == nil else { return }

        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                 eventKind: UInt32(kEventHotKeyPressed))

        // The C callback can't capture Swift context, so we hand it a pointer to
        // `self` via `userData` and reconstruct the instance inside.
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()

        InstallEventHandler(GetApplicationEventTarget(), { _, event, userData -> OSStatus in
            guard let userData, let event else { return noErr }
            let instance = Unmanaged<HotKey>.fromOpaque(userData).takeUnretainedValue()

            var firedID = EventHotKeyID()
            GetEventParameter(event,
                              EventParamName(kEventParamDirectObject),
                              EventParamType(typeEventHotKeyID),
                              nil,
                              MemoryLayout<EventHotKeyID>.size,
                              nil,
                              &firedID)

            if firedID.signature == instance.hotKeyID.signature,
               firedID.id == instance.hotKeyID.id {
                DispatchQueue.main.async { instance.onFire?() }
            }
            return noErr
        }, 1, &spec, selfPtr, &eventHandler)
    }

    deinit {
        unregister()
        if let eventHandler {
            RemoveEventHandler(eventHandler)
        }
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
