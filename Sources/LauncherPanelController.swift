import SwiftUI
import AppKit
import Combine

private final class FloatingLauncherPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

final class LauncherPanelController: NSWindowController, NSWindowDelegate {
    private static let dragProtectionTimeout: TimeInterval = 0.75
    private static let defaultSize = NSSize(width: 810, height: 560)
    private static let minimumSize = NSSize(width: 740, height: 520)

    private let clipboardManager: ClipboardManager
    private let settings: AppSettings
    private let panel: NSPanel
    private var cancellables: Set<AnyCancellable> = []
    private var dragProtectionActive = false
    private var dragProtectionTimeoutWorkItem: DispatchWorkItem?
    private var dragProtectionMouseUpMonitor: Any?

    init(clipboardManager: ClipboardManager, settings: AppSettings) {
        self.clipboardManager = clipboardManager
        self.settings = settings

        let panel = FloatingLauncherPanel(
            contentRect: NSRect(origin: .zero, size: Self.defaultSize),
            styleMask: [.titled, .nonactivatingPanel, .fullSizeContentView, .resizable],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.standardWindowButton(.closeButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true
        panel.minSize = Self.minimumSize

        if let savedSize = settings.launcherWindowSize() {
            let restoredSize = NSSize(
                width: max(savedSize.width, Self.minimumSize.width),
                height: max(savedSize.height, Self.minimumSize.height)
            )
            panel.setFrame(NSRect(origin: panel.frame.origin, size: restoredSize), display: false)
        }

        self.panel = panel

        super.init(window: panel)
        panel.delegate = self
        installDragProtectionMonitor()

        let rootView = LauncherView(
            clipboardManager: clipboardManager,
            settings: settings,
            onClose: { [weak panel] in
                panel?.orderOut(nil)
            },
            onActivateItem: { [weak panel] item, paste in
                if paste {
                    clipboardManager.capturePasteTargetApplication()
                }
                panel?.orderOut(nil)
                clipboardManager.copyToClipboard(item: item, shouldPaste: paste, refreshHistoryEntry: false)
            },
            onBeginDrag: { [weak self] in
                self?.beginDragProtection()
            },
            shouldHandleKeyEvent: { [weak panel] event in
                guard let panel else { return false }
                return panel.isKeyWindow && event.window === panel
            }
        )

        let hostingController = NSHostingController(rootView: rootView)
        hostingController.view.wantsLayer = true
        hostingController.view.layer?.backgroundColor = NSColor.clear.cgColor
        panel.contentViewController = hostingController

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
        clipboardManager.capturePasteTargetApplication()
        positionPanel()
        panel.makeKeyAndOrderFront(nil)
        panel.orderFrontRegardless()
        panel.invalidateShadow()
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

    func windowDidResize(_ notification: Notification) {
        settings.setLauncherWindowSize(panel.frame.size)
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
        dragProtectionActive = true
        dragProtectionTimeoutWorkItem?.cancel()

        let workItem = DispatchWorkItem { [weak self] in
            self?.endDragProtection()
        }
        dragProtectionTimeoutWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.dragProtectionTimeout, execute: workItem)
    }

    private func endDragProtection() {
        dragProtectionTimeoutWorkItem?.cancel()
        dragProtectionTimeoutWorkItem = nil
        dragProtectionActive = false

        if !panel.isKeyWindow && panel.isVisible {
            hide()
        }
    }

    private func installDragProtectionMonitor() {
        dragProtectionMouseUpMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseUp, .rightMouseUp]) { [weak self] _ in
            self?.endDragProtection()
        }
    }

    deinit {
        if let dragProtectionMouseUpMonitor {
            NSEvent.removeMonitor(dragProtectionMouseUpMonitor)
        }
    }
}
