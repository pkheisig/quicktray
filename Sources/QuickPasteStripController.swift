import SwiftUI
import AppKit

private final class QuickPasteStripPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

final class QuickPasteStripController: NSWindowController, NSWindowDelegate {
    private static let dragProtectionTimeout: TimeInterval = 0.75

    private let clipboardManager: ClipboardManager
    private let settings: AppSettings
    private let onChoose: (ClipboardItem) -> Void
    private let panel: NSPanel
    private var hostingController: NSHostingController<QuickPasteStripView>?
    private var dragProtectionActive = false
    private var dragProtectionTimeoutWorkItem: DispatchWorkItem?
    private var dragProtectionMouseUpMonitor: Any?

    init(clipboardManager: ClipboardManager, settings: AppSettings, onChoose: @escaping (ClipboardItem) -> Void) {
        self.clipboardManager = clipboardManager
        self.settings = settings
        self.onChoose = onChoose

        let panel = QuickPasteStripPanel(
            contentRect: NSRect(x: 0, y: 0, width: 620, height: 142),
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
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

        self.panel = panel

        super.init(window: panel)
        panel.delegate = self
        installDragProtectionMonitor()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    var isVisible: Bool {
        panel.isVisible
    }

    func show(items: [ClipboardItem], shortcutLabel: String) {
        guard !items.isEmpty else {
            hide()
            return
        }

        let rootView = QuickPasteStripView(
            clipboardManager: clipboardManager,
            items: items,
            onChoose: { [weak self] item in
                self?.onChoose(item)
                self?.hide()
            },
            onStartDrag: { [weak self] in
                self?.beginDragProtection()
            },
            onEndDrag: { [weak self] in
                self?.endDragProtection()
            },
            onSuccessfulDrop: { [weak self] in
                self?.hide()
            },
            onClose: { [weak self] in
                self?.hide()
            }
        )

        if let hostingController {
            hostingController.rootView = rootView
        } else {
            let hostingController = NSHostingController(rootView: rootView)
            hostingController.view.wantsLayer = true
            hostingController.view.layer?.cornerRadius = 12
            hostingController.view.layer?.masksToBounds = true
            hostingController.view.layer?.backgroundColor = NSColor.clear.cgColor
            panel.contentViewController = hostingController
            self.hostingController = hostingController
        }

        let tileWidth: CGFloat = 108
        let spacing: CGFloat = 8
        let horizontalPadding: CGFloat = 28
        let calculatedWidth = (tileWidth * CGFloat(items.count))
            + (spacing * CGFloat(max(items.count - 1, 0)))
            + horizontalPadding

        positionPanel(calculatedWidth: calculatedWidth, height: 144)
        panel.makeKeyAndOrderFront(nil)
        panel.orderFrontRegardless()
        panel.invalidateShadow()
    }

    func hide() {
        panel.orderOut(nil)
    }

    func windowDidMove(_ notification: Notification) {
        settings.setHoldChooserWindowOrigin(panel.frame.origin)
    }

    func windowDidResignKey(_ notification: Notification) {
        guard !dragProtectionActive else { return }
        hide()
    }

    private func positionPanel(calculatedWidth: CGFloat, height: CGFloat) {
        let savedOrigin = settings.holdChooserWindowOrigin()
        let referenceSize = NSSize(width: max(calculatedWidth, 300), height: height)
        let referenceScreen = savedOrigin.flatMap { origin in
            NSScreen.screens.first { $0.visibleFrame.intersects(NSRect(origin: origin, size: referenceSize)) }
        }
            ?? NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) }
            ?? NSScreen.main
        let visibleFrame = referenceScreen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero
        let width = min(max(calculatedWidth, 300), max(visibleFrame.width - 40, 300))
        let size = NSSize(width: width, height: height)

        let origin: CGPoint
        if let savedOrigin {
            origin = CGPoint(
                x: min(max(savedOrigin.x, visibleFrame.minX), max(visibleFrame.maxX - size.width, visibleFrame.minX)),
                y: min(max(savedOrigin.y, visibleFrame.minY), max(visibleFrame.maxY - size.height, visibleFrame.minY))
            )
        } else {
            origin = CGPoint(
                x: visibleFrame.midX - (size.width / 2),
                y: visibleFrame.minY + 52
            )
        }

        panel.setFrame(NSRect(origin: origin, size: size), display: true)
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

private struct QuickPasteStripView: View {
    @ObservedObject var clipboardManager: ClipboardManager
    let items: [ClipboardItem]
    let onChoose: (ClipboardItem) -> Void
    let onStartDrag: () -> Void
    let onEndDrag: () -> Void
    let onSuccessfulDrop: () -> Void
    let onClose: () -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.16), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.45), radius: 18, y: 6)

            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    ZStack(alignment: .leading) {
                        QuickPasteStripWindowDragHandle()

                        Text("double-click or drag/drop an item to paste")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.white.opacity(0.5))
                            .allowsHitTesting(false)
                    }
                    .frame(maxWidth: .infinity, minHeight: 28, alignment: .leading)

                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.white.opacity(0.75))
                            .frame(width: 20, height: 20)
                            .background(.white.opacity(0.08), in: Circle())
                    }
                    .buttonStyle(.plain)
                }

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(items) { item in
                            QuickPasteStripTile(
                                item: item,
                                previewImage: clipboardManager.previewImage(for: item),
                                onStartDrag: onStartDrag,
                                onEndDrag: onEndDrag,
                                onSuccessfulDrop: onSuccessfulDrop,
                                onChoose: { onChoose(item) }
                            )
                        }
                    }
                    .padding(.horizontal, 2)
                }
            }
            .padding(12)
        }
    }
}

