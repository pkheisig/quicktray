import SwiftUI
import AppKit
import Carbon.HIToolbox

struct LauncherView: View {
    @ObservedObject var clipboardManager: ClipboardManager
    @ObservedObject var settings: AppSettings
    let onClose: () -> Void
    let onActivateItem: (ClipboardItem, Bool) -> Void

    @State private var selectedItemID: UUID?
    @State private var editingItem: ClipboardItem?
    @State private var detailItem: ClipboardItem?
    @State private var showClearConfirmation = false
    @State private var showSettings = false
    @State private var showOnboarding = false
    @State private var onboardingStep = 0
    @FocusState private var isSearchFocused: Bool

    private let tileColumns = 3

    private var visibleItems: [ClipboardItem] {
        clipboardManager.displayedItems
    }

    private var recentItems: [ClipboardItem] {
        Array(clipboardManager.items.sorted { $0.timestamp > $1.timestamp }.prefix(5))
    }

    private var selectedItem: ClipboardItem? {
        visibleItems.first(where: { $0.id == selectedItemID })
    }

    private var pinnedCount: Int {
        clipboardManager.items.filter(\.isPinned).count
    }

    private var activeTypeFilterLabel: String {
        clipboardManager.fileTypeFilter == "all" ? "All types" : clipboardManager.fileTypeFilter.uppercased()
    }

