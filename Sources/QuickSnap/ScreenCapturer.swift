import AppKit
import CoreGraphics
import ScreenCaptureKit

enum CaptureError: LocalizedError {
    case noDisplay
    case encodingFailed

    var errorDescription: String? {
        switch self {
        case .noDisplay:      return "No display was found to capture."
        case .encodingFailed: return "Couldn’t encode the screenshot as PNG."
        }
    }
}

/// Captures the full main display using ScreenCaptureKit — Apple's modern,
/// non-deprecated capture API (macOS 14+).
enum ScreenCapturer {

    static func captureMainDisplay() async throws -> CGImage {
        // Asking for shareable content is what triggers the one-time
        // Screen Recording permission prompt on first use.
        let content = try await SCShareableContent.excludingDesktopWindows(
            false, onScreenWindowsOnly: false
        )

        guard let display = content.displays.first(where: { $0.displayID == CGMainDisplayID() })
                ?? content.displays.first else {
            throw CaptureError.noDisplay
        }

        let filter = SCContentFilter(display: display, excludingWindows: [])

        let config = SCStreamConfiguration()
        // SCDisplay dimensions are in points; multiply by the backing scale so
        // the capture is full Retina resolution rather than looking soft.
        let scale = backingScale(for: display.displayID)
        config.width = Int(CGFloat(display.width) * scale)
        config.height = Int(CGFloat(display.height) * scale)
        config.showsCursor = false

        return try await SCScreenshotManager.captureImage(
            contentFilter: filter, configuration: config
        )
    }

    private static func backingScale(for displayID: CGDirectDisplayID) -> CGFloat {
        let screen = NSScreen.screens.first { screen in
            (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID) == displayID
        }
        return screen?.backingScaleFactor ?? 2
    }
}

/// Turns a captured image into the two outputs the user asked for:
/// a PNG file on disk and an image on the clipboard.
enum CaptureOutput {

    @discardableResult
    static func save(image: CGImage, to folder: URL) throws -> URL {
        let rep = NSBitmapImageRep(cgImage: image)
        guard let data = rep.representation(using: .png, properties: [:]) else {
            throw CaptureError.encodingFailed
        }
        let url = folder.appendingPathComponent(fileName())
        try data.write(to: url)
        return url
    }

    static func copyToClipboard(image: CGImage) {
        let nsImage = NSImage(cgImage: image,
                              size: NSSize(width: image.width, height: image.height))
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([nsImage])
    }

    /// e.g. "Screenshot 2026-07-28 at 14.30.05.png" — matches macOS naming.
    private static func fileName() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        return "Screenshot \(formatter.string(from: Date())).png"
    }
}
