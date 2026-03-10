import SwiftUI
import AppKit
import Carbon.HIToolbox
import QuickLook

struct LauncherView: View {
    @ObservedObject var clipboardManager: ClipboardManager
    @ObservedObject var settings: AppSettings
    @ObservedObject private var snippetManager = SnippetManager.shared
    let onClose: () -> Void
    let onActivateItem: (ClipboardItem, Bool) -> Void

    @State private var selectedItemID: UUID?
    @State private var selectedSnippetID: UUID?
    @State private var editingItem: ClipboardItem?
    @State private var formattingItem: ClipboardItem?
    @State private var detailItem: ClipboardItem?
    @State private var editingTemplate: SnippetTemplate?
    @State private var quickLookURL: URL?
    @State private var showClearConfirmation = false
    @State private var showSettings = false
    @State private var showSettingsFromHoldKey = false
    @State private var showNewTemplateSheet = false
    @State private var showOnboarding = false
    @State private var onboardingStep = 0
    @FocusState private var isSearchFocused: Bool

    @State private var localEventMonitor: Any?
    @State private var settingsRevealWorkItem: DispatchWorkItem?

    private let tileColumns = 3
    private let defaultHistoryLimitOptions = [10, 20, 50, 100, 200]
    private static let stripCountFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .none
        formatter.minimum = NSNumber(value: AppSettings.minCommandVStripItemCount)
        formatter.maximum = NSNumber(value: AppSettings.maxCommandVStripItemCount)
        return formatter
    }()
    private static let holdDurationFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimum = NSNumber(value: AppSettings.minLauncherHoldDuration)
        formatter.maximum = NSNumber(value: AppSettings.maxLauncherHoldDuration)
        formatter.minimumFractionDigits = 1
        formatter.maximumFractionDigits = 1
        return formatter
    }()

    private var visibleItems: [ClipboardItem] {
        clipboardManager.displayedItems
    }

    private var selectedItem: ClipboardItem? {
        visibleItems.first(where: { $0.id == selectedItemID })
    }

    private var visibleTemplates: [SnippetTemplate] {
        let query = clipboardManager.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return snippetManager.templates }

        let normalizedQuery = query.lowercased()
        return snippetManager.templates.filter { template in
            template.title.lowercased().contains(normalizedQuery)
                || template.body.lowercased().contains(normalizedQuery)
        }
    }

    private var selectedTemplate: SnippetTemplate? {
        visibleTemplates.first(where: { $0.id == selectedSnippetID })
    }

    private var pinnedCount: Int {
        clipboardManager.items.filter(\.isPinned).count
    }

    private var historyLimitOptions: [Int] {
        if defaultHistoryLimitOptions.contains(clipboardManager.unpinnedRetentionLimit) {
            return defaultHistoryLimitOptions
        }
        return (defaultHistoryLimitOptions + [clipboardManager.unpinnedRetentionLimit]).sorted()
    }

    var body: some View {
        ZStack {
            LauncherBackdrop()

            VStack(spacing: 0) {
                header
                Divider().background(Color.white.opacity(0.12))
                tabs
                quickToolsBar
                contentArea
                footer
            }

            if showSettings {
                Color.black.opacity(0.001)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture {
                        cancelSettingsReveal(hideIfNeeded: false)
                        showSettingsFromHoldKey = false
                        withAnimation(.spring(response: 0.24, dampingFraction: 0.88)) {
                            showSettings = false
                        }
                    }

                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        settingsPanel
                            .frame(width: 660, height: 420)
                            .background(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(Color.black.opacity(0.62))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                                            .strokeBorder(Color.white.opacity(0.14), lineWidth: 1)
                                    )
                            )
                            .shadow(color: .black.opacity(0.35), radius: 16, y: 10)
                            .padding(.trailing, 10)
                            .padding(.bottom, 44)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
            }
        }
        .frame(width: 750, height: 500)
        .quickLookPreview($quickLookURL)
        .sheet(item: $editingItem) { item in
            TextEditSheet(
                item: item,
                onSave: { updatedValue in
                    clipboardManager.updateText(for: item.id, newValue: updatedValue)
                }
            )
        }
        .sheet(item: $detailItem) { item in
            DetailSheet(
                item: item,
                previewImage: clipboardManager.previewImage(for: item),
                maskedText: clipboardManager.maskedTextPreview(for: item),
                isMasked: clipboardManager.shouldMaskDisplay(of: item),
                sensitivitySummary: clipboardManager.sensitivitySummary(for: item),
                inspection: clipboardManager.inspection(for: item),
                preferredPasteMode: clipboardManager.preferredPasteMode,
                onCopy: { onActivateItem(item, false) },
                onPaste: { onActivateItem(item, true) },
                onPastePlain: { clipboardManager.copyToClipboard(item: item, shouldPaste: true, asPlainText: true) },
                onQueue: { clipboardManager.enqueueForPasteStack(item) },
                onOCR: { clipboardManager.extractText(from: item, shouldPaste: false) },
                onReveal: { clipboardManager.revealInFinder(item) },
                onOpen: { clipboardManager.openFile(item) },
                onCopyPath: { clipboardManager.copyPathToClipboard(item: item) },
                onEdit: { editingItem = item }
            )
        }
        .sheet(item: $formattingItem) { item in
            TextTransformSheet(
                item: item,
                onApply: { action in
                    _ = clipboardManager.applyTextTransform(action, to: item, shouldPaste: false)
                }
            )
        }
        .sheet(isPresented: $showNewTemplateSheet) {
            SnippetEditorSheet(
                title: "New Template",
                initialTitle: "",
                initialBody: ""
            ) { title, body in
                snippetManager.addTemplate(title: title, body: body)
                if let insertedTemplate = snippetManager.templates.last {
                    selectedSnippetID = insertedTemplate.id
                }
            }
        }
        .sheet(item: $editingTemplate) { template in
            SnippetEditorSheet(
                title: "Edit Template",
                initialTitle: template.title,
                initialBody: template.body
            ) { title, body in
                snippetManager.updateTemplate(id: template.id, title: title, body: body)
            }
        }
        .onAppear {
            syncSelection()
            setupEventMonitor()
            if !settings.hasCompletedOnboarding {
                showOnboarding = true
            }
        }
        .onDisappear {
            if let monitor = localEventMonitor {
                NSEvent.removeMonitor(monitor)
                localEventMonitor = nil
            }
            cancelSettingsReveal(hideIfNeeded: false)
            showSettingsFromHoldKey = false
        }
        .onChange(of: clipboardManager.displayedItems.map(\.id)) { _ in
            syncSelection()
        }
        .onChange(of: clipboardManager.selectedCategory) { _ in
            syncSelection()
        }
        .onChange(of: clipboardManager.searchQuery) { _ in
            syncSelection()
        }
        .onChange(of: snippetManager.templates.map(\.id)) { _ in
            syncSelection()
        }
        .onReceive(NotificationCenter.default.publisher(for: AppSettings.quickTrayLauncherDidShow)) { _ in
            showSettingsFromHoldKey = false
            selectedItemID = nil
            selectedSnippetID = nil
            syncSelection()
            if !settings.hasCompletedOnboarding {
                onboardingStep = 0
                showOnboarding = true
            }
            if settings.focusSearchOnOpen {
                isSearchFocused = true
            }
        }
        .overlay {
            if showOnboarding {
                onboardingOverlay
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
            }
        }
    }

    private func setupEventMonitor() {
        if localEventMonitor == nil {
            localEventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { event in
                if NSApp.keyWindow == nil {
                    return event
                }
                if event.type == .flagsChanged {
                    handleModifierFlagsChanged(event)
                    return event
                }
                cancelSettingsReveal(hideIfNeeded: false)
                if handleKeyDown(event) {
                    return nil // consume the event
                }
                return event
            }
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "tray.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white.opacity(0.7))

            SearchField(text: $clipboardManager.searchQuery, isFocused: $isSearchFocused)
                .frame(maxWidth: .infinity)

            if !clipboardManager.searchQuery.isEmpty {
                Button {
                    clipboardManager.searchQuery = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(.white.opacity(0.4))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 54)
    }

    private var footer: some View {
        HStack(spacing: 12) {
            if clipboardManager.selectedCategory == .snippets {
                if selectedSnippetID != nil {
                    HStack(spacing: 6) {
                        Text("Return")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 2)
                            .background(.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 4))
                        Text("to Paste Template")
                            .font(.system(size: 11, weight: .medium))
                    }
                } else {
                    Text("Select a template to paste")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.4))
                }

                Spacer()
            } else if selectedItemID != nil {
                HStack(spacing: 6) {
                    Text("Return")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                        .background(.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 4))
                    Text("Paste \(clipboardManager.preferredPasteMode.title)")
                        .font(.system(size: 11, weight: .medium))
                }

                HStack(spacing: 6) {
                    Text("Shift+Return")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                        .background(.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 4))
                    Text("Plain Paste")
                        .font(.system(size: 11, weight: .medium))
                }

                HStack(spacing: 6) {
                    Text("Space")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                        .background(.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 4))
                    Text("Inspect")
                        .font(.system(size: 11, weight: .medium))
                }

                Spacer()

                HStack(spacing: 12) {
                    Text("\(clipboardManager.items.count) items")
                    if pinnedCount > 0 {
                        Text("\(pinnedCount) pinned")
                    }
                }
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.5))
            } else {
                Text("Type to search...")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.4))
                Spacer()
            }

            Button {
                showSettingsFromHoldKey = false
                withAnimation(.spring(response: 0.24, dampingFraction: 0.88)) {
                    showSettings.toggle()
                }
            } label: {
                Image(systemName: "command")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.6))
                    .padding(6)
                    .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .frame(height: 38)
        .background(Color.black.opacity(0.2))
    }

    private var settingsPanel: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                settingsSection(title: "Launcher") {
                    HStack(alignment: .top, spacing: 16) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Shortcut")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(.white.opacity(0.72))

                            HStack(spacing: 8) {
                                Picker("Key", selection: $settings.toggleKeyCode) {
                                    ForEach(AppSettings.availableToggleKeys) { key in
                                        Text(key.label).tag(key.keyCode)
                                    }
                                }
                                .pickerStyle(.menu)
                                .labelsHidden()
                                .frame(width: 92)

                                HStack(spacing: 4) {
                                    ModifierChip(label: "⌘", isOn: settings.includesModifier(UInt32(cmdKey))) {
                                        settings.setModifier(UInt32(cmdKey), enabled: !settings.includesModifier(UInt32(cmdKey)))
                                    }
                                    ModifierChip(label: "⌥", isOn: settings.includesModifier(UInt32(optionKey))) {
                                        settings.setModifier(UInt32(optionKey), enabled: !settings.includesModifier(UInt32(optionKey)))
                                    }
                                }
                            }
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            Text("Defaults")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(.white.opacity(0.72))

                            Toggle("Open on startup", isOn: $settings.showLauncherOnStartup)
                                .controlSize(.small)
                            Toggle("Focus search on open", isOn: $settings.focusSearchOnOpen)
                                .controlSize(.small)
                        }
                        .toggleStyle(.checkbox)

                        Spacer()
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Long-press launcher hotkey items: \(settings.commandVStripItemCount)")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.white.opacity(0.75))

                        HStack(spacing: 8) {
                            Slider(
                                value: Binding(
                                    get: { Double(settings.commandVStripItemCount) },
                                    set: { settings.commandVStripItemCount = Int($0.rounded()) }
                                ),
                                in: Double(AppSettings.minCommandVStripItemCount)...Double(AppSettings.maxCommandVStripItemCount),
                                step: 1
                            )

                            TextField(
                                "",
                                value: $settings.commandVStripItemCount,
                                formatter: Self.stripCountFormatter
                            )
                            .frame(width: 36)
                            .multilineTextAlignment(.trailing)
                        }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Hold hotkey before strip opens: \(settings.launcherHoldDuration, specifier: "%.1f")s")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.white.opacity(0.75))

                        HStack(spacing: 8) {
                            Slider(
                                value: $settings.launcherHoldDuration,
                                in: AppSettings.minLauncherHoldDuration...AppSettings.maxLauncherHoldDuration,
                                step: 0.1
                            )

                            TextField(
                                "",
                                value: $settings.launcherHoldDuration,
                                formatter: Self.holdDurationFormatter
                            )
                            .frame(width: 40)
                            .multilineTextAlignment(.trailing)

                            Text("s")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.white.opacity(0.52))
                        }
                    }
                }

                settingsSection(title: "Paste") {
                    VStack(alignment: .leading, spacing: 10) {
                        PasteModeControl(selection: $clipboardManager.preferredPasteMode, compact: false)
                        Text(clipboardManager.preferredPasteMode.helpText)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.white.opacity(0.55))
                    }
                }

                settingsSection(title: "Privacy") {
                    VStack(alignment: .leading, spacing: 12) {
                        Toggle("Automatically mask likely secrets in history", isOn: $clipboardManager.maskSensitiveClips)
                            .toggleStyle(.checkbox)
                            .controlSize(.small)

                        Text("Password managers and concealed clipboard types are already skipped automatically.")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.white.opacity(0.5))

                        if clipboardManager.configuredApplications.isEmpty {
                            Text("App rules appear after QuickTray sees clips from an app.")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.white.opacity(0.5))
                        } else {
                            VStack(spacing: 8) {
                                ForEach(clipboardManager.configuredApplications) { application in
                                    AppRuleRow(
                                        application: application,
                                        onBehaviorChange: { behavior in
                                            clipboardManager.updateRule(for: application, behavior: behavior)
                                        }
                                    )
                                }
                            }
                        }
                    }
                }

                settingsSection(title: "History") {
                    HStack(alignment: .top, spacing: 16) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Retention")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(.white.opacity(0.72))

                            Picker("Keep History", selection: $clipboardManager.unpinnedRetentionLimit) {
                                ForEach(historyLimitOptions, id: \.self) { limit in
                                    Text("Keep last \(limit)").tag(limit)
                                }
                            }
                            .pickerStyle(.menu)
                            .labelsHidden()
                        }

                        Spacer()

                        VStack(alignment: .trailing, spacing: 10) {
                            Button("Delete All") {
                                showClearConfirmation = true
                            }
                            .buttonStyle(QuickGlassButtonStyle(fill: .red.opacity(0.4)))

                            if showClearConfirmation {
                                HStack(spacing: 8) {
                                    Button("Confirm") {
                                        clipboardManager.clearAll()
                                        showClearConfirmation = false
                                    }
                                    .buttonStyle(QuickGlassButtonStyle(fill: .red))
                                    Button("Cancel") { showClearConfirmation = false }
                                        .buttonStyle(QuickGlassButtonStyle())
                                }
                            }
                        }
                    }
                }
            }
            .padding(16)
        }
        .background(Color.black.opacity(0.3))
    }

    private var tabs: some View {
        HStack(spacing: 16) {
            ForEach(Array(ClipboardCategory.allCases.enumerated()), id: \.element.id) { index, category in
                Button {
                    clipboardManager.selectedCategory = category
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: category.symbolName)
                            .font(.system(size: 11))
                        Text(category.title)
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundStyle(clipboardManager.selectedCategory == category ? Color.white : Color.white.opacity(0.4))
                    .padding(.vertical, 8)
                    .contentShape(Rectangle())
                    .overlay(alignment: .bottom) {
                        if clipboardManager.selectedCategory == category {
                            Rectangle()
                                .fill(Color.white.opacity(0.8))
                                .frame(height: 2)
                                .offset(y: 8)
                        }
                    }
                }
                .buttonStyle(.plain)
            }

            Spacer()

            if clipboardManager.selectedCategory != .snippets {
                ModeToggle(selection: $clipboardManager.displayMode)
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 34)
        .background(Color.black.opacity(0.1))
    }

    private var quickToolsBar: some View {
        HStack(spacing: 12) {
            if clipboardManager.selectedCategory != .snippets {
                PasteModeControl(selection: $clipboardManager.preferredPasteMode, compact: true)
            }

            if let selectedItem, clipboardManager.shouldMaskDisplay(of: selectedItem) {
                UtilityBadge(
                    text: clipboardManager.sensitivitySummary(for: selectedItem).first ?? "Masked",
                    symbolName: "hand.raised.fill"
                )
            }

            Spacer()

            if let selectedItem, selectedItem.kind == .image {
                Button("Extract Text") {
                    clipboardManager.extractText(from: selectedItem, shouldPaste: false)
                }
                .buttonStyle(QuickGlassButtonStyle(fill: .white.opacity(0.12)))
            } else if clipboardManager.items.contains(where: { $0.kind == .image }) {
                Button("OCR Latest Image") {
                    clipboardManager.extractTextFromMostRecentImage(shouldPaste: false)
                }
                .buttonStyle(QuickGlassButtonStyle(fill: .white.opacity(0.12)))
            }

            if let selectedItem, clipboardManager.selectedCategory != .snippets {
                Button("Add to Stack") {
                    clipboardManager.enqueueForPasteStack(selectedItem)
                }
                .buttonStyle(QuickGlassButtonStyle(fill: .white.opacity(0.12)))
            }

            if !clipboardManager.pasteStackItems.isEmpty {
                HStack(spacing: 8) {
                    UtilityBadge(
                        text: "Stack \(clipboardManager.pasteStackItems.count)",
                        symbolName: "square.stack.3d.up.fill"
                    )
                    Button("Paste Next") {
                        clipboardManager.pasteNextStackItem()
                        onClose()
                    }
                    .buttonStyle(QuickGlassButtonStyle(fill: .white.opacity(0.12)))
                    Button("Clear") {
                        clipboardManager.clearPasteStack()
                    }
                    .buttonStyle(QuickGlassButtonStyle())
                }
            }

            if clipboardManager.selectedCategory != .snippets, selectedItem != nil {
                Button("Inspect") {
                    detailItem = selectedItem
                }
                .buttonStyle(QuickGlassButtonStyle())
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.black.opacity(0.16))
    }

    private func settingsSection<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.white.opacity(0.78))
            content()
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.white.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
                )
        )
    }

    private var contentArea: some View {
        Group {
            if clipboardManager.selectedCategory == .snippets {
                snippetsArea
            } else if visibleItems.isEmpty {
                emptyState(text: "No results")
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        if clipboardManager.displayMode == .compact {
                            LazyVStack(spacing: 0) {
                                ForEach(visibleItems) { item in
                                    LauncherCompactCard(
                                        item: item,
                                        displayTitle: clipboardManager.displayTitle(for: item),
                                        isSensitive: clipboardManager.shouldMaskDisplay(of: item),
                                        sourceAppIcon: clipboardManager.sourceAppIcon(for: item),
                                        isSelected: item.id == selectedItemID,
                                        onSelect: { selectedItemID = item.id },
                                        onPaste: { onActivateItem(item, true) },
                                        onStartDrag: startDraggingSelectedItem
                                    )
                                }
                            }
                            .padding(.vertical, 8)
                        } else if clipboardManager.displayMode == .list {
                            LazyVStack(spacing: 0) {
                                ForEach(visibleItems) { item in
                                    LauncherListCard(
                                        item: item,
                                        displayTitle: clipboardManager.displayTitle(for: item),
                                        displayDetail: clipboardManager.displayDetail(for: item),
                                        isSensitive: clipboardManager.shouldMaskDisplay(of: item),
                                        previewImage: clipboardManager.previewImage(for: item),
                                        sourceAppIcon: clipboardManager.sourceAppIcon(for: item),
                                        isSelected: item.id == selectedItemID,
                                        onSelect: { selectedItemID = item.id },
                                        onCopy: { onActivateItem(item, false) },
                                        onPaste: { onActivateItem(item, true) },
                                        onCopyPath: item.kind == .file ? { clipboardManager.copyPathToClipboard(item: item) } : nil,
                                        onOpen: item.kind == .file ? { clipboardManager.openFile(item) } : nil,
                                        onEdit: item.canEdit ? { editingItem = item } : nil,
                                        onDetail: { detailItem = item },
                                        onDelete: { clipboardManager.removeItem(id: item.id) },
                                        onPin: { clipboardManager.togglePin(for: item.id) },
                                        onStartDrag: startDraggingSelectedItem
                                    )
                                }
                            }
                            .padding(.vertical, 8)
                        } else {
                            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: tileColumns), spacing: 12) {
                                ForEach(visibleItems) { item in
                                    LauncherTileCard(
                                        item: item,
                                        displayTitle: clipboardManager.displayTitle(for: item),
                                        previewText: clipboardManager.maskedTextPreview(for: item),
                                        isSensitive: clipboardManager.shouldMaskDisplay(of: item),
                                        previewImage: clipboardManager.previewImage(for: item),
                                        sourceAppIcon: clipboardManager.sourceAppIcon(for: item),
                                        isSelected: item.id == selectedItemID,
                                        onSelect: { selectedItemID = item.id },
                                        onCopy: { onActivateItem(item, false) },
                                        onPaste: { onActivateItem(item, true) },
                                        onCopyPath: item.kind == .file ? { clipboardManager.copyPathToClipboard(item: item) } : nil,
                                        onOpen: item.kind == .file ? { clipboardManager.openFile(item) } : nil,
                                        onEdit: item.canEdit ? { editingItem = item } : nil,
                                        onDetail: { detailItem = item },
                                        onDelete: { clipboardManager.removeItem(id: item.id) },
                                        onPin: { clipboardManager.togglePin(for: item.id) },
                                        onStartDrag: startDraggingSelectedItem
                                    )
                                }
                            }
                            .padding(12)
                        }
                    }
                    .onChange(of: selectedItemID) { itemID in
                        guard let itemID else { return }
                        proxy.scrollTo(itemID, anchor: .center)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func emptyState(text: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "tray")
                .font(.system(size: 24))
                .foregroundStyle(.white.opacity(0.2))
            Text(text)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white.opacity(0.5))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var snippetsArea: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Button {
                    showNewTemplateSheet = true
                } label: {
                    Label("New Template", systemImage: "plus")
                        .font(.system(size: 11, weight: .semibold))
                }
                .buttonStyle(QuickGlassButtonStyle(fill: .white.opacity(0.12)))

                TextField("Default email variable", text: $snippetManager.defaultEmail)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.8))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))

                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            if visibleTemplates.isEmpty {
                emptyState(text: "No templates")
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(visibleTemplates) { template in
                                SnippetRow(
                                    template: template,
                                    renderedPreview: snippetManager.renderedText(for: template),
                                    isSelected: template.id == selectedSnippetID,
                                    onSelect: { selectedSnippetID = template.id },
                                    onPaste: {
                                        onClose()
                                        snippetManager.pasteTemplate(template, shouldPaste: true)
                                    },
                                    onEdit: {
                                        editingTemplate = template
                                    },
                                    onDelete: {
                                        snippetManager.removeTemplate(id: template.id)
                                    }
                                )
                            }
                        }
                        .padding(.vertical, 8)
                    }
                    .onChange(of: selectedSnippetID) { snippetID in
                        guard let snippetID else { return }
                        proxy.scrollTo(snippetID, anchor: .center)
                    }
                }
            }
        }
    }

    private var onboardingOverlay: some View {
        ZStack {
            Color.black.opacity(0.48)
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(onboardingPage.title)
                            .font(.system(size: 28, weight: .black, design: .rounded))
                            .foregroundStyle(.white)
                        Text(onboardingPage.subtitle)
                            .font(.system(size: 14, weight: .medium, design: .rounded))
                            .foregroundStyle(.white.opacity(0.74))
                    }

                    Spacer()

                    Button {
                        finishOnboarding()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 12, weight: .black))
                            .foregroundStyle(.white.opacity(0.8))
                            .frame(width: 34, height: 34)
                            .background(.white.opacity(0.08), in: Circle())
                    }
                    .buttonStyle(.plain)
                }

                HStack(spacing: 14) {
                    ForEach(Array(onboardingPages.enumerated()), id: \.offset) { index, page in
                        OnboardingStepCard(
                            page: page,
                            isActive: index == onboardingStep
                        )
                        .onTapGesture {
                            onboardingStep = index
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 14) {
                    ForEach(onboardingPage.points, id: \.self) { point in
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(Color(red: 0.95, green: 0.72, blue: 0.34))
                            Text(point)
                                .font(.system(size: 14, weight: .medium, design: .rounded))
                                .foregroundStyle(.white.opacity(0.88))
                        }
                    }
                }
                .padding(18)
                .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 22, style: .continuous))

                VStack(alignment: .leading, spacing: 10) {
                    Text("Visible every time you need it")
                        .font(.system(size: 13, weight: .black, design: .rounded))
                        .foregroundStyle(.white)

                    HStack(spacing: 12) {
                        ShortcutHint(text: "Toggle launcher: \(settings.toggleShortcutLabel)")
                        ShortcutHint(text: "Menu bar icon opens the same window")
                        ShortcutHint(text: "Help button reopens this guide")
                    }
                }

                HStack {
                    Toggle("Open QuickTray window automatically on startup", isOn: $settings.showLauncherOnStartup)
                        .toggleStyle(.switch)
                        .tint(.white.opacity(0.84))
                        .foregroundStyle(.white.opacity(0.82))

                    Spacer()

                    if onboardingStep > 0 {
                        Button("Back") {
                            withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                                onboardingStep -= 1
                            }
                        }
                        .buttonStyle(QuickGlassButtonStyle())
                    }

                    Button(onboardingStep == onboardingPages.count - 1 ? "Start Using QuickTray" : "Next") {
                        if onboardingStep == onboardingPages.count - 1 {
                            finishOnboarding()
                        } else {
                            withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                                onboardingStep += 1
                            }
                        }
                    }
                    .buttonStyle(QuickGlassButtonStyle(fill: Color.white.opacity(0.18)))
                }
            }
            .padding(24)
            .frame(width: 760)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(red: 0.12, green: 0.14, blue: 0.17).opacity(0.96))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
                    )
            )
            .shadow(color: .black.opacity(0.35), radius: 28, y: 20)
        }
    }

    private var onboardingPages: [OnboardingPage] {
        [
            OnboardingPage(
                title: "QuickTray opens as a floating clipboard window",
                subtitle: "You should never have to guess where the app went.",
                points: [
                    "On first launch, this window opens automatically so you can immediately see the app.",
                    "After onboarding, you can reopen it at any time with \(settings.toggleShortcutLabel) or by clicking the menu bar tray icon.",
                    "If you prefer, keep 'Open QuickTray window automatically on startup' enabled so the window appears every launch."
                ]
            ),
            OnboardingPage(
                title: "Copy anything and it lands here",
                subtitle: "Text, images, documents, folders, and video files all show up in one place.",
                points: [
                    "The default view is Mixed, so new users always see everything first.",
                    "Use the tabs to jump into Text, Images, Video, Docs, or Files.",
                    "If Quick Look cannot preview a file, QuickTray shows the icon of the default app that opens it."
                ]
            ),
            OnboardingPage(
                title: "The fastest path is keyboard-first",
                subtitle: "You can still click around, but the speed comes from the shortcuts.",
                points: [
                    "Arrow keys move selection, Return pastes using the current mode, Shift+Return pastes plain text, and Space inspects the clip.",
                    "Use the toolbar to switch Rich, Plain, or Markdown paste, queue a paste stack, and extract text from images.",
                    "Use ⌥⌘2-5 for quick recent paste, and ⌥⇧⌘V to paste your captured stack in copy order."
                ]
            )
        ]
    }

    private var onboardingPage: OnboardingPage {
        onboardingPages[min(max(onboardingStep, 0), onboardingPages.count - 1)]
    }

    private func syncSelection() {
        if clipboardManager.selectedCategory == .snippets {
            selectedItemID = nil
            if let selectedSnippetID, visibleTemplates.contains(where: { $0.id == selectedSnippetID }) {
                return
            }
            selectedSnippetID = visibleTemplates.first?.id
            return
        }

        selectedSnippetID = nil
        if let selectedItemID, visibleItems.contains(where: { $0.id == selectedItemID }) {
            return
        }
        selectedItemID = clipboardManager.preferredSelectionID(in: visibleItems)
    }

    private func copySelected() {
        guard let selectedItem else { return }
        onActivateItem(selectedItem, false)
    }

    private func pasteSelected(asPlainText: Bool = false) {
        guard let selectedItem else { return }
        if asPlainText {
            onClose()
            clipboardManager.copyToClipboard(item: selectedItem, shouldPaste: true, asPlainText: true)
            return
        }
        onActivateItem(selectedItem, true)
    }

    private func copySelectedTemplate() {
        guard let selectedTemplate else { return }
        clipboardManager.copyTextToClipboard(
            snippetManager.renderedText(for: selectedTemplate),
            shouldPaste: false,
            addToHistory: true,
            sourceApplicationName: "QuickTray Snippet",
            sourceBundleIdentifier: Bundle.main.bundleIdentifier
        )
    }

    private func pasteSelectedTemplate() {
        guard let selectedTemplate else { return }
        onClose()
        snippetManager.pasteTemplate(selectedTemplate, shouldPaste: true)
    }

    private func copySelectedPath() {
        guard let selectedItem else { return }
        clipboardManager.copyPathToClipboard(item: selectedItem)
    }

    private func queueSelected() {
        guard let selectedItem else { return }
        clipboardManager.enqueueForPasteStack(selectedItem)
    }

    private func inspectSelected() {
        guard let selectedItem else { return }
        detailItem = selectedItem
    }

    private func extractTextFromSelection() {
        if let selectedItem, selectedItem.kind == .image {
            clipboardManager.extractText(from: selectedItem, shouldPaste: false)
            return
        }
        clipboardManager.extractTextFromMostRecentImage(shouldPaste: false)
    }

    private func openSelected() {
        guard let selectedItem else { return }
        clipboardManager.openFile(selectedItem)
    }

    private func revealSelected() {
        guard let selectedItem else { return }
        clipboardManager.revealInFinder(selectedItem)
    }

    private func resetFilters() {
        clipboardManager.searchQuery = ""
        clipboardManager.fileTypeFilter = "all"
        clipboardManager.selectedCategory = .mixed
        clipboardManager.showPinnedOnly = false
    }

    private func startDraggingSelectedItem() {
        showSettingsFromHoldKey = false
        showSettings = false
    }

    private func handleModifierFlagsChanged(_ event: NSEvent) {
        if showOnboarding {
            return
        }

        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let shouldShowFromHold = modifiers == .command || modifiers == .control

        if shouldShowFromHold {
            scheduleSettingsRevealFromHold()
            return
        }

        cancelSettingsReveal(hideIfNeeded: true)
    }

    private func scheduleSettingsRevealFromHold() {
        guard !showSettingsFromHoldKey else { return }
        guard settingsRevealWorkItem == nil else { return }

        let workItem = DispatchWorkItem {
            settingsRevealWorkItem = nil
            guard !showOnboarding else { return }
            showSettingsFromHoldKey = true
            withAnimation(.spring(response: 0.2, dampingFraction: 0.9)) {
                showSettings = true
            }
        }

        settingsRevealWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.22, execute: workItem)
    }

    private func cancelSettingsReveal(hideIfNeeded: Bool) {
        settingsRevealWorkItem?.cancel()
        settingsRevealWorkItem = nil

        guard hideIfNeeded, showSettingsFromHoldKey else { return }
        showSettingsFromHoldKey = false
        withAnimation(.spring(response: 0.2, dampingFraction: 0.9)) {
            showSettings = false
        }
    }

    private func handleKeyDown(_ event: NSEvent) -> Bool {
        if showOnboarding {
            switch Int(event.keyCode) {
            case kVK_Escape:
                finishOnboarding()
                return true
            case kVK_Return, kVK_RightArrow:
                if onboardingStep == onboardingPages.count - 1 {
                    finishOnboarding()
                } else {
                    onboardingStep += 1
                }
                return true
            case kVK_LeftArrow:
                onboardingStep = max(onboardingStep - 1, 0)
                return true
            default:
                return false
            }
        }

        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

        if modifiers.contains(.command) {
            switch Int(event.keyCode) {
            case kVK_ANSI_F:
                isSearchFocused = true
                return true
            case kVK_ANSI_C:
                if clipboardManager.selectedCategory == .snippets {
                    copySelectedTemplate()
                } else if modifiers.contains(.shift) {
                    copySelectedPath()
                } else {
                    copySelected()
                }
                return true
            case kVK_ANSI_E:
                if clipboardManager.selectedCategory == .snippets, let selectedTemplate {
                    editingTemplate = selectedTemplate
                } else if let selectedItem, selectedItem.canEdit {
                    editingItem = selectedItem
                }
                return true
            case kVK_ANSI_K:
                if let selectedItem, selectedItem.canEdit {
                    formattingItem = selectedItem
                }
                return true
            case kVK_ANSI_I:
                if clipboardManager.selectedCategory != .snippets {
                    inspectSelected()
                }
                return true
            case kVK_ANSI_P:
                if clipboardManager.selectedCategory != .snippets, let selectedItem {
                    clipboardManager.togglePin(for: selectedItem.id)
                }
                return true
            case kVK_ANSI_O:
                if modifiers.contains(.shift), clipboardManager.selectedCategory != .snippets {
                    extractTextFromSelection()
                } else if clipboardManager.selectedCategory != .snippets {
                    openSelected()
                }
                return true
            case kVK_ANSI_R:
                if clipboardManager.selectedCategory != .snippets {
                    revealSelected()
                }
                return true
            case kVK_Delete, kVK_ForwardDelete:
                if clipboardManager.selectedCategory == .snippets, let selectedTemplate {
                    snippetManager.removeTemplate(id: selectedTemplate.id)
                } else if let selectedItem {
                    clipboardManager.removeItem(id: selectedItem.id)
                }
                return true
            case kVK_ANSI_0:
                resetFilters()
                return true
            case kVK_ANSI_1:
                clipboardManager.selectedCategory = .mixed
                return true
            case kVK_ANSI_2:
                clipboardManager.selectedCategory = .text
                return true
            case kVK_ANSI_3:
                clipboardManager.selectedCategory = .images
                return true
            case kVK_ANSI_4:
                clipboardManager.selectedCategory = .video
                return true
            case kVK_ANSI_5:
                clipboardManager.selectedCategory = .documents
                return true
            case kVK_ANSI_6:
                clipboardManager.selectedCategory = .files
                return true
            case kVK_ANSI_7:
                clipboardManager.selectedCategory = .snippets
                return true
            case kVK_ANSI_Comma:
                showSettingsFromHoldKey = false
                withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                    showSettings.toggle()
                }
                return true
            case kVK_ANSI_A:
                if modifiers.contains(.shift), clipboardManager.selectedCategory != .snippets {
                    queueSelected()
                    return true
                }
            case kVK_ANSI_V:
                if modifiers.contains(.shift) {
                    clipboardManager.pasteNextStackItem()
                    onClose()
                    return true
                }
            default:
                break
            }
        }

        switch Int(event.keyCode) {
        case kVK_Escape:
            onClose()
            return true
        case kVK_Return:
            if clipboardManager.selectedCategory == .snippets {
                pasteSelectedTemplate()
            } else if modifiers.contains(.shift) {
                pasteSelected(asPlainText: true)
            } else {
                pasteSelected()
            }
            return true
        case kVK_Space:
            if isSearchFocused { return false }
            if clipboardManager.selectedCategory == .snippets {
                return true
            }
            if let selectedItem {
                if selectedItem.kind == .file, let url = selectedItem.fileURL {
                    quickLookURL = url
                } else {
                    detailItem = selectedItem
                }
            }
            return true
        case kVK_LeftArrow:
            if isSearchFocused { return false }
            moveSelection(step: -1)
            return true
        case kVK_RightArrow:
            if isSearchFocused { return false }
            moveSelection(step: 1)
            return true
        case kVK_UpArrow:
            let upStep = clipboardManager.selectedCategory == .snippets
                ? -1
                : (clipboardManager.displayMode == .tiles ? -tileColumns : -1)
            moveSelection(step: upStep)
            return true
        case kVK_DownArrow:
            let downStep = clipboardManager.selectedCategory == .snippets
                ? 1
                : (clipboardManager.displayMode == .tiles ? tileColumns : 1)
            moveSelection(step: downStep)
            return true
        case kVK_ANSI_S:
            showSettingsFromHoldKey = false
            withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                showSettings.toggle()
            }
            return true
        case kVK_ANSI_T:
            if clipboardManager.selectedCategory != .snippets {
                clipboardManager.displayMode = clipboardManager.displayMode == .list ? .tiles : .list
            }
            return true
        case kVK_ANSI_P:
            if clipboardManager.selectedCategory != .snippets {
                clipboardManager.showPinnedOnly.toggle()
            }
            return true
        case kVK_ANSI_Slash:
            isSearchFocused = true
            return true
        default:
            return false
        }
    }

    private func moveSelection(step: Int) {
        if clipboardManager.selectedCategory == .snippets {
            guard !visibleTemplates.isEmpty else {
                selectedSnippetID = nil
                return
            }

            guard let currentIndex = visibleTemplates.firstIndex(where: { $0.id == selectedSnippetID }) else {
                selectedSnippetID = visibleTemplates.first?.id
                return
            }

            let nextIndex = min(max(currentIndex + step, 0), visibleTemplates.count - 1)
            selectedSnippetID = visibleTemplates[nextIndex].id
            return
        }

        guard let currentIndex = visibleItems.firstIndex(where: { $0.id == selectedItemID }) else {
            selectedItemID = clipboardManager.preferredSelectionID(in: visibleItems)
            return
        }

        let nextIndex = min(max(currentIndex + step, 0), visibleItems.count - 1)
        selectedItemID = visibleItems[nextIndex].id
    }

    private func finishOnboarding() {
        settings.completeOnboarding()
        withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
            showOnboarding = false
        }
    }
}