    var body: some View {
        ZStack {
            LauncherBackdrop()

            VStack(spacing: 18) {
                header
                if showSettings {
                    settingsPanel
                }
                quickActions
                productivityStrip
                tabs
                contentArea
            }
            .padding(22)

            if showOnboarding {
                onboardingOverlay
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
            }
        }
        .frame(width: 980, height: 700)
        .background(PanelKeyHandler(onKeyDown: handleKeyDown))
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
                onCopy: { onActivateItem(item, false) },
                onPaste: { onActivateItem(item, true) },
                onReveal: { clipboardManager.revealInFinder(item) },
                onOpen: { clipboardManager.openFile(item) },
                onCopyPath: { clipboardManager.copyPathToClipboard(item: item) }
            )
        }
        .onAppear {
            syncSelection()
            if !settings.hasCompletedOnboarding {
                showOnboarding = true
            }
        }
        .onChange(of: clipboardManager.displayedItems.map(\.id)) { _ in
            syncSelection()
        }
        .onReceive(NotificationCenter.default.publisher(for: AppSettings.quickTrayLauncherDidShow)) { _ in
            syncSelection()
            if !settings.hasCompletedOnboarding {
                onboardingStep = 0
                showOnboarding = true
            }
            if settings.focusSearchOnOpen {
                isSearchFocused = true
            }
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 18) {
            VStack(alignment: .leading, spacing: 8) {
                Text("QuickTray")
                    .font(.system(size: 30, weight: .black, design: .rounded))
                    .foregroundStyle(.white)

                Text("Fast clipboard launcher for text, files, images, and drag-out paste flows.")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.65))

                HStack(spacing: 10) {
                    HotkeyPill(text: "Toggle", shortcut: settings.toggleShortcutLabel)
                    HotkeyPill(text: "Paste 2-5", shortcut: "⌥⌘2-5")
                    HotkeyPill(text: "Find", shortcut: "⌘F")
                    HotkeyPill(text: "Act", shortcut: "↩ / Space")
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 10) {
                HStack(spacing: 10) {
                    SearchField(text: $clipboardManager.searchQuery, isFocused: $isSearchFocused)
                        .frame(width: 280)

                    Picker("Type", selection: $clipboardManager.fileTypeFilter) {
                        ForEach(clipboardManager.availableFileTypeFilters, id: \.self) { typeToken in
                            Text(typeToken == "all" ? "All types" : typeToken.uppercased())
                                .tag(typeToken)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .frame(width: 120)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

                    ModeToggle(selection: $clipboardManager.displayMode)
                }

                HStack(spacing: 10) {
                    Stepper(value: $clipboardManager.unpinnedRetentionLimit, in: 1...500) {
                        Text("Keep \(clipboardManager.unpinnedRetentionLimit)")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white.opacity(0.7))
                    }
                    .controlSize(.small)

                    Button(showSettings ? "Hide Settings" : "Settings") {
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                            showSettings.toggle()
                        }
                    }
                    .buttonStyle(QuickGlassButtonStyle())

                    Button("Help") {
                        onboardingStep = 0
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                            showOnboarding = true
                        }
                    }
                    .buttonStyle(QuickGlassButtonStyle())

                    if showClearConfirmation {
                        HStack(spacing: 8) {
                            Text("Clear all?")
                                .font(.system(size: 11, weight: .semibold, design: .rounded))
                                .foregroundStyle(.white.opacity(0.64))

                            Button("Yes") {
                                clipboardManager.clearAll()
                                showClearConfirmation = false
                            }
                            .buttonStyle(QuickGlassButtonStyle(fill: Color.red.opacity(0.74)))

                            Button("No") {
                                showClearConfirmation = false
                            }
                            .buttonStyle(QuickGlassButtonStyle())
                        }
                    } else {
                        Button("Delete All") {
                            showClearConfirmation = true
                        }
                        .buttonStyle(QuickGlassButtonStyle())
                    }

                    Button("Close") {
                        onClose()
                    }
                    .buttonStyle(QuickGlassButtonStyle())
                }
            }
        }
    }

    private var settingsPanel: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 18) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Launcher Shortcut")
                        .font(.system(size: 14, weight: .black, design: .rounded))
                        .foregroundStyle(.white)

                    HStack(spacing: 10) {
                        Picker("Key", selection: $settings.toggleKeyCode) {
                            ForEach(AppSettings.availableToggleKeys) { key in
                                Text(key.label).tag(key.keyCode)
                            }
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                        .frame(width: 100)

                        ModifierChip(label: "⌘", isOn: settings.includesModifier(UInt32(cmdKey))) {
                            settings.setModifier(UInt32(cmdKey), enabled: !settings.includesModifier(UInt32(cmdKey)))
                        }
                        ModifierChip(label: "⌥", isOn: settings.includesModifier(UInt32(optionKey))) {
                            settings.setModifier(UInt32(optionKey), enabled: !settings.includesModifier(UInt32(optionKey)))
                        }
                        ModifierChip(label: "⌃", isOn: settings.includesModifier(UInt32(controlKey))) {
                            settings.setModifier(UInt32(controlKey), enabled: !settings.includesModifier(UInt32(controlKey)))
                        }
                        ModifierChip(label: "⇧", isOn: settings.includesModifier(UInt32(shiftKey))) {
                            settings.setModifier(UInt32(shiftKey), enabled: !settings.includesModifier(UInt32(shiftKey)))
                        }

                        Text(settings.toggleShortcutLabel)
                            .font(.system(size: 12, weight: .black, design: .rounded))
                            .foregroundStyle(.white.opacity(0.62))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .background(.white.opacity(0.06), in: Capsule())
                    }
                }

                VStack(alignment: .leading, spacing: 12) {
                    Text("Window Transparency")
                        .font(.system(size: 14, weight: .black, design: .rounded))
                        .foregroundStyle(.white)

                    HStack(spacing: 12) {
                        Slider(
                            value: Binding(
                                get: { settings.windowOpacity },
                                set: { settings.setWindowOpacity($0) }
                            ),
                            in: 0.45...1.0
                        )
                            .frame(width: 220)
                        Text("\(Int(settings.windowOpacity * 100))%")
                            .font(.system(size: 12, weight: .black, design: .rounded))
                            .foregroundStyle(.white.opacity(0.68))
                            .frame(width: 44, alignment: .trailing)
                    }
                }

                VStack(alignment: .leading, spacing: 12) {
                    Text("Behavior")
                        .font(.system(size: 14, weight: .black, design: .rounded))
                        .foregroundStyle(.white)

                    Toggle("Focus search whenever the launcher opens", isOn: $settings.focusSearchOnOpen)
                        .toggleStyle(.switch)
                        .tint(.white.opacity(0.8))

                    Toggle("Open launcher when QuickTray starts", isOn: $settings.showLauncherOnStartup)
                        .toggleStyle(.switch)
                        .tint(.white.opacity(0.8))

                    Toggle("Capture clipboard changes", isOn: $clipboardManager.isMonitoringEnabled)
                        .toggleStyle(.switch)
                        .tint(.white.opacity(0.8))

                    Text("Mixed remains the default tab.")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.52))
                }
            }

            HStack(spacing: 10) {
                ShortcutHint(text: "⌘1-6 switch tabs")
                ShortcutHint(text: "⌘C copy")
                ShortcutHint(text: "⌘⇧C copy path")
                ShortcutHint(text: "⌘P pin")
                ShortcutHint(text: "⌘⌫ delete")
                ShortcutHint(text: "Space preview")
                Spacer()
                Button("Reset Defaults") {
                    settings.resetDefaults()
                }
                .buttonStyle(QuickGlassButtonStyle())
            }
        }
        .padding(16)
        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private var quickActions: some View {
        HStack(spacing: 12) {
            ForEach(Array(recentItems.enumerated()), id: \.element.id) { index, item in
                RecentItemChip(
                    index: index,
                    item: item,
                    previewImage: clipboardManager.previewImage(for: item),
                    isSelected: item.id == selectedItemID,
                    onTap: {
                        selectedItemID = item.id
                    },
                    onDoubleTap: {
                        onActivateItem(item, true)
                    }
                )
            }

            if recentItems.isEmpty {
                Text("Copy something to start building a tray.")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.55))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(18)
                    .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
        }
    }

    private var productivityStrip: some View {
        HStack(spacing: 10) {
            StatPill(title: "Items", value: "\(clipboardManager.items.count)")
            StatPill(title: "Pinned", value: "\(pinnedCount)")
            StatPill(title: "Mode", value: clipboardManager.displayMode == .list ? "List" : "Tiles")

            Button(clipboardManager.isMonitoringEnabled ? "Pause Capture" : "Resume Capture") {
                clipboardManager.toggleMonitoring()
            }
            .buttonStyle(QuickGlassButtonStyle(fill: clipboardManager.isMonitoringEnabled ? Color.white.opacity(0.1) : Color.orange.opacity(0.65)))

            Button(clipboardManager.showPinnedOnly ? "Pinned Only" : "All Items") {
                clipboardManager.showPinnedOnly.toggle()
            }
            .buttonStyle(QuickGlassButtonStyle(fill: clipboardManager.showPinnedOnly ? Color.white.opacity(0.2) : Color.white.opacity(0.08)))

            Spacer()

            Button("Paste Selected") {
                pasteSelected()
            }
            .buttonStyle(QuickGlassButtonStyle(fill: Color.white.opacity(0.14)))

            Button("Copy Selected") {
                copySelected()
            }
            .buttonStyle(QuickGlassButtonStyle())

            if selectedItem?.kind == .file {
                Button("Copy Path") {
                    copySelectedPath()
                }
                .buttonStyle(QuickGlassButtonStyle())

                Button("Open") {
                    openSelected()
                }
                .buttonStyle(QuickGlassButtonStyle())
            }
        }
    }

    private var tabs: some View {
        HStack(spacing: 10) {
            ForEach(Array(ClipboardCategory.allCases.enumerated()), id: \.element.id) { index, category in
                Button {
                    clipboardManager.selectedCategory = category
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: category.symbolName)
                        Text(category.title)
                        Text("\(index + 1)")
                            .opacity(0.56)
                    }
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(clipboardManager.selectedCategory == category ? Color.black : Color.white.opacity(0.76))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(clipboardManager.selectedCategory == category ? Color.white.opacity(0.94) : Color.white.opacity(0.07))
                    )
                }
                .buttonStyle(.plain)
            }

            Spacer()

            Text(clipboardManager.showPinnedOnly ? "Pinned • \(activeTypeFilterLabel)" : activeTypeFilterLabel)
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.58))
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(.white.opacity(0.06), in: Capsule())
        }
    }

    private var contentArea: some View {
        Group {
            if visibleItems.isEmpty {
                emptyState
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        if clipboardManager.displayMode == .list {
                            LazyVStack(spacing: 12) {
                                ForEach(visibleItems) { item in
                                    LauncherListCard(
                                        item: item,
                                        previewImage: clipboardManager.previewImage(for: item),
                                        isSelected: item.id == selectedItemID,
                                        onSelect: { selectedItemID = item.id },
                                        onCopy: { onActivateItem(item, false) },
                                        onPaste: { onActivateItem(item, true) },
                                        onCopyPath: item.kind == .file ? { clipboardManager.copyPathToClipboard(item: item) } : nil,
                                        onOpen: item.kind == .file ? { clipboardManager.openFile(item) } : nil,
                                        onEdit: item.canEdit ? { editingItem = item } : nil,
                                        onDetail: { detailItem = item },
                                        onDelete: { clipboardManager.removeItem(id: item.id) },
                                        onPin: { clipboardManager.togglePin(for: item.id) }
                                    )
                                    .id(item.id)
                                }
                            }
                        } else {
                            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: tileColumns), spacing: 12) {
                                ForEach(visibleItems) { item in
                                    LauncherTileCard(
                                        item: item,
                                        previewImage: clipboardManager.previewImage(for: item),
                                        isSelected: item.id == selectedItemID,
                                        onSelect: { selectedItemID = item.id },
                                        onCopy: { onActivateItem(item, false) },
                                        onPaste: { onActivateItem(item, true) },
                                        onCopyPath: item.kind == .file ? { clipboardManager.copyPathToClipboard(item: item) } : nil,
                                        onOpen: item.kind == .file ? { clipboardManager.openFile(item) } : nil,
                                        onEdit: item.canEdit ? { editingItem = item } : nil,
                                        onDetail: { detailItem = item },
                                        onDelete: { clipboardManager.removeItem(id: item.id) },
                                        onPin: { clipboardManager.togglePin(for: item.id) }
                                    )
                                    .id(item.id)
                                }
                            }
                        }
                    }
                    .onChange(of: selectedItemID) { itemID in
                        guard let itemID else { return }
                        withAnimation(.easeInOut(duration: 0.18)) {
                            proxy.scrollTo(itemID, anchor: .center)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Spacer()
            Image(systemName: "tray.and.arrow.down.fill")
                .font(.system(size: 34, weight: .black))
                .foregroundStyle(.white.opacity(0.34))
            Text("No items in this view")
                .font(.system(size: 22, weight: .black, design: .rounded))
                .foregroundStyle(.white)
            Text("Try a different tab, clear the file type filter, or copy a new item.")
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.58))
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
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
                RoundedRectangle(cornerRadius: 30, style: .continuous)
                    .fill(Color(red: 0.12, green: 0.14, blue: 0.17).opacity(0.96))
                    .overlay(
                        RoundedRectangle(cornerRadius: 30, style: .continuous)
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
                    "Arrow keys move selection, Return pastes, and Space previews the selected item.",
                    "Use ⌘F to jump into search, ⌘1-6 to switch tabs, and T to flip between list and tile view.",
                    "Use ⌥⌘2-5 to instantly paste the 2nd, 3rd, 4th, or 5th most recent clipboard item."
                ]
            )
        ]
    }

    private var onboardingPage: OnboardingPage {
        onboardingPages[min(max(onboardingStep, 0), onboardingPages.count - 1)]
    }

    private func syncSelection() {
        if let selectedItemID, visibleItems.contains(where: { $0.id == selectedItemID }) {
            return
        }
        selectedItemID = visibleItems.first?.id
    }

    private func copySelected() {
        guard let selectedItem else { return }
        onActivateItem(selectedItem, false)
    }

    private func pasteSelected() {
        guard let selectedItem else { return }
        onActivateItem(selectedItem, true)
    }

    private func copySelectedPath() {
        guard let selectedItem else { return }
        clipboardManager.copyPathToClipboard(item: selectedItem)
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
                if modifiers.contains(.shift) {
                    copySelectedPath()
                } else {
                    copySelected()
                }
                return true
            case kVK_ANSI_E:
                if let selectedItem, selectedItem.canEdit {
                    editingItem = selectedItem
                }
                return true
            case kVK_ANSI_P:
                if let selectedItem {
                    clipboardManager.togglePin(for: selectedItem.id)
                }
                return true
            case kVK_ANSI_O:
                openSelected()
                return true
            case kVK_ANSI_R:
                revealSelected()
                return true
            case kVK_Delete, kVK_ForwardDelete:
                if let selectedItem {
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
            case kVK_ANSI_Comma:
                withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                    showSettings.toggle()
                }
                return true
            default:
                break
            }
        }

        switch Int(event.keyCode) {
        case kVK_Escape:
            onClose()
            return true
        case kVK_Return:
            pasteSelected()
            return true
        case kVK_Space:
            if let selectedItem {
                detailItem = selectedItem
            }
            return true
        case kVK_LeftArrow:
            moveSelection(step: -1)
            return true
        case kVK_RightArrow:
            moveSelection(step: 1)
            return true
        case kVK_UpArrow:
            moveSelection(step: clipboardManager.displayMode == .tiles ? -tileColumns : -1)
            return true
        case kVK_DownArrow:
            moveSelection(step: clipboardManager.displayMode == .tiles ? tileColumns : 1)
            return true
        case kVK_ANSI_S:
            withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                showSettings.toggle()
            }
            return true
        case kVK_ANSI_T:
            clipboardManager.displayMode = clipboardManager.displayMode == .list ? .tiles : .list
            return true
        case kVK_ANSI_P:
            clipboardManager.showPinnedOnly.toggle()
            return true
        case kVK_ANSI_Slash:
            isSearchFocused = true
            return true
        default:
            return false
        }
    }

    private func moveSelection(step: Int) {
        guard let currentIndex = visibleItems.firstIndex(where: { $0.id == selectedItemID }) else {
            selectedItemID = visibleItems.first?.id
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
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.09, green: 0.1, blue: 0.13), Color(red: 0.12, green: 0.16, blue: 0.19)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Circle()
                .fill(Color(red: 0.91, green: 0.55, blue: 0.33).opacity(0.24))
                .frame(width: 260, height: 260)
                .blur(radius: 14)
                .offset(x: -260, y: -230)

            Circle()
                .fill(Color(red: 0.37, green: 0.62, blue: 0.95).opacity(0.18))
                .frame(width: 320, height: 320)
                .blur(radius: 30)
                .offset(x: 300, y: 240)

            RoundedRectangle(cornerRadius: 34, style: .continuous)
                .fill(.ultraThinMaterial.opacity(0.78))
                .overlay(
                    RoundedRectangle(cornerRadius: 34, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.14), lineWidth: 1)
                )
        }
        .clipShape(RoundedRectangle(cornerRadius: 34, style: .continuous))
        .shadow(color: Color.black.opacity(0.35), radius: 28, y: 22)
        .padding(6)
    }
}

