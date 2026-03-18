import SwiftUI
import AppKit
import Combine

private final class FloatingLauncherPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

final class LauncherPanelController: NSWindowController, NSWindowDelegate {
    private let clipboardManager: ClipboardManager
    private let settings: AppSettings
    private let panel: NSPanel
    private var cancellables: Set<AnyCancellable> = []
    private var dragProtectionActive = false
    private var dragProtectionWorkItem: DispatchWorkItem?

    init(clipboardManager: ClipboardManager, settings: AppSettings) {
        self.clipboardManager = clipboardManager
        self.settings = settings

        let panel = FloatingLauncherPanel(
            contentRect: NSRect(x: 0, y: 0, width: 820, height: 560),
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.alphaValue = settings.windowOpacity
        panel.standardWindowButton(.closeButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true

        self.panel = panel

        super.init(window: panel)
        panel.delegate = self

        let rootView = LauncherView(
            clipboardManager: clipboardManager,
            settings: settings,
            onClose: { [weak panel] in
                panel?.orderOut(nil)
            },
            onActivateItem: { [weak panel] item, paste in
                panel?.orderOut(nil)
                clipboardManager.copyToClipboard(item: item, shouldPaste: paste, refreshHistoryEntry: false)
            },
            onBeginDrag: { [weak self] in
                self?.beginDragProtection()
            }
        )

        let hostingController = NSHostingController(rootView: rootView)
        hostingController.view.wantsLayer = true
        hostingController.view.layer?.backgroundColor = NSColor.clear.cgColor
        panel.contentViewController = hostingController

        settings.$windowOpacity
            .receive(on: RunLoop.main)
            .sink { [weak panel] opacity in
                panel?.alphaValue = opacity
            }
            .store(in: &cancellables)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    var isVisible: Bool {
        panel.isVisible
    }

    func toggle() {
        // A non-activating panel can remain "visible" after losing focus.
        // Only treat it as toggle-hide when it is actually the active key window.
        (panel.isVisible && panel.isKeyWindow) ? hide() : show()
    }

    func show() {
        positionPanel()
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        panel.orderFrontRegardless()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            NSApp.setActivationPolicy(.accessory)
        }
        NotificationCenter.default.post(name: AppSettings.quickTrayLauncherDidShow, object: nil)
    }

    func hide() {
        panel.orderOut(nil)
    }

    private func centerPanel() {
        let referenceScreen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
        let frame = panel.frame
        let visibleFrame = referenceScreen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero

        let origin = CGPoint(
            x: visibleFrame.midX - (frame.width / 2),
            y: visibleFrame.midY - (frame.height / 2)
        )

        panel.setFrameOrigin(origin)
    }

    func windowDidMove(_ notification: Notification) {
        settings.setLauncherWindowOrigin(panel.frame.origin)
    }

    func windowDidResignKey(_ notification: Notification) {
        guard !dragProtectionActive else { return }
        hide()
    }

    private func positionPanel() {
        guard let savedOrigin = settings.launcherWindowOrigin() else {
            centerPanel()
            return
        }

        let frame = NSRect(origin: savedOrigin, size: panel.frame.size)
        let referenceScreen = NSScreen.screens.first { $0.visibleFrame.intersects(frame) }
            ?? NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) }
            ?? NSScreen.main

        let visibleFrame = referenceScreen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero
        let origin = CGPoint(
            x: min(max(savedOrigin.x, visibleFrame.minX), max(visibleFrame.maxX - panel.frame.width, visibleFrame.minX)),
            y: min(max(savedOrigin.y, visibleFrame.minY), max(visibleFrame.maxY - panel.frame.height, visibleFrame.minY))
        )

        panel.setFrameOrigin(origin)
    }

    private func beginDragProtection() {
        dragProtectionWorkItem?.cancel()
        dragProtectionActive = true

        let workItem = DispatchWorkItem { [weak self] in
            self?.dragProtectionActive = false
        }
        dragProtectionWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: workItem)
    }
}