private struct OnboardingPage {
    let title: String
    let subtitle: String
    let points: [String]
}

private struct LauncherBackdrop: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(.ultraThinMaterial)
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
            )
    }
}

private struct ShortcutHint: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(.white.opacity(0.5))
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 4))
    }
}

private struct OnboardingStepCard: View {
    let page: OnboardingPage
    let isActive: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(page.title)
                .lineLimit(2)
                .font(.system(size: 15, weight: .black, design: .rounded))
                .foregroundStyle(.white)

            Text(page.subtitle)
                .lineLimit(3)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.6))
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 112, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(isActive ? Color.white.opacity(0.14) : Color.white.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(isActive ? Color.white.opacity(0.22) : Color.clear, lineWidth: 1)
                )
        )
    }
}

private struct ModifierChip: View {
    let label: String
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 12, weight: .black, design: .rounded))
                .foregroundStyle(isOn ? Color.black : Color.white)
                .frame(width: 34, height: 30)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(isOn ? Color.white : Color.white.opacity(0.08))
                )
        }
        .buttonStyle(.plain)
    }
}

private struct SearchField: View {
    @Binding var text: String
    var isFocused: FocusState<Bool>.Binding

    var body: some View {
        TextField("Search history...", text: $text)
            .textFieldStyle(.plain)
            .font(.system(size: 16, weight: .regular))
            .foregroundStyle(.white)
            .focused(isFocused)
            .padding(.vertical, 16)
    }
}