private struct QuickPasteStripWindowDragHandle: NSViewRepresentable {
    func makeNSView(context: Context) -> QuickPasteStripWindowDragHandleView {
        QuickPasteStripWindowDragHandleView()
    }

    func updateNSView(_ nsView: QuickPasteStripWindowDragHandleView, context: Context) {}
}

private final class QuickPasteStripWindowDragHandleView: NSView {
    private var dragStartScreenPoint: CGPoint?
    private var dragStartWindowOrigin: CGPoint?

    override func mouseDown(with event: NSEvent) {
        dragStartScreenPoint = NSEvent.mouseLocation
        dragStartWindowOrigin = window?.frame.origin
    }

    override func mouseDragged(with event: NSEvent) {
        guard let window, let dragStartScreenPoint, let dragStartWindowOrigin else { return }

        let currentScreenPoint = NSEvent.mouseLocation
        let newOrigin = CGPoint(
            x: dragStartWindowOrigin.x + currentScreenPoint.x - dragStartScreenPoint.x,
            y: dragStartWindowOrigin.y + currentScreenPoint.y - dragStartScreenPoint.y
        )
        window.setFrameOrigin(newOrigin)
    }

    override func mouseUp(with event: NSEvent) {
        dragStartScreenPoint = nil
        dragStartWindowOrigin = nil
    }
}

private struct QuickPasteStripTile: View {
    let item: ClipboardItem
    let previewImage: NSImage?
    let onStartDrag: () -> Void
    let onEndDrag: () -> Void
    let onSuccessfulDrop: () -> Void
    let onChoose: () -> Void

    var body: some View {
        QuickPasteStripTileContent(item: item, previewImage: previewImage)
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay {
                QuickPasteStripTileDragSource(
                    item: item,
                    previewImage: previewImage,
                    onStartDrag: onStartDrag,
                    onEndDrag: onEndDrag,
                    onSuccessfulDrop: onSuccessfulDrop,
                    onChoose: onChoose
                )
            }
    }
}

private struct QuickPasteStripTileContent: View {
    let item: ClipboardItem
    let previewImage: NSImage?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.black.opacity(0.25))

                if let previewImage {
                    Image(nsImage: previewImage)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 100, height: 62)
                        .clipped()
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                } else if item.kind == .text, let textPreview {
                    Text(textPreview)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.78))
                        .lineLimit(4)
                        .multilineTextAlignment(.leading)
                        .frame(width: 86, height: 48, alignment: .topLeading)
                } else {
                    Image(systemName: iconName)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.45))
                }
            }
            .frame(width: 100, height: 62)

            Text(caption)
                .lineLimit(2)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.9))
                .frame(width: 100, alignment: .leading)
        }
        .padding(4)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var iconName: String {
        switch item.kind {
        case .text:
            return "text.alignleft"
        case .image:
            return "photo"
        case .file:
            return item.primaryCategory == .video ? "film" : "doc"
        }
    }

    private var textPreview: String? {
        guard let text = item.textContent?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else {
            return nil
        }

        return text
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private var caption: String {
        item.kind == .text ? "Text" : item.title
    }
}

private struct QuickPasteStripTileDragSource: NSViewRepresentable {
    let item: ClipboardItem
    let previewImage: NSImage?
    let onStartDrag: () -> Void
    let onEndDrag: () -> Void
    let onSuccessfulDrop: () -> Void
    let onChoose: () -> Void

    func makeNSView(context: Context) -> QuickPasteStripTileDragSourceView {
        QuickPasteStripTileDragSourceView(
            item: item,
            previewImage: previewImage,
            onStartDrag: onStartDrag,
            onEndDrag: onEndDrag,
            onSuccessfulDrop: onSuccessfulDrop,
            onChoose: onChoose
        )
    }