private struct HotkeyPill: View {
    let text: String
    let shortcut: String

    var body: some View {
        HStack(spacing: 8) {
            Text(text.uppercased())
                .foregroundStyle(.white.opacity(0.5))
            Text(shortcut)
                .foregroundStyle(.white)
        }
        .font(.system(size: 11, weight: .heavy, design: .rounded))
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(.white.opacity(0.06), in: Capsule())
    }
}

private struct ShortcutHint: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .bold, design: .rounded))
            .foregroundStyle(.white.opacity(0.62))
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(.white.opacity(0.06), in: Capsule())
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
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.white.opacity(0.46))
            TextField("Search names, snippets, and paths", text: $text)
                .textFieldStyle(.plain)
                .foregroundStyle(.white)
                .focused(isFocused)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

private struct ModeToggle: View {
    @Binding var selection: ClipboardDisplayMode

    var body: some View {
        HStack(spacing: 6) {
            ForEach(ClipboardDisplayMode.allCases) { mode in
                Button {
                    selection = mode
                } label: {
                    Image(systemName: mode.symbolName)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(selection == mode ? Color.black : Color.white.opacity(0.72))
                        .frame(width: 38, height: 34)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(selection == mode ? Color.white : Color.white.opacity(0.06))
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

private struct StatPill: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title.uppercased())
                .font(.system(size: 9, weight: .black, design: .rounded))
                .foregroundStyle(.white.opacity(0.44))
            Text(value)
                .font(.system(size: 14, weight: .black, design: .rounded))
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

private struct RecentItemChip: View {
    let index: Int
    let item: ClipboardItem
    let previewImage: NSImage?
    let isSelected: Bool
    let onTap: () -> Void
    let onDoubleTap: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text(index == 0 ? "LATEST" : "⌥⌘\(index + 1)")
                    .font(.system(size: 10, weight: .black, design: .rounded))
                    .foregroundStyle(.white.opacity(0.54))
                Spacer()
                if item.isPinned {
                    Image(systemName: "pin.fill")
                        .font(.system(size: 10, weight: .black))
                        .foregroundStyle(Color(red: 1, green: 0.82, blue: 0.38))
                }
            }

            HStack(spacing: 12) {
                PreviewBadge(item: item, previewImage: previewImage, side: 46)
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.title)
                        .lineLimit(1)
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    Text(item.fileTypeToken.uppercased())
                        .font(.system(size: 10, weight: .black, design: .rounded))
                        .foregroundStyle(.white.opacity(0.46))
                }
                Spacer()
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(isSelected ? Color.white.opacity(0.14) : Color.white.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(isSelected ? Color.white.opacity(0.24) : Color.clear, lineWidth: 1)
                )
        )
        .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .onTapGesture(perform: onTap)
        .onTapGesture(count: 2, perform: onDoubleTap)
    }
}

