import SwiftUI
import AppKit
import Carbon.HIToolbox
import Combine

@main
struct QuickTrayApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let clipboardManager = ClipboardManager.shared
    private let settings = AppSettings.shared
    private var statusItem: NSStatusItem?
    private var panelController: LauncherPanelController?
    private var quickPasteStripController: QuickPasteStripController?
    private var cancellables: Set<AnyCancellable> = []
    private var launcherHotKeyHoldWorkItem: DispatchWorkItem?
    private var launcherHotKeyDidTriggerLongPress = false

    func applicationWillFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        configureStatusItem()
        configureLauncherPanel()
        configureQuickPasteStrip()
        configureHotKeys()
        maybePresentLauncherOnStartup()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationWillTerminate(_ notification: Notification) {
        launcherHotKeyHoldWorkItem?.cancel()
        launcherHotKeyHoldWorkItem = nil
    }

    private func configureStatusItem() {
        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        let icon = statusBarIcon()
        statusItem.button?.image = icon
        statusItem.button?.imagePosition = .imageOnly
        statusItem.button?.imageScaling = .scaleProportionallyDown
        statusItem.button?.toolTip = "QuickTray"

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Open App", action: #selector(menuOpenApp), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Close App", action: #selector(menuCloseApp), keyEquivalent: ""))

        for item in menu.items {
            item.target = self
        }

        statusItem.menu = menu
        self.statusItem = statusItem
    }

    private func statusBarIcon() -> NSImage {
        if let icon = NSImage(systemSymbolName: "tray.full.fill", accessibilityDescription: "QuickTray") {
            icon.size = NSSize(width: 18, height: 18)
            icon.isTemplate = true
            return icon
        }

        let icon = NSImage(size: NSSize(width: 18, height: 18), flipped: true) { rect in
            let inset = rect.insetBy(dx: 1, dy: 2)
            let tray = NSBezierPath()
            tray.move(to: NSPoint(x: inset.minX, y: inset.minY + 4))
            tray.line(to: NSPoint(x: inset.minX + 3, y: inset.minY))
            tray.line(to: NSPoint(x: inset.maxX - 3, y: inset.minY))
            tray.line(to: NSPoint(x: inset.maxX, y: inset.minY + 4))
            tray.line(to: NSPoint(x: inset.maxX, y: inset.maxY))
            tray.line(to: NSPoint(x: inset.minX, y: inset.maxY))
            tray.close()
            NSColor.black.setStroke()
            tray.lineWidth = 1.3
            tray.stroke()
            let shelf = NSBezierPath()
            shelf.move(to: NSPoint(x: inset.minX, y: inset.minY + 4))
            shelf.line(to: NSPoint(x: inset.minX + 5, y: inset.minY + 4))
            shelf.line(to: NSPoint(x: inset.minX + 6, y: inset.minY + 6.5))
            shelf.line(to: NSPoint(x: inset.maxX - 6, y: inset.minY + 6.5))
            shelf.line(to: NSPoint(x: inset.maxX - 5, y: inset.minY + 4))
            shelf.line(to: NSPoint(x: inset.maxX, y: inset.minY + 4))
            shelf.lineWidth = 1.0
            shelf.stroke()
            return true
        }
        icon.isTemplate = true
        return icon
    }

    private func configureLauncherPanel() {
        panelController = LauncherPanelController(clipboardManager: clipboardManager, settings: settings)
    }

    private func configureQuickPasteStrip() {
        quickPasteStripController = QuickPasteStripController(
            clipboardManager: clipboardManager,
            onChoose: { [weak self] item in
                self?.clipboardManager.capturePasteTargetApplication()
                self?.clipboardManager.copyToClipboard(item: item, shouldPaste: true, refreshHistoryEntry: false)
                self?.panelController?.hide()
            }
        )
    }

    private func configureHotKeys() {
        registerLauncherHotKey()

        settings.$toggleKeyCode
            .combineLatest(settings.$toggleModifiers)
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] _, _ in
                self?.registerLauncherHotKey()
            }
            .store(in: &cancellables)

        HotKeyManager.shared.register(
            id: 2,
            keyCode: UInt32(kVK_ANSI_2),
            modifiers: UInt32(optionKey | cmdKey)
        ) { [weak self] in
            self?.clipboardManager.capturePasteTargetApplication()
            self?.clipboardManager.quickPasteRecent(offsetFromLatest: 1)
            self?.panelController?.hide()
        }

        HotKeyManager.shared.register(
            id: 3,
            keyCode: UInt32(kVK_ANSI_3),
            modifiers: UInt32(optionKey | cmdKey)
        ) { [weak self] in
            self?.clipboardManager.capturePasteTargetApplication()
            self?.clipboardManager.quickPasteRecent(offsetFromLatest: 2)
            self?.panelController?.hide()
        }

        HotKeyManager.shared.register(
            id: 4,
            keyCode: UInt32(kVK_ANSI_4),
            modifiers: UInt32(optionKey | cmdKey)
        ) { [weak self] in
            self?.clipboardManager.capturePasteTargetApplication()
            self?.clipboardManager.quickPasteRecent(offsetFromLatest: 3)
            self?.panelController?.hide()
        }

        HotKeyManager.shared.register(
            id: 5,
            keyCode: UInt32(kVK_ANSI_5),
            modifiers: UInt32(optionKey | cmdKey)
        ) { [weak self] in
            self?.clipboardManager.capturePasteTargetApplication()
            self?.clipboardManager.quickPasteRecent(offsetFromLatest: 4)
            self?.panelController?.hide()
        }

        HotKeyManager.shared.register(
            id: 6,
            keyCode: UInt32(kVK_ANSI_V),
            modifiers: UInt32(optionKey | cmdKey | shiftKey)
        ) { [weak self] in
            self?.clipboardManager.capturePasteTargetApplication()
            self?.clipboardManager.pasteNextStackItem()
            self?.panelController?.hide()
        }

        HotKeyManager.shared.register(
            id: 7,
            keyCode: UInt32(kVK_ANSI_O),
            modifiers: UInt32(optionKey | cmdKey | shiftKey)
        ) { [weak self] in
            self?.clipboardManager.extractTextFromMostRecentImage(shouldPaste: false)
            self?.panelController?.hide()
        }
    }

    @objc
    private func toggleLauncher() {
        clipboardManager.capturePasteTargetApplication()
        panelController?.toggle()
    }

    @objc
    func menuOpenApp() {
        clipboardManager.capturePasteTargetApplication()
        panelController?.show()
    }

    @objc
    func menuCloseApp() {
        NSApp.terminate(nil)
    }

    private func registerLauncherHotKey() {
        HotKeyManager.shared.register(
            id: 1,
            keyCode: settings.toggleKeyCode,
            modifiers: settings.toggleModifiers,
            onPress: { [weak self] in
                self?.beginLauncherHotKeyPress()
            },
            onRelease: { [weak self] in
                self?.endLauncherHotKeyPress()
            }
        )
    }

    private func maybePresentLauncherOnStartup() {
        guard !settings.hasCompletedOnboarding || settings.showLauncherOnStartup else { return }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            self?.clipboardManager.capturePasteTargetApplication()
            self?.panelController?.show()
        }
    }

    private func beginLauncherHotKeyPress() {
        guard launcherHotKeyHoldWorkItem == nil else { return }
        clipboardManager.capturePasteTargetApplication()

        launcherHotKeyDidTriggerLongPress = false

        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            if self.presentQuickPasteStripFromLauncherHotKey() {
                self.launcherHotKeyDidTriggerLongPress = true
                self.panelController?.hide()
            }
            self.launcherHotKeyHoldWorkItem = nil
        }

        launcherHotKeyHoldWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + settings.launcherHoldDuration, execute: workItem)
    }

    private func endLauncherHotKeyPress() {
        launcherHotKeyHoldWorkItem?.cancel()
        launcherHotKeyHoldWorkItem = nil

        if launcherHotKeyDidTriggerLongPress {
            launcherHotKeyDidTriggerLongPress = false
            return
        }

        if quickPasteStripController?.isVisible == true {
            quickPasteStripController?.hide()
        }
        toggleLauncher()
    }

    private func presentQuickPasteStripFromLauncherHotKey() -> Bool {
        let orderedItems = clipboardManager.items.sorted { $0.timestamp > $1.timestamp }
        let limit = max(AppSettings.minCommandVStripItemCount, settings.commandVStripItemCount)
        let itemsToShow = Array(orderedItems.prefix(limit))
        guard !itemsToShow.isEmpty else { return false }

        quickPasteStripController?.show(items: itemsToShow, shortcutLabel: settings.toggleShortcutLabel)
        return true
    }
}
