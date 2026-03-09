import SwiftUI
import AppKit

private final class QuickPasteStripPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

final class QuickPasteStripController: NSWindowController {
    private let clipboardManager: ClipboardManager
    private let onChoose: (ClipboardItem) -> Void
    private let panel: NSPanel
    private var hostingController: NSHostingController<QuickPasteStripView>?

    init(clipboardManager: ClipboardManager, onChoose: @escaping (ClipboardItem) -> Void) {
        self.clipboardManager = clipboardManager
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
        panel.hasShadow = true
        panel.hidesOnDeactivate = true
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true

        self.panel = panel

        super.init(window: panel)
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
            shortcutLabel: shortcutLabel,
            onChoose: { [weak self] item in
                self?.hide()
                self?.onChoose(item)
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

        let referenceScreen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
        let visibleFrame = referenceScreen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero
        let width = min(max(calculatedWidth, 300), max(visibleFrame.width - 40, 300))
        let height: CGFloat = 144

        let origin = CGPoint(
            x: visibleFrame.midX - (width / 2),
            y: visibleFrame.minY + 52
        )

        panel.setFrame(NSRect(origin: origin, size: NSSize(width: width, height: height)), display: true)
        panel.makeKeyAndOrderFront(nil)
        panel.orderFrontRegardless()
    }

    func hide() {
        panel.orderOut(nil)
    }
}

private struct QuickPasteStripView: View {
    @ObservedObject var clipboardManager: ClipboardManager
    let items: [ClipboardItem]
    let shortcutLabel: String
    let onChoose: (ClipboardItem) -> Void
    let onClose: () -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.16), lineWidth: 1)
                )

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Hold \(shortcutLabel) chooser")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.68))
                    Spacer()
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

private struct QuickPasteStripTile: View {
    let item: ClipboardItem
    let previewImage: NSImage?
    let onChoose: () -> Void

    var body: some View {
        Button(action: onChoose) {
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
                    } else {
                        Image(systemName: iconName)
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.45))
                    }
                }
                .frame(width: 100, height: 62)

                Text(item.title)
                    .lineLimit(2)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.9))
                    .frame(width: 100, alignment: .leading)
            }
            .padding(4)
            .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
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
}