    func updateNSView(_ nsView: QuickPasteStripTileDragSourceView, context: Context) {
        nsView.item = item
        nsView.previewImage = previewImage
        nsView.onStartDrag = onStartDrag
        nsView.onEndDrag = onEndDrag
        nsView.onSuccessfulDrop = onSuccessfulDrop
        nsView.onChoose = onChoose
    }
}

private final class QuickPasteStripTileDragSourceView: NSView, NSDraggingSource {
    private static let dragDistanceThreshold: CGFloat = 4
    private static let dragPreviewSize = NSSize(width: 108, height: 96)

    var item: ClipboardItem
    var previewImage: NSImage?
    var onStartDrag: () -> Void
    var onEndDrag: () -> Void
    var onSuccessfulDrop: () -> Void
    var onChoose: () -> Void

    private var mouseDownEvent: NSEvent?
    private var isDragging = false

    init(
        item: ClipboardItem,
        previewImage: NSImage?,
        onStartDrag: @escaping () -> Void,
        onEndDrag: @escaping () -> Void,
        onSuccessfulDrop: @escaping () -> Void,
        onChoose: @escaping () -> Void
    ) {
        self.item = item
        self.previewImage = previewImage
        self.onStartDrag = onStartDrag
        self.onEndDrag = onEndDrag
        self.onSuccessfulDrop = onSuccessfulDrop
        self.onChoose = onChoose
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override func mouseDown(with event: NSEvent) {
        guard event.clickCount < 2 else {
            mouseDownEvent = nil
            onChoose()
            return
        }

        mouseDownEvent = event
        isDragging = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard !isDragging, let mouseDownEvent else { return }
        let currentPoint = convert(event.locationInWindow, from: nil)
        let startPoint = convert(mouseDownEvent.locationInWindow, from: nil)
        let distance = hypot(currentPoint.x - startPoint.x, currentPoint.y - startPoint.y)
        guard distance >= Self.dragDistanceThreshold else { return }
        beginDrag(with: mouseDownEvent)
    }

    override func mouseUp(with event: NSEvent) {
        mouseDownEvent = nil
        isDragging = false
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        .copy
    }

    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        mouseDownEvent = nil
        isDragging = false
        onEndDrag()
        if !operation.isEmpty {
            onSuccessfulDrop()
        }
    }

    private func beginDrag(with event: NSEvent) {
        guard let pasteboardWriter = item.quickPasteStripDragPasteboardWriter else { return }

        isDragging = true
        onStartDrag()

        let draggingItem = NSDraggingItem(pasteboardWriter: pasteboardWriter)
        let draggingFrame = NSRect(
            x: bounds.midX - (Self.dragPreviewSize.width / 2),
            y: bounds.midY - (Self.dragPreviewSize.height / 2),
            width: Self.dragPreviewSize.width,
            height: Self.dragPreviewSize.height
        )
        let dragImage = Self.makeDragPreviewImage(item: item, previewImage: previewImage)
        draggingItem.setDraggingFrame(draggingFrame, contents: dragImage)

        let session = beginDraggingSession(with: [draggingItem], event: event, source: self)
        session.animatesToStartingPositionsOnCancelOrFail = false
    }

    private static func makeDragPreviewImage(item: ClipboardItem, previewImage: NSImage?) -> NSImage {
        let hostingView = NSHostingView(
            rootView: QuickPasteStripTileContent(item: item, previewImage: previewImage)
                .frame(width: dragPreviewSize.width, height: dragPreviewSize.height)
                .opacity(0.48)
        )
        hostingView.frame = NSRect(origin: .zero, size: dragPreviewSize)
        hostingView.layoutSubtreeIfNeeded()

        guard let bitmap = hostingView.bitmapImageRepForCachingDisplay(in: hostingView.bounds) else {
            return NSImage(size: dragPreviewSize)
        }

        hostingView.cacheDisplay(in: hostingView.bounds, to: bitmap)
        let image = NSImage(size: dragPreviewSize)
        image.addRepresentation(bitmap)
        return image
    }
}

private extension ClipboardItem {
    var quickPasteStripDragPasteboardWriter: NSPasteboardWriting? {
        switch kind {
        case .text:
            guard let textContent else { return nil }
            let pasteboardItem = NSPasteboardItem()
            pasteboardItem.setString(textContent, forType: .string)
            if let richTextData {
                pasteboardItem.setData(richTextData, forType: .rtf)
            }
            if let htmlData {
                pasteboardItem.setData(htmlData, forType: .html)
            }
            return pasteboardItem
        case .image:
            guard let imagePayloadData else { return nil }
            let pasteboardItem = NSPasteboardItem()
            pasteboardItem.setData(imagePayloadData, forType: .tiff)
            return pasteboardItem
        case .file:
            return fileURL as NSURL?
        }
    }
}
