import AppKit

final class StatusBarController: NSObject {
    private let statusItem: NSStatusItem
    private let openApp: () -> Void
    private let closeApp: () -> Void

    init(openApp: @escaping () -> Void, closeApp: @escaping () -> Void) {
        self.openApp = openApp
        self.closeApp = closeApp
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()

        statusItem.isVisible = true
        configureButton()
        configureMenu()
    }

    private func configureButton() {
        guard let button = statusItem.button else {
            NSLog("QuickTray failed to create a status bar button")
            return
        }

        let icon = QuickTrayStatusIcon.make()
        button.image = icon
        // Fall back to a text title only if the icon failed to render.
        button.title = icon.size == .zero ? "QuickTray" : ""
        button.imagePosition = icon.size == .zero ? .noImage : .imageOnly
        button.imageScaling = .scaleProportionallyDown
        button.toolTip = "QuickTray"
        button.setAccessibilityTitle("QuickTray")
        button.setAccessibilityLabel("QuickTray")
    }

    private func configureMenu() {
        let menu = NSMenu()

        let openItem = NSMenuItem(title: "Open QuickTray", action: #selector(openSelected), keyEquivalent: "")
        openItem.target = self
        menu.addItem(openItem)

        let quitItem = NSMenuItem(title: "Quit QuickTray", action: #selector(closeSelected), keyEquivalent: "")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    @objc
    private func openSelected() {
        openApp()
    }

    @objc
    private func closeSelected() {
        closeApp()
    }
}