private struct LauncherListCard: View {
    let item: ClipboardItem
    let previewImage: NSImage?
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

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            PreviewBadge(item: item, previewImage: previewImage, side: 72)

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    Text(item.title)
                        .lineLimit(1)
                        .font(.system(size: 16, weight: .black, design: .rounded))
                        .foregroundStyle(.white)

                    Label(item.fileTypeToken.uppercased(), systemImage: item.primaryCategory.symbolName)
                        .font(.system(size: 10, weight: .black, design: .rounded))
                        .foregroundStyle(.white.opacity(0.52))
                }

                Text(item.detailText)
                    .lineLimit(2)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.66))

                HStack(spacing: 8) {
                    if item.isPinned {
                        MiniMetaLabel(text: "Pinned", accent: Color(red: 1, green: 0.84, blue: 0.38))
                    }
                    MiniMetaLabel(text: item.timestamp.formatted(date: .omitted, time: .shortened), accent: .white.opacity(0.2))
                }
            }

            Spacer()

            HStack(spacing: 8) {
                ActionButton(symbol: "doc.on.doc.fill", title: "Copy", action: onCopy)
                ActionButton(symbol: "arrowshape.turn.up.right.fill", title: "Paste", action: onPaste)
                if let onOpen {
                    ActionButton(symbol: "arrow.up.forward.app.fill", title: "Open", action: onOpen)
                }
                if let onCopyPath {
                    ActionButton(symbol: "link", title: "Path", action: onCopyPath)
                }
                if let onEdit {
                    ActionButton(symbol: "pencil", title: "Edit", action: onEdit)
                }
                ActionButton(symbol: "eye.fill", title: "Detail", action: onDetail)
                ActionButton(symbol: item.isPinned ? "pin.slash.fill" : "pin.fill", title: "Pin", action: onPin)
                ActionButton(symbol: "trash.fill", title: "Delete", action: onDelete)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(isSelected ? Color.white.opacity(0.13) : Color.white.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .strokeBorder(isSelected ? Color.white.opacity(0.2) : Color.white.opacity(0.06), lineWidth: 1)
                )
        )
        .contentShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .onTapGesture(perform: onSelect)
        .onTapGesture(count: 2, perform: onPaste)
        .onDrag {
            item.dragItemProvider() ?? NSItemProvider()
        }
    }
}

