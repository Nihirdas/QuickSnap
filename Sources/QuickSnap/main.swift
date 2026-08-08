import AppKit

// QuickSnap is a menu-bar utility, so we launch NSApplication by hand instead
// of using @main. This lets us set the activation policy to `.accessory`, which
// means: no Dock icon and no app menu — it lives only in the menu bar.
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
