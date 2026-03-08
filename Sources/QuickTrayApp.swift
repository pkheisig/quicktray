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
    private var cancellables: Set<AnyCancellable> = []

    func applicationWillFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        configureStatusItem()
        configureLauncherPanel()
        configureHotKeys()
        maybePresentLauncherOnStartup()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
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
    }

    @objc
    private func toggleLauncher() {
        panelController?.toggle()
    }

    private func registerLauncherHotKey() {
        HotKeyManager.shared.register(
            id: 1,
            keyCode: settings.toggleKeyCode,
            modifiers: settings.toggleModifiers
        ) { [weak self] in
            self?.toggleLauncher()
        }
    }

    private func maybePresentLauncherOnStartup() {
        guard !settings.hasCompletedOnboarding || settings.showLauncherOnStartup else { return }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            self?.panelController?.show()
        }
    }
}
