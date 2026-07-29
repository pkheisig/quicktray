import SwiftUI
import AppKit
import Carbon.HIToolbox
import Combine

#if !QUICKTRAY_SWIFT_PACKAGE
@main
#endif
struct QuickTrayApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

private enum LegacyDefaultsMigration {
    private static let legacyDomain = "com.gemini.QuickTray"
    private static let migrationKey = "settings.migratedLegacyDefaults"

    static func run() {
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: migrationKey) == nil else { return }

        defer {
            defaults.set(true, forKey: migrationKey)
        }

        guard let legacyDefaults = defaults.persistentDomain(forName: legacyDomain) else { return }

        for (key, value) in legacyDefaults where defaults.object(forKey: key) == nil {
            guard !key.hasPrefix("NSStatusItem ") else { continue }
            defaults.set(value, forKey: key)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let defaultsMigration: Void = LegacyDefaultsMigration.run()
    private lazy var clipboardManager = ClipboardManager.shared
    private lazy var settings = AppSettings.shared
    private var statusBarController: StatusBarController?
    private var panelController: LauncherPanelController?
    private var quickPasteStripController: QuickPasteStripController?
    private var cancellables: Set<AnyCancellable> = []
    private var launcherHotKeyHoldWorkItem: DispatchWorkItem?
    private var launcherHotKeyDidTriggerLongPress = false
    private var launcherHotKeyDidDismissQuickPasteStrip = false

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
        clipboardManager.flushPendingSave()
    }

    private func configureStatusItem() {
        statusBarController = StatusBarController(
            openApp: { [weak self] in
                self?.clipboardManager.capturePasteTargetApplication()
                self?.panelController?.show()
            },
            closeApp: {
                NSApp.terminate(nil)
            }
        )
    }

    private func configureLauncherPanel() {
        panelController = LauncherPanelController(clipboardManager: clipboardManager, settings: settings)
    }

    private func configureQuickPasteStrip() {
        quickPasteStripController = QuickPasteStripController(
            clipboardManager: clipboardManager,
            settings: settings,
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
        guard settings.showLauncherOnStartup else { return }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            self?.clipboardManager.capturePasteTargetApplication()
            self?.panelController?.show()
        }
    }

    private func beginLauncherHotKeyPress() {
        guard launcherHotKeyHoldWorkItem == nil else { return }
        if quickPasteStripController?.isVisible == true {
            quickPasteStripController?.hide()
            launcherHotKeyDidDismissQuickPasteStrip = true
            launcherHotKeyDidTriggerLongPress = false
            return
        }

        clipboardManager.capturePasteTargetApplication()

        launcherHotKeyDidDismissQuickPasteStrip = false
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

        if launcherHotKeyDidDismissQuickPasteStrip {
            launcherHotKeyDidDismissQuickPasteStrip = false
            return
        }

        if launcherHotKeyDidTriggerLongPress {
            launcherHotKeyDidTriggerLongPress = false
            return
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