private struct ModeToggle: View {
    @Binding var selection: ClipboardDisplayMode

    var body: some View {
        HStack(spacing: 2) {
            ForEach(ClipboardDisplayMode.allCases) { mode in
                Button {
                    selection = mode
                } label: {
                    Image(systemName: mode.symbolName)
                        .font(.system(size: 11))
                        .foregroundStyle(selection == mode ? Color.white : Color.white.opacity(0.3))
                        .frame(width: 28, height: 28)
                        .background(selection == mode ? Color.white.opacity(0.1) : Color.clear, in: RoundedRectangle(cornerRadius: 6))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .background(Color.black.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct PasteModeControl: View {
    @Binding var selection: ClipboardPasteMode
    let compact: Bool

    var body: some View {
        HStack(spacing: compact ? 4 : 6) {
            ForEach(ClipboardPasteMode.allCases) { mode in
                Button {
                    selection = mode
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: mode.symbolName)
                            .font(.system(size: 11, weight: .semibold))
                        Text(compact ? mode.shortTitle : mode.title)
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundStyle(selection == mode ? Color.white : Color.white.opacity(0.58))
                    .padding(.horizontal, compact ? 8 : 10)
                    .padding(.vertical, 7)
                    .background(selection == mode ? Color.white.opacity(0.12) : Color.clear, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(compact ? 3 : 4)
        .background(Color.black.opacity(0.16), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

private struct UtilityBadge: View {
    let text: String
    let symbolName: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: symbolName)
                .font(.system(size: 10, weight: .semibold))
            Text(text)
                .lineLimit(1)
                .font(.system(size: 11, weight: .semibold))
        }
        .foregroundStyle(.white.opacity(0.78))
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct AppRuleRow: View {
    let application: SourceApplicationSummary
    let onBehaviorChange: (ClipboardAppRuleBehavior) -> Void

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(application.applicationName)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.9))
                Text("\(application.clipCount) clips")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.45))
            }

            Spacer()

            Picker("Behavior", selection: Binding(
                get: { application.behavior },
                set: { onBehaviorChange($0) }
            )) {
                ForEach(ClipboardAppRuleBehavior.allCases) { behavior in
                    Text(behavior.title).tag(behavior)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 210)
        }
        .padding(.vertical, 2)
    }
}

private struct SourceApplicationBadge: View {
    let sourceName: String?
    let sourceIcon: NSImage?

    var body: some View {
        if sourceName != nil || sourceIcon != nil {
            HStack(spacing: 4) {
                if let sourceIcon {
                    Image(nsImage: sourceIcon)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 12, height: 12)
                        .clipShape(RoundedRectangle(cornerRadius: 2, style: .continuous))
                } else {
                    Image(systemName: "app")
                        .font(.system(size: 9))
                        .foregroundStyle(.white.opacity(0.45))
                }

                if let sourceName, !sourceName.isEmpty {
                    Text(sourceName)
                        .lineLimit(1)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.white.opacity(0.52))
                }
            }
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(.white.opacity(0.06), in: Capsule())
        }
    }
}

private struct LauncherCompactCard: View {
    let item: ClipboardItem
    let displayTitle: String
    let isSensitive: Bool
    let sourceAppIcon: NSImage?
    let isSelected: Bool
    let onSelect: () -> Void
    let onPaste: () -> Void
    let onStartDrag: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: item.primaryCategory.symbolName)
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.4))
                .frame(width: 16)

