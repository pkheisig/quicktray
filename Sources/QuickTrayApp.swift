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
    private static let launcherHotKeyHoldDuration: TimeInterval = 1.0

    private let clipboardManager = ClipboardManager.shared
    private let settings = AppSettings.shared
    private var statusItem: NSStatusItem?
    private var panelController: LauncherPanelController?
    private var quickPasteStripController: QuickPasteStripController?
    private var cancellables: Set<AnyCancellable> = []
    private var launcherHotKeyHoldTimer: Timer?
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
        launcherHotKeyHoldTimer?.invalidate()
        launcherHotKeyHoldTimer = nil
    }

    private func configureStatusItem() {
        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "tray.full.fill", accessibilityDescription: "QuickTray")
        statusItem.button?.action = #selector(toggleLauncher)
        statusItem.button?.target = self
        statusItem.button?.toolTip = "QuickTray"
        self.statusItem = statusItem
    }

    private func configureLauncherPanel() {
        panelController = LauncherPanelController(clipboardManager: clipboardManager, settings: settings)
    }

    private func configureQuickPasteStrip() {
        quickPasteStripController = QuickPasteStripController(
            clipboardManager: clipboardManager,
            onChoose: { [weak self] item in
                self?.clipboardManager.copyToClipboard(item: item, shouldPaste: true)
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
            self?.clipboardManager.quickPasteRecent(offsetFromLatest: 1)
            self?.panelController?.hide()
        }

        HotKeyManager.shared.register(
            id: 3,
            keyCode: UInt32(kVK_ANSI_3),
            modifiers: UInt32(optionKey | cmdKey)
        ) { [weak self] in
            self?.clipboardManager.quickPasteRecent(offsetFromLatest: 2)
            self?.panelController?.hide()
        }

        HotKeyManager.shared.register(
            id: 4,
            keyCode: UInt32(kVK_ANSI_4),
            modifiers: UInt32(optionKey | cmdKey)
        ) { [weak self] in
            self?.clipboardManager.quickPasteRecent(offsetFromLatest: 3)
            self?.panelController?.hide()
        }

        HotKeyManager.shared.register(
            id: 5,
            keyCode: UInt32(kVK_ANSI_5),
            modifiers: UInt32(optionKey | cmdKey)
        ) { [weak self] in
            self?.clipboardManager.quickPasteRecent(offsetFromLatest: 4)
            self?.panelController?.hide()
        }

        HotKeyManager.shared.register(
            id: 6,
            keyCode: UInt32(kVK_ANSI_V),
            modifiers: UInt32(optionKey | cmdKey | shiftKey)
        ) { [weak self] in
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
        panelController?.toggle()
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
            self?.panelController?.show()
        }
    }

    private func beginLauncherHotKeyPress() {
        guard launcherHotKeyHoldTimer == nil else { return }

        launcherHotKeyDidTriggerLongPress = false
        launcherHotKeyHoldTimer = Timer.scheduledTimer(withTimeInterval: Self.launcherHotKeyHoldDuration, repeats: false) { [weak self] _ in
            guard let self else { return }
            if self.presentQuickPasteStripFromLauncherHotKey() {
                self.launcherHotKeyDidTriggerLongPress = true
                self.panelController?.hide()
            }
        }
    }

    private func endLauncherHotKeyPress() {
        launcherHotKeyHoldTimer?.invalidate()
        launcherHotKeyHoldTimer = nil

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
