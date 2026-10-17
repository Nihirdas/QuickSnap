import AppKit

/// Presents a full-screen "freeze" of the main display and lets the user
/// drag-select a rectangle to crop.
///
/// The screen is captured *first* and shown as a still image, so the dimming
/// overlay and selection rectangle never end up in the shot — the same trick
/// macOS's own screenshot tool uses.
final class CropSelectionController {

    private var overlayWindow: OverlayWindow?
    private let cgImage: CGImage
    private let completion: (CGImage?) -> Void

    /// - Parameters:
    ///   - image: a full-display capture to select a region from.
    ///   - completion: the cropped image, or `nil` if the user cancelled.
    init(image: CGImage, completion: @escaping (CGImage?) -> Void) {
        self.cgImage = image
        self.completion = completion
    }

    func begin() {
        let screen = NSScreen.main ?? NSScreen.screens.first!
        // .frame (not .visibleFrame) so the overlay covers the whole display —
        // menu bar included — and lines up 1:1 with the full-display capture.
        let frame = screen.frame

        let window = OverlayWindow(
            contentRect: frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        window.level = .screenSaver
        // Appear over full-screen apps (e.g. a meeting) and on whatever Space
        // the user is currently on.
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.isOpaque = true
        window.backgroundColor = .black
        window.ignoresMouseEvents = false

        let view = CropSelectionView(frame: NSRect(origin: .zero, size: frame.size))
        view.image = NSImage(cgImage: cgImage,
                             size: NSSize(width: cgImage.width, height: cgImage.height))
        view.onFinish = { [weak self] rect in
            self?.finish(with: rect)
        }
        window.contentView = view

        overlayWindow = window
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(view)
    }

    /// Maps a selection rectangle (in the overlay view's top-left points) to the
    /// captured image's pixel space and crops it.
    private func finish(with viewRect: CGRect?) {
        let window = overlayWindow
        overlayWindow = nil
        window?.orderOut(nil)

        guard let viewRect,
              let bounds = window?.contentView?.bounds,
              bounds.width > 0, bounds.height > 0 else {
            completion(nil)
            return
        }

        let scaleX = CGFloat(cgImage.width) / bounds.width
        let scaleY = CGFloat(cgImage.height) / bounds.height
        // The view is flipped (top-left origin), matching CGImage.cropping's
        // upper-left coordinate space, so this maps straight across.
        var pixelRect = CGRect(x: viewRect.origin.x * scaleX,
                               y: viewRect.origin.y * scaleY,
                               width: viewRect.width * scaleX,
                               height: viewRect.height * scaleY).integral

        pixelRect = pixelRect.intersection(
            CGRect(x: 0, y: 0, width: cgImage.width, height: cgImage.height)
        )

        guard pixelRect.width >= 1, pixelRect.height >= 1,
              let cropped = cgImage.cropping(to: pixelRect) else {
            completion(nil)
            return
        }
        completion(cropped)
    }
}

/// Borderless windows can't become key by default, which we need for Esc + drags.
final class OverlayWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

/// Draws the frozen screenshot, dims everything outside the live selection, and
/// reports the chosen rectangle (or a cancel) back through `onFinish`.
final class CropSelectionView: NSView {

    var image: NSImage?
    /// Called once with the selection rect (view points, top-left) or `nil` to cancel.
    var onFinish: ((CGRect?) -> Void)?

    private var startPoint: CGPoint?
    private var selection: CGRect?
    private var finished = false

    override var isFlipped: Bool { true }                 // top-left origin
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .crosshair)
    }

    // MARK: Drawing

    override func draw(_ dirtyRect: NSRect) {
        image?.draw(in: bounds)

        let dim = NSColor.black.withAlphaComponent(0.45)
        dim.setFill()

        if let sel = selection, sel.width > 0, sel.height > 0 {
            // Dim everything except the selection (even-odd punches the hole).
            let mask = NSBezierPath(rect: bounds)
            mask.append(NSBezierPath(rect: sel))
            mask.windingRule = .evenOdd
            mask.fill()

            NSColor.white.setStroke()
            let border = NSBezierPath(rect: sel)
            border.lineWidth = 1.5
            border.stroke()

            drawSizeBadge(for: sel)
        } else {
            bounds.fill()
            drawHint()
        }
    }

    private func drawSizeBadge(for sel: CGRect) {
        // Show the size in captured pixels, which is what actually gets saved.
        let scaleX = image.map { CGFloat($0.size.width) / bounds.width } ?? 1
        let scaleY = image.map { CGFloat($0.size.height) / bounds.height } ?? 1
        let text = "\(Int((sel.width * scaleX).rounded())) × \(Int((sel.height * scaleY).rounded()))"
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .semibold),
            .foregroundColor: NSColor.white
        ]
        let size = (text as NSString).size(withAttributes: attrs)
        let pad: CGFloat = 6
        var badge = CGRect(x: sel.minX, y: sel.minY - size.height - 2 * pad - 4,
                           width: size.width + 2 * pad, height: size.height + 2 * pad)
        if badge.minY < 0 { badge.origin.y = sel.minY + 4 }   // flip below if clipped at top
        NSColor.black.withAlphaComponent(0.7).setFill()
        NSBezierPath(roundedRect: badge, xRadius: 4, yRadius: 4).fill()
        (text as NSString).draw(at: CGPoint(x: badge.minX + pad, y: badge.minY + pad), withAttributes: attrs)
    }

    private func drawHint() {
        let text = "Drag to select an area  ·  Esc to cancel"
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 14, weight: .medium),
            .foregroundColor: NSColor.white
        ]
        let size = (text as NSString).size(withAttributes: attrs)
        let pad: CGFloat = 10
        let badge = CGRect(x: (bounds.width - size.width) / 2 - pad,
                           y: bounds.height * 0.12,
                           width: size.width + 2 * pad, height: size.height + 2 * pad)
        NSColor.black.withAlphaComponent(0.6).setFill()
        NSBezierPath(roundedRect: badge, xRadius: 8, yRadius: 8).fill()
        (text as NSString).draw(at: CGPoint(x: badge.minX + pad, y: badge.minY + pad), withAttributes: attrs)
    }

    // MARK: Mouse

    override func mouseDown(with event: NSEvent) {
        startPoint = convert(event.locationInWindow, from: nil)
        selection = .zero
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = startPoint else { return }
        selection = rect(start, convert(event.locationInWindow, from: nil))
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard let start = startPoint else { return }
        let final = rect(start, convert(event.locationInWindow, from: nil))
        startPoint = nil
        // A stray click (no real drag) cancels rather than cropping a sliver.
        if final.width < 5 || final.height < 5 {
            complete(nil)
        } else {
            complete(final)
        }
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {                 // Esc
            complete(nil)
        } else {
            super.keyDown(with: event)
        }
    }

    // MARK: Helpers

    private func rect(_ a: CGPoint, _ b: CGPoint) -> CGRect {
        CGRect(x: min(a.x, b.x), y: min(a.y, b.y),
               width: abs(a.x - b.x), height: abs(a.y - b.y))
    }

    private func complete(_ result: CGRect?) {
        guard !finished else { return }          // fire onFinish exactly once
        finished = true
        onFinish?(result)
    }
}