            Text(displayTitle)
                .lineLimit(1)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(isSelected ? .white : .white.opacity(0.8))

            Spacer()

            if isSensitive {
                Image(systemName: "hand.raised.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(Color(red: 0.95, green: 0.72, blue: 0.34))
            }

            SourceApplicationBadge(
                sourceName: item.sourceApplicationName,
                sourceIcon: sourceAppIcon
            )

            if item.isPinned {
                Image(systemName: "pin.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.4))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(isSelected ? Color.white.opacity(0.1) : Color.clear)
        .contentShape(Rectangle())
        .simultaneousGesture(
            TapGesture()
                .onEnded(onSelect)
        )
        .simultaneousGesture(
            TapGesture(count: 2)
                .onEnded(onPaste)
        )
        .onDrag {
            onStartDrag()
            return item.dragItemProvider() ?? NSItemProvider()
        }
    }
}

private struct LauncherListCard: View {
    let item: ClipboardItem
    let displayTitle: String
    let displayDetail: String
    let isSensitive: Bool
    let previewImage: NSImage?
    let sourceAppIcon: NSImage?
    let isSelected: Bool
    let onSelect: () -> Void
    let onCopy: () -> Void
    let onPaste: () -> Void
    let onCopyPath: (() -> Void)?
    let onOpen: (() -> Void)?
    let onEdit: (() -> Void)?
    let onDetail: () -> Void
    let onDelete: () -> Void
    let onPin: () -> Void
    let onStartDrag: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            PreviewBadge(item: item, previewImage: previewImage, side: 36)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(displayTitle)
                        .lineLimit(1)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(isSelected ? .white : .white.opacity(0.9))

                    if isSensitive {
                        Image(systemName: "hand.raised.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(Color(red: 0.95, green: 0.72, blue: 0.34))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Text(displayDetail)
                    .lineLimit(1)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(isSelected ? .white.opacity(0.7) : .white.opacity(0.5))

                SourceApplicationBadge(
                    sourceName: item.sourceApplicationName,
                    sourceIcon: sourceAppIcon
                )
            }

            Spacer()

            if item.isPinned {
                Image(systemName: "pin.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.4))
            }

            Text(item.fileTypeToken.uppercased())
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.white.opacity(0.3))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 4))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(isSelected ? Color.white.opacity(0.1) : Color.clear)
        .contentShape(Rectangle())
        .simultaneousGesture(
            TapGesture()
                .onEnded(onSelect)
        )
        .simultaneousGesture(
            TapGesture(count: 2)
                .onEnded(onPaste)
        )
        .onDrag {
            onStartDrag()
            return item.dragItemProvider() ?? NSItemProvider()
        }
    }
}

