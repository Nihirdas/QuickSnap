// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "QuickSnap",
    platforms: [
        // ScreenCaptureKit's SCScreenshotManager needs macOS 14+.
        .macOS(.v14)
    ],
    targets: [
        .executableTarget(
            name: "QuickSnap",
            path: "Sources/QuickSnap",
            // Swift 5 language mode keeps the Carbon C-callback and AppKit
            // main-thread code simple. We can tighten to Swift 6 concurrency later.
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
