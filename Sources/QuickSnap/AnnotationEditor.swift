import AppKit

/// The kinds of marks the editor can draw.
enum AnnotationTool: Int {
    case arrow, box, circle, text
}

/// A single mark on the canvas.
struct Annotation {
    var tool: AnnotationTool
    var start: CGPoint
    var end: CGPoint
    var color: NSColor
    var lineWidth: CGFloat = 3
    var text: String = ""
    var fontSize: CGFloat = 20
}

// MARK: - Canvas

/// Draws the captured screenshot plus the annotations, and handles the drawing gestures.
final class AnnotationCanvasView: NSView, NSTextFieldDelegate {

    var backgroundImage: NSImage?
    var currentTool: AnnotationTool = .arrow
    var currentColor: NSColor = .systemRed
    var currentFontSize: CGFloat = 20

    private var annotations: [Annotation] = []
    private var draft: Annotation?
    private var activeTextField: NSTextField?
    private var activeTextOrigin: CGPoint = .zero

    override var isFlipped: Bool { true }              // top-left origin, matches screen coords
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    // MARK: Drawing

    override func draw(_ dirtyRect: NSRect) {
        backgroundImage?.draw(in: bounds)
        for annotation in annotations { drawAnnotation(annotation) }
        if let draft { drawAnnotation(draft) }
    }

    private func drawAnnotation(_ a: Annotation) {
        a.color.set()
        switch a.tool {
        case .box:
            let path = NSBezierPath(rect: rect(a.start, a.end))
            path.lineWidth = a.lineWidth
            path.stroke()
        case .circle:
            let path = NSBezierPath(ovalIn: rect(a.start, a.end))
            path.lineWidth = a.lineWidth
            path.stroke()
        case .arrow:
            drawArrow(from: a.start, to: a.end, lineWidth: a.lineWidth)
        case .text:
            let attrs: [NSAttributedString.Key: Any] = [
                .foregroundColor: a.color,
                .font: NSFont.systemFont(ofSize: a.fontSize, weight: .semibold)
            ]
            (a.text as NSString).draw(at: a.start, withAttributes: attrs)
        }
    }

    private func rect(_ p1: CGPoint, _ p2: CGPoint) -> CGRect {
        CGRect(x: min(p1.x, p2.x), y: min(p1.y, p2.y),
               width: abs(p1.x - p2.x), height: abs(p1.y - p2.y))
    }

    private func drawArrow(from: CGPoint, to: CGPoint, lineWidth: CGFloat) {
        let shaft = NSBezierPath()
        shaft.lineWidth = lineWidth
        shaft.lineCapStyle = .round
        shaft.move(to: from)
        shaft.line(to: to)
        shaft.stroke()

        let dx = Double(to.x - from.x), dy = Double(to.y - from.y)
        let angle = atan2(dy, dx)
        let headLen = Double(max(14, lineWidth * 4))
        let spread = Double.pi / 7
        let head = NSBezierPath()
        head.lineWidth = lineWidth
        head.lineCapStyle = .round
        head.lineJoinStyle = .round
        head.move(to: to)
        head.line(to: CGPoint(x: to.x + CGFloat(cos(angle + .pi - spread) * headLen),
                              y: to.y + CGFloat(sin(angle + .pi - spread) * headLen)))
        head.move(to: to)
        head.line(to: CGPoint(x: to.x + CGFloat(cos(angle + .pi + spread) * headLen),
                              y: to.y + CGFloat(sin(angle + .pi + spread) * headLen)))
        head.stroke()
    }

    // MARK: Mouse

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        commitActiveText()
        if currentTool == .text {
            beginTextEditing(at: point)
            return
        }
        draft = Annotation(tool: currentTool, start: point, end: point,
                           color: currentColor, fontSize: currentFontSize)
    }

    override func mouseDragged(with event: NSEvent) {
        guard draft != nil else { return }
        draft?.end = convert(event.locationInWindow, from: nil)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard var finished = draft else { return }
        finished.end = convert(event.locationInWindow, from: nil)
        if hypot(finished.end.x - finished.start.x, finished.end.y - finished.start.y) > 3 {
            annotations.append(finished)
        }
        draft = nil
        needsDisplay = true
    }

    // MARK: Text editing

    private func beginTextEditing(at point: CGPoint) {
        let field = NSTextField(frame: NSRect(x: point.x, y: point.y, width: 240, height: currentFontSize + 12))
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = NSFont.systemFont(ofSize: currentFontSize, weight: .semibold)
        field.textColor = currentColor
        field.placeholderString = "Type…"
        field.delegate = self
        addSubview(field)
        activeTextField = field
        activeTextOrigin = point
        window?.makeFirstResponder(field)
    }

    private func commitActiveText() {
        guard let field = activeTextField else { return }
        let text = field.stringValue
        field.removeFromSuperview()
        activeTextField = nil
        guard !text.isEmpty else { return }
        var a = Annotation(tool: .text, start: activeTextOrigin, end: activeTextOrigin,
                           color: currentColor, fontSize: currentFontSize)
        a.text = text
        annotations.append(a)
        needsDisplay = true
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        commitActiveText()
    }

    // MARK: Actions

    func undo() {
        if activeTextField != nil { commitActiveText(); return }
        if !annotations.isEmpty { annotations.removeLast(); needsDisplay = true }
    }

    /// Flatten the screenshot + marks into a PNG at the canvas's backing resolution.
    func flattenedPNG() -> Data? {
        commitActiveText()
        guard let rep = bitmapImageRepForCachingDisplay(in: bounds) else { return nil }
        cacheDisplay(in: bounds, to: rep)
        return rep.representation(using: .png, properties: [:])
    }
}