private struct LauncherTileCard: View {
    let item: ClipboardItem
    let previewImage: NSImage?
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

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ZStack(alignment: .topTrailing) {
                PreviewCanvas(item: item, previewImage: previewImage)

                if item.isPinned {
                    Image(systemName: "pin.fill")
                        .font(.system(size: 11, weight: .black))
                        .foregroundStyle(Color(red: 1, green: 0.84, blue: 0.38))
                        .padding(8)
                        .background(.black.opacity(0.2), in: Circle())
                        .padding(10)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(item.title)
                    .lineLimit(1)
                    .font(.system(size: 15, weight: .black, design: .rounded))
                    .foregroundStyle(.white)

                Text(item.detailText)
                    .lineLimit(3)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.62))
            }

            HStack(spacing: 8) {
                SmallActionButton(symbol: "doc.on.doc.fill", action: onCopy)
                SmallActionButton(symbol: "arrowshape.turn.up.right.fill", action: onPaste)
                if let onOpen {
                    SmallActionButton(symbol: "arrow.up.forward.app.fill", action: onOpen)
                }
                if let onCopyPath {
                    SmallActionButton(symbol: "link", action: onCopyPath)
                }
                if let onEdit {
                    SmallActionButton(symbol: "pencil", action: onEdit)
                }
                SmallActionButton(symbol: "eye.fill", action: onDetail)
                SmallActionButton(symbol: item.isPinned ? "pin.slash.fill" : "pin.fill", action: onPin)
                Spacer()
                SmallActionButton(symbol: "trash.fill", action: onDelete)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 282, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(isSelected ? Color.white.opacity(0.13) : Color.white.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 26, style: .continuous)
                        .strokeBorder(isSelected ? Color.white.opacity(0.22) : Color.white.opacity(0.05), lineWidth: 1)
                )
        )
        .contentShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .onTapGesture(perform: onSelect)
        .onTapGesture(count: 2, perform: onPaste)
        .onDrag {
            item.dragItemProvider() ?? NSItemProvider()
        }
    }
}