private struct LauncherTileCard: View {
    let item: ClipboardItem
    let displayTitle: String
    let previewText: String?
    let isSensitive: Bool
    let previewImage: NSImage?
    let sourceAppIcon: NSImage?
    let isSelected: Bool
    let onSelect: () -> Void
    let onCopy: () -> Void
    let onPaste: () -> Void
    let onCopyPath: (() -> Void)?
    let onOpen: (() -> Void)?
    let onEdit: (() -> Void)?
    let onDetail: () -> Void
    let onDelete: () -> Void
    let onPin: () -> Void
    let onStartDrag: () -> Void

    var body: some View {
        PreviewCanvas(item: item, previewImage: previewImage, previewText: previewText)
            .overlay(alignment: .topTrailing) {
                HStack(spacing: 6) {
                    if isSensitive {
                        Image(systemName: "hand.raised.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(Color(red: 0.95, green: 0.72, blue: 0.34))
                            .padding(6)
                            .background(Color.black.opacity(0.4), in: Circle())
                    }
                    if item.isPinned {
                        Image(systemName: "pin.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(.white)
                            .padding(6)
                            .background(Color.black.opacity(0.4), in: Circle())
                    }
                }
                .padding(8)
            }
            .overlay(alignment: .bottomLeading) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(displayTitle)
                        .lineLimit(2)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.9))
                    SourceApplicationBadge(
                        sourceName: item.sourceApplicationName,
                        sourceIcon: sourceAppIcon
                    )
                }
                .padding(8)
            }
            .padding(6)
            .background(isSelected ? Color.white.opacity(0.15) : Color.white.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(isSelected ? Color.white.opacity(0.2) : Color.clear, lineWidth: 1)
            )
            .simultaneousGesture(
                TapGesture()
                    .onEnded(onSelect)
            )
            .simultaneousGesture(
                TapGesture(count: 2)
                    .onEnded(onPaste)
            )
            .onDrag {
                onStartDrag()
                return item.dragItemProvider() ?? NSItemProvider()
            }
    }
}

