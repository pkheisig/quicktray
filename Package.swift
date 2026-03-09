// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "QuickTray",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        // Exported as a library specifically to trick Xcode into allowing SwiftUI Previews
        .library(name: "QuickTray", targets: ["QuickTray"])
    ],
    targets: [
        .target(
            name: "QuickTray",
            path: "Sources"
        )
    ]
)