private struct PreviewBadge: View {
    let item: ClipboardItem
    let previewImage: NSImage?
    let side: CGFloat

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: side * 0.28, style: .continuous)
                .fill(Color.white.opacity(0.09))

            if let previewImage {
                Image(nsImage: previewImage)
                    .resizable()
                    .scaledToFill()
                    .frame(width: side, height: side)
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: side * 0.28, style: .continuous))
            } else {
                Image(systemName: iconName)
                    .font(.system(size: side * 0.32, weight: .black))
                    .foregroundStyle(.white.opacity(0.76))
            }
        }
        .frame(width: side, height: side)
    }

    private var iconName: String {
        switch item.kind {
        case .text:
            return "text.alignleft"
        case .image:
            return "photo.fill"
        case .file:
            return item.primaryCategory == .video ? "film.stack.fill" : "doc.fill"
        }
    }
}

private struct PreviewCanvas: View {
    let item: ClipboardItem
    let previewImage: NSImage?

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.black.opacity(0.2))

            if let previewImage {
                Image(nsImage: previewImage)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity, minHeight: 150, maxHeight: 150)
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            } else if item.kind == .text, let textContent = item.textContent {
                Text(textContent)
                    .lineLimit(6)
                    .multilineTextAlignment(.leading)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding(18)
            } else {
                Image(systemName: item.primaryCategory.symbolName)
                    .font(.system(size: 34, weight: .black))
                    .foregroundStyle(.white.opacity(0.72))
            }
        }
        .frame(height: 150)
    }
}