private struct PreviewBadge: View {
    let item: ClipboardItem
    let previewImage: NSImage?
    let side: CGFloat

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.white.opacity(0.1))

            if let previewImage {
                Image(nsImage: previewImage)
                    .resizable()
                    .scaledToFill()
                    .frame(width: side, height: side)
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            } else {
                Image(systemName: iconName)
                    .font(.system(size: side * 0.4))
                    .foregroundStyle(.white.opacity(0.5))
            }
        }
        .frame(width: side, height: side)
    }

    private var iconName: String {
        switch item.kind {
        case .text: return "text.alignleft"
        case .image: return "photo.fill"
        case .file: return item.primaryCategory == .video ? "film.fill" : "doc.fill"
        }
    }
}

private struct PreviewCanvas: View {
    let item: ClipboardItem
    let previewImage: NSImage?
    let previewText: String?

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.black.opacity(0.2))

            if let previewImage {
                Color.clear
                    .overlay(
                        Image(nsImage: previewImage)
                            .resizable()
                            .scaledToFill()
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            } else if item.kind == .text, let previewText {
                Text(previewText)
                    .lineLimit(4)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(.white.opacity(0.8))
                    .padding(12)
            } else {
                Image(systemName: item.primaryCategory.symbolName)
                    .font(.system(size: 24))
                    .foregroundStyle(.white.opacity(0.3))
            }
        }
        .frame(maxWidth: .infinity, minHeight: 120, maxHeight: 120)
        .clipped()
    }
}

