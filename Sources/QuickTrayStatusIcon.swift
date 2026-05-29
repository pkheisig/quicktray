import AppKit

enum QuickTrayStatusIcon {
    static func make() -> NSImage {
        if let symbol = NSImage(
            systemSymbolName: "tray.full.fill",
            accessibilityDescription: "QuickTray"
        ) {
            let config = NSImage.SymbolConfiguration(pointSize: 15, weight: .regular)
            let configured = symbol.withSymbolConfiguration(config) ?? symbol
            configured.isTemplate = true
            return configured
        }

        return makeDrawnIcon()
    }

    private static func makeDrawnIcon() -> NSImage {
        let size = NSSize(width: 26, height: 18)
        let image = NSImage(size: size)
        image.lockFocus()

        NSColor.black.setFill()

        let tray = NSBezierPath(
            roundedRect: NSRect(x: 3, y: 2, width: size.width - 6, height: 2.4),
            xRadius: 1.2,
            yRadius: 1.2
        )
        tray.fill()

        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .center

        let text = "QT" as NSString
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 13, weight: .black),
            .foregroundColor: NSColor.black,
            .paragraphStyle: paragraphStyle
        ]
        let textSize = text.size(withAttributes: attributes)
        let textRect = NSRect(
            x: (size.width - textSize.width) / 2,
            y: (size.height - textSize.height) / 2 + 1.5,
            width: textSize.width,
            height: textSize.height
        )
        text.draw(in: textRect, withAttributes: attributes)
        image.unlockFocus()

        image.isTemplate = true
        image.accessibilityDescription = "QuickTray"
        return image
    }
}