// MARK: - Window controller

/// Hosts the annotation canvas and a small toolbar. "Save & Copy" writes the PNG,
/// copies it to the clipboard, and closes; closing any other way discards.
final class AnnotationEditorWindowController: NSWindowController, NSWindowDelegate {

    private let canvas = AnnotationCanvasView()
    private let saveFolder: URL
    private var onClose: (() -> Void)?
    private let fontSizes = ["14", "20", "28", "36", "48"]

    init(image: CGImage, saveFolder: URL, onClose: @escaping () -> Void) {
        self.saveFolder = saveFolder
        self.onClose = onClose

        let imageSize = NSSize(width: image.width, height: image.height)
        let visible = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let maxW = min(visible.width - 80, 1200)
        let maxH = visible.height - 160
        let scale = min(maxW / imageSize.width, maxH / imageSize.height, 1.0)
        let canvasSize = NSSize(width: floor(imageSize.width * scale),
                                height: floor(imageSize.height * scale))

        let toolbarH: CGFloat = 52
        let w = max(canvasSize.width, 760)
        let h = canvasSize.height + toolbarH
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: w, height: h),
                              styleMask: [.titled, .closable],
                              backing: .buffered, defer: false)
        window.title = "QuickSnap — Annotate"
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.delegate = self

        let container = NSView(frame: NSRect(x: 0, y: 0, width: w, height: h))

        canvas.frame = NSRect(x: (w - canvasSize.width) / 2, y: 0,
                              width: canvasSize.width, height: canvasSize.height)
        canvas.backgroundImage = NSImage(cgImage: image, size: imageSize)
        container.addSubview(canvas)

        container.addSubview(buildToolbar(width: w, y: canvasSize.height, height: toolbarH))
        window.contentView = container
        window.initialFirstResponder = canvas
        window.center()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    private func buildToolbar(width: CGFloat, y: CGFloat, height: CGFloat) -> NSView {
        let bar = NSView(frame: NSRect(x: 0, y: y, width: width, height: height))
        bar.wantsLayer = true
        bar.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor

        let tools = NSSegmentedControl(labels: ["↗ Arrow", "▢ Box", "◯ Circle", "T Text"],
                                       trackingMode: .selectOne, target: self, action: #selector(toolChanged(_:)))
        tools.selectedSegment = 0

        let colorWell = NSColorWell()
        colorWell.color = .systemRed
        colorWell.target = self
        colorWell.action = #selector(colorChanged(_:))
        colorWell.widthAnchor.constraint(equalToConstant: 44).isActive = true

        let sizeLabel = NSTextField(labelWithString: "Size")
        sizeLabel.textColor = .secondaryLabelColor
        let sizePop = NSPopUpButton(frame: .zero, pullsDown: false)
        sizePop.addItems(withTitles: fontSizes)
        sizePop.selectItem(withTitle: "20")
        sizePop.target = self
        sizePop.action = #selector(fontSizeChanged(_:))

        let undo = NSButton(title: "Undo", target: self, action: #selector(undoTapped))
        let cancel = NSButton(title: "Cancel", target: self, action: #selector(cancelTapped))
        cancel.keyEquivalent = "\u{1b}"                     // Esc
        let save = NSButton(title: "Save & Copy", target: self, action: #selector(saveAndCopy))
        save.keyEquivalent = "\r"                            // Enter = default button
        save.bezelStyle = .rounded

        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        for v in [tools, colorWell, sizeLabel, sizePop, undo] { stack.addView(v, in: .leading) }
        stack.addView(cancel, in: .trailing)
        stack.addView(save, in: .trailing)
        bar.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: bar.leadingAnchor, constant: 14),
            stack.trailingAnchor.constraint(equalTo: bar.trailingAnchor, constant: -14),
            stack.centerYAnchor.constraint(equalTo: bar.centerYAnchor)
        ])
        return bar
    }

    // MARK: Toolbar actions

    @objc private func toolChanged(_ sender: NSSegmentedControl) {
        canvas.currentTool = AnnotationTool(rawValue: sender.selectedSegment) ?? .arrow
    }

    @objc private func colorChanged(_ sender: NSColorWell) {
        canvas.currentColor = sender.color
    }

    @objc private func fontSizeChanged(_ sender: NSPopUpButton) {
        canvas.currentFontSize = CGFloat(Int(sender.titleOfSelectedItem ?? "20") ?? 20)
    }

    @objc private func undoTapped() { canvas.undo() }

    @objc private func cancelTapped() { window?.close() }

    @objc private func saveAndCopy() {
        if let png = canvas.flattenedPNG() {
            try? png.write(to: saveFolder.appendingPathComponent(fileName()))
            if let image = NSImage(data: png) {
                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                pasteboard.writeObjects([image])
            }
        }
        window?.close()
    }

    private func fileName() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        return "Screenshot \(formatter.string(from: Date())) (annotated).png"
    }

    // Any close (button, X, discard) releases the controller.
    func windowWillClose(_ notification: Notification) {
        onClose?()
        onClose = nil
    }
}