private struct SnippetRow: View {
    let template: SnippetTemplate
    let renderedPreview: String
    let isSelected: Bool
    let onSelect: () -> Void
    let onPaste: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "text.badge.plus")
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.6))
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(template.title)
                        .lineLimit(1)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(isSelected ? .white : .white.opacity(0.86))

                    if template.isBuiltIn {
                        Text("Built-In")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.white.opacity(0.58))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(.white.opacity(0.08), in: Capsule())
                    }
                }

                Text(renderedPreview)
                    .lineLimit(2)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.58))
            }

            Spacer()

            HStack(spacing: 8) {
                Button {
                    onEdit()
                } label: {
                    Image(systemName: "pencil")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white.opacity(0.65))

                if !template.isBuiltIn {
                    Button {
                        onDelete()
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.red.opacity(0.8))
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(isSelected ? Color.white.opacity(0.1) : Color.clear)
        .contentShape(Rectangle())
        .simultaneousGesture(
            TapGesture()
                .onEnded(onSelect)
        )
        .simultaneousGesture(
            TapGesture(count: 2)
                .onEnded(onPaste)
        )
    }
}

private struct TextTransformSheet: View {
    let item: ClipboardItem
    let onApply: (TextTransformAction) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Quick Formatting")
                .font(.system(size: 20, weight: .black, design: .rounded))