private struct MiniMetaLabel: View {
    let text: String
    let accent: Color

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 10, weight: .black, design: .rounded))
            .foregroundStyle(.white.opacity(0.62))
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(accent, in: Capsule())
    }
}

private struct ActionButton: View {
    let symbol: String
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 5) {
                Image(systemName: symbol)
                    .font(.system(size: 12, weight: .bold))
                Text(title)
                    .font(.system(size: 10, weight: .black, design: .rounded))
            }
            .foregroundStyle(.white.opacity(0.78))
            .frame(width: 56, height: 54)
            .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

private struct SmallActionButton: View {
    let symbol: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .black))
                .foregroundStyle(.white.opacity(0.82))
                .frame(width: 30, height: 30)
                .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
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
    let onCopy: () -> Void
    let onPaste: () -> Void
    let onReveal: () -> Void
    let onOpen: () -> Void
    let onCopyPath: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(item.title)
                .font(.system(size: 22, weight: .black, design: .rounded))

            if let previewImage {
                Image(nsImage: previewImage)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: 240)
                    .background(Color.black.opacity(0.04), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            } else if let textContent = item.textContent {
                ScrollView {
                    Text(textContent)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
                .frame(maxWidth: .infinity, maxHeight: 240)
                .padding()
                .background(Color.black.opacity(0.04), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }

            Text(item.detailText)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)

            HStack(spacing: 10) {
                Button("Copy") {
                    onCopy()
                    dismiss()
                }
                .buttonStyle(.borderedProminent)

                Button("Paste") {
                    onPaste()
                    dismiss()
                }
                .buttonStyle(.borderedProminent)

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
        .frame(width: 620, height: 460)
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

private struct PanelKeyHandler: NSViewRepresentable {
    let onKeyDown: (NSEvent) -> Bool

    func makeNSView(context: Context) -> KeyView {
        let view = KeyView()
        view.onKeyDown = onKeyDown
        DispatchQueue.main.async {
            view.window?.makeFirstResponder(view)
        }
        return view
    }

    func updateNSView(_ nsView: KeyView, context: Context) {
        nsView.onKeyDown = onKeyDown
        DispatchQueue.main.async {
            nsView.window?.makeFirstResponder(nsView)
        }
    }

    final class KeyView: NSView {
        var onKeyDown: ((NSEvent) -> Bool)?

        override var acceptsFirstResponder: Bool {
            true
        }

        override func keyDown(with event: NSEvent) {
            if onKeyDown?(event) == true {
                return
            }
            super.keyDown(with: event)
        }
    }
}
