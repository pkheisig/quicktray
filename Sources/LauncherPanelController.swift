import SwiftUI
import AppKit
import Combine
import UniformTypeIdentifiers

private final class FloatingLauncherPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

final class LauncherPanelController: NSWindowController, NSWindowDelegate {
    private static let dragProtectionTimeout: TimeInterval = 0.75
    private static let defaultSize = NSSize(width: 810, height: 560)
    private static let minimumSize = NSSize(width: 600, height: 420)
    private static let settingsSize = NSSize(width: 780, height: 650)

    private let clipboardManager: ClipboardManager
    private let settings: AppSettings
    private let panel: NSPanel
    private var cancellables: Set<AnyCancellable> = []
    private var dragProtectionActive = false
    private var dragProtectionTimeoutWorkItem: DispatchWorkItem?
    private var dragProtectionMouseUpMonitor: Any?
    private var modalInteractionActive = false
    private var activeOpenPanel: NSOpenPanel?
    private var frameBeforeSettings: NSRect?
    private var suppressFramePersistence = false

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
        panel.contentMinSize = Self.minimumSize

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
            onActivateItem: { [weak panel, weak settings] item, paste in
                if paste {
                    clipboardManager.capturePasteTargetApplication()
                }
                if settings?.dismissBehavior.shouldDismiss(afterPaste: paste) == true {
                    panel?.orderOut(nil)
                }
                clipboardManager.copyToClipboard(item: item, shouldPaste: paste, refreshHistoryEntry: false)
            },
            onChooseExcludedApplications: { [weak self] in
                self?.chooseExcludedApplications()
            },
            onSettingsPresentationChanged: { [weak self] isPresented in
                self?.setSettingsPresented(isPresented)
            },
            onResetWindowLayout: { [weak self] in
                self?.resetWindowLayout()
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
        // Keep SwiftUI's ideal size from turning into an AppKit window constraint.
        // The panel's own minSize is the only bound on edge and corner resizing.
        hostingController.sizingOptions = []
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
        guard !suppressFramePersistence, frameBeforeSettings == nil else { return }
        settings.setLauncherWindowOrigin(panel.frame.origin)
    }

    func windowDidResize(_ notification: Notification) {
        guard !suppressFramePersistence, frameBeforeSettings == nil else { return }
        settings.setLauncherWindowSize(panel.frame.size)
    }

    func windowDidResignKey(_ notification: Notification) {
        guard !dragProtectionActive, !modalInteractionActive, panel.attachedSheet == nil else { return }
        hide()
    }

    private func positionPanel() {
        switch settings.windowPlacement {
        case .center:
            centerPanel()
            return
        case .nearCursor:
            positionNearCursor()
            return
        case .remember:
            break
        }
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

    private func positionNearCursor() {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
        let visible = screen?.visibleFrame ?? .zero
        let desired = CGPoint(x: mouse.x - 32, y: mouse.y - panel.frame.height + 32)
        let origin = CGPoint(
            x: min(max(desired.x, visible.minX), max(visible.maxX - panel.frame.width, visible.minX)),
            y: min(max(desired.y, visible.minY), max(visible.maxY - panel.frame.height, visible.minY))
        )
        panel.setFrameOrigin(origin)
    }

    private func chooseExcludedApplications() {
        guard !modalInteractionActive, activeOpenPanel == nil else { return }
        let openPanel = NSOpenPanel()
        openPanel.title = "Exclude Applications"
        openPanel.prompt = "Exclude"
        openPanel.allowedContentTypes = [.application]
        openPanel.allowsMultipleSelection = true
        openPanel.canChooseDirectories = false
        openPanel.canChooseFiles = true
        openPanel.directoryURL = URL(fileURLWithPath: "/Applications", isDirectory: true)
        openPanel.level = NSWindow.Level(rawValue: panel.level.rawValue + 1)
        modalInteractionActive = true
        activeOpenPanel = openPanel
        NSApp.activate(ignoringOtherApps: true)
        openPanel.begin { [weak self] response in
            guard let self else { return }
            if response == .OK {
                openPanel.urls.forEach { _ = self.settings.addExcludedApplication(at: $0) }
            }
            self.activeOpenPanel = nil
            self.modalInteractionActive = false
            self.panel.makeKeyAndOrderFront(nil)
        }
    }

    private func setSettingsPresented(_ presented: Bool) {
        if presented {
            guard frameBeforeSettings == nil else { return }
            frameBeforeSettings = panel.frame
            let screen = panel.screen ?? NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
            let visible = screen?.visibleFrame ?? panel.frame
            let size = NSSize(
                width: min(max(panel.frame.width, Self.settingsSize.width), visible.width),
                height: min(max(panel.frame.height, Self.settingsSize.height), visible.height)
            )
            let origin = CGPoint(
                x: min(max(panel.frame.midX - size.width / 2, visible.minX), max(visible.maxX - size.width, visible.minX)),
                y: min(max(panel.frame.midY - size.height / 2, visible.minY), max(visible.maxY - size.height, visible.minY))
            )
            suppressFramePersistence = true
            panel.setFrame(NSRect(origin: origin, size: size), display: true)
            suppressFramePersistence = false
        } else if let previousFrame = frameBeforeSettings {
            frameBeforeSettings = nil
            suppressFramePersistence = true
            panel.setFrame(previousFrame, display: true)
            suppressFramePersistence = false
        }
    }

    private func resetWindowLayout() {
        settings.resetLauncherWindowLayout()
        let screen = panel.screen ?? NSScreen.main
        let visible = screen?.visibleFrame ?? panel.frame
        let baseFrame = NSRect(
            x: visible.midX - Self.defaultSize.width / 2,
            y: visible.midY - Self.defaultSize.height / 2,
            width: Self.defaultSize.width,
            height: Self.defaultSize.height
        )
        if frameBeforeSettings != nil {
            frameBeforeSettings = baseFrame
            return
        }
        suppressFramePersistence = true
        panel.setFrame(baseFrame, display: true)
        suppressFramePersistence = false
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