            Text("Pick an action for the selected text clip. The transformed output is copied back to your clipboard.")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)

            ForEach(TextTransformAction.allCases) { action in
                Button {
                    onApply(action)
                    dismiss()
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: action.symbolName)
                            .font(.system(size: 13, weight: .semibold))
                            .frame(width: 16)
                        Text(action.title)
                            .font(.system(size: 13, weight: .semibold))
                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .background(.black.opacity(0.06), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)
            }

            Spacer()

            Text(item.title)
                .lineLimit(1)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .padding(20)
        .frame(width: 460, height: 360)
    }
}

private struct SnippetEditorSheet: View {
    let title: String
    let initialTitle: String
    let initialBody: String
    let onSave: (String, String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var snippetTitle: String
    @State private var snippetBody: String

    init(
        title: String,
        initialTitle: String,
        initialBody: String,
        onSave: @escaping (String, String) -> Void
    ) {
        self.title = title
        self.initialTitle = initialTitle
        self.initialBody = initialBody
        self.onSave = onSave
        _snippetTitle = State(initialValue: initialTitle)
        _snippetBody = State(initialValue: initialBody)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title)
                .font(.system(size: 20, weight: .black, design: .rounded))

            TextField("Template title", text: $snippetTitle)
                .textFieldStyle(.roundedBorder)

            TextEditor(text: $snippetBody)
                .font(.system(size: 13, weight: .medium))
                .frame(minHeight: 220)
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(Color.secondary.opacity(0.2), lineWidth: 1)
                )

            Text("Variables: {{date}}, {{time}}, {{datetime}}, {{iso_date}}, {{email}}, {{clipboard}}")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Save") {
                    onSave(snippetTitle, snippetBody)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 620, height: 430)
    }
}

private struct TextEditSheet: View {
    let item: ClipboardItem
    let onSave: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var value: String

    init(item: ClipboardItem, onSave: @escaping (String) -> Void) {
        self.item = item
        self.onSave = onSave
        _value = State(initialValue: item.textContent ?? "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Edit text clip")
                .font(.system(size: 20, weight: .black, design: .rounded))

            TextEditor(text: $value)
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .frame(minHeight: 260)

            HStack {
                Spacer()
                Button("Cancel") {
                    dismiss()
                }
                Button("Save") {
                    onSave(value)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 560, height: 380)
    }
}

private struct DetailSheet: View {
    let item: ClipboardItem
    let previewImage: NSImage?
    let maskedText: String?
    let isMasked: Bool
    let sensitivitySummary: [String]
    let inspection: ClipboardInspection
    let preferredPasteMode: ClipboardPasteMode
    let onCopy: () -> Void
    let onPaste: () -> Void
    let onPastePlain: () -> Void
    let onQueue: () -> Void
    let onOCR: () -> Void
    let onReveal: () -> Void
    let onOpen: () -> Void
    let onCopyPath: () -> Void
    let onEdit: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var revealSensitiveText = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(item.kind == .text && isMasked ? "Sensitive text clip" : item.title)
                        .font(.system(size: 22, weight: .black, design: .rounded))

                    Text(item.detailText)
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if !sensitivitySummary.isEmpty {
                    UtilityBadge(
                        text: sensitivitySummary.joined(separator: " • "),
                        symbolName: "hand.raised.fill"
                    )
                }
            }

            if let previewImage {
                Image(nsImage: previewImage)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: 220)
                    .background(Color.black.opacity(0.04), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            } else if let textContent = item.textContent {
                VStack(alignment: .leading, spacing: 10) {
                    if isMasked {
                        Button(revealSensitiveText ? "Hide" : "Reveal") {
                            revealSensitiveText.toggle()
                        }
                        .buttonStyle(.bordered)
                    }

                    ScrollView {
                        Text(revealSensitiveText || !isMasked ? textContent : (maskedText ?? ""))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    }
                    .frame(maxWidth: .infinity, maxHeight: 220)
                    .padding()
                    .background(Color.black.opacity(0.04), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("Clipboard Inspector")
                    .font(.system(size: 13, weight: .bold))

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                    ForEach(inspection.summary) { field in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(field.label)
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(.secondary)
                            Text(field.value)
                                .lineLimit(2)
                                .font(.system(size: 11, weight: .medium))
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(10)
                        .background(Color.black.opacity(0.04), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Type IDs")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Text(inspection.typeIdentifiers.isEmpty ? "No captured type identifiers." : inspection.typeIdentifiers.joined(separator: "\n"))
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .textSelection(.enabled)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Hex Preview")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Text(inspection.hexPreview)
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .textSelection(.enabled)
                }
            }

            HStack(spacing: 10) {
                Button("Copy") {
                    onCopy()
                    dismiss()
                }
                .buttonStyle(.borderedProminent)

                Button("Paste \(preferredPasteMode.shortTitle)") {
                    onPaste()
                    dismiss()
                }
                .buttonStyle(.borderedProminent)

                if item.kind == .text {
                    Button("Paste Plain") {
                        onPastePlain()
                        dismiss()
                    }
                    .buttonStyle(.bordered)
                }

                Button("Add to Stack") {
                    onQueue()
                }
                .buttonStyle(.bordered)

                if item.kind == .image {
                    Button("Extract Text") {
                        onOCR()
                    }
                    .buttonStyle(.bordered)
                }

                if item.canEdit {
                    Button("Edit") {
                        dismiss()
                        onEdit()
                    }
                    .buttonStyle(.bordered)
                }

                if item.kind == .file {
                    Button("Copy Path") {
                        onCopyPath()
                    }
                    .buttonStyle(.bordered)

                    Button("Reveal") {
                        onReveal()
                    }
                    .buttonStyle(.bordered)

                    Button("Open") {
                        onOpen()
                    }
                    .buttonStyle(.bordered)
                }

                Spacer()

                Button("Close") {
                    dismiss()
                }
            }
        }
        .padding(24)
        .frame(width: 700, height: 620)
    }
}

private struct QuickGlassButtonStyle: ButtonStyle {
    var fill: Color = Color.white.opacity(0.08)

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(fill.opacity(configuration.isPressed ? 0.74 : 1))
            )
    }
}

#Preview {
    let previewSettings = AppSettings.shared
    previewSettings.hasCompletedOnboarding = true
    
    return LauncherView(
        clipboardManager: ClipboardManager.shared,
        settings: previewSettings,
        onClose: {},
        onActivateItem: { _, _ in }
    )
        .frame(width: 820, height: 560)
    .background(Color(red: 0.1, green: 0.1, blue: 0.15))
}
