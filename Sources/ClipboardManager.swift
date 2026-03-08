import SwiftUI
import AppKit
import UniformTypeIdentifiers
import QuickLookThumbnailing
import Carbon.HIToolbox

enum ClipboardKind: String, Codable {
    case text
    case image
    case file
}

enum ClipboardCategory: String, CaseIterable, Identifiable {
    case mixed
    case text
    case images
    case video
    case documents
    case files

    var id: String { rawValue }

    var title: String {
        switch self {
        case .mixed: return "Mixed"
        case .text: return "Text"
        case .images: return "Images"
        case .video: return "Video"
        case .documents: return "Docs"
        case .files: return "Files"
        }
    }

    var symbolName: String {
        switch self {
        case .mixed: return "square.stack.3d.up.fill"
        case .text: return "text.alignleft"
        case .images: return "photo.fill"
        case .video: return "film.stack.fill"
        case .documents: return "doc.text.fill"
        case .files: return "folder.fill"
        }
    }
}

enum ClipboardDisplayMode: String, CaseIterable, Identifiable {
    case list
    case tiles

    var id: String { rawValue }

    var symbolName: String {
        switch self {
        case .list: return "list.bullet.rectangle.portrait"
        case .tiles: return "square.grid.2x2.fill"
        }
    }
}

final class ClipboardItem: Identifiable, Hashable, Codable {
    let id: UUID
    let kind: ClipboardKind
    var textContent: String?
    var imageData: Data?
    var filePath: String?
    var timestamp: Date
    var isPinned: Bool

    private var cachedImage: NSImage?
    private var cachedContentType: UTType?

    var fileURL: URL? {
        guard let filePath else { return nil }
        return URL(fileURLWithPath: filePath)
    }

    var imageContent: NSImage? {
        guard kind == .image else { return nil }
        if let cachedImage {
            return cachedImage
        }
        guard let imageData else { return nil }
        let image = NSImage(data: imageData)
        cachedImage = image
        return image
    }

    var contentType: UTType? {
        if let cachedContentType {
            return cachedContentType
        }

        guard let fileURL else { return nil }
        if let resourceValues = try? fileURL.resourceValues(forKeys: [.contentTypeKey]),
           let detectedType = resourceValues.contentType {
            cachedContentType = detectedType
            return detectedType
        }

        let fallbackType = UTType(filenameExtension: fileURL.pathExtension)
        cachedContentType = fallbackType
        return fallbackType
    }

    var title: String {
        switch kind {
        case .text:
            let firstLine = textContent?
                .split(whereSeparator: \.isNewline)
                .first?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return firstLine.isEmpty ? "Untitled text clip" : String(firstLine.prefix(120))
        case .image:
            return "Image clip"
        case .file:
            return fileURL?.lastPathComponent ?? "Missing file"
        }
    }

    var detailText: String {
        switch kind {
        case .text:
            let trimmed = textContent?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if trimmed.isEmpty {
                return "Empty text item"
            }
            return String(trimmed.prefix(220))
        case .image:
            let width = Int(imageContent?.size.width ?? 0)
            let height = Int(imageContent?.size.height ?? 0)
            return "\(width) × \(height)"
        case .file:
            if let fileURL {
                return fileURL.path
            }
            return "Original file is unavailable"
        }
    }

    var primaryCategory: ClipboardCategory {
        switch kind {
        case .text:
            return .text
        case .image:
            return .images
        case .file:
            guard let type = contentType else { return .files }
            if type.conforms(to: UTType.movie) || type.conforms(to: UTType.audiovisualContent) {
                return .video
            }
            if type.conforms(to: UTType.image) {
                return .images
            }
            let isDocument = type.conforms(to: UTType.text)
                || type.conforms(to: UTType.pdf)
                || type.conforms(to: UTType.content)
                || type.identifier.contains("spreadsheet")
                || type.identifier.contains("presentation")
                || type.identifier.contains("wordprocessing")
                || type.identifier.contains("office")
            if isDocument {
                return .documents
            }
            return .files
        }
    }

    var fileTypeToken: String {
        switch kind {
        case .text:
            return "text"
        case .image:
            return "image"
        case .file:
            if let fileURL, fileURL.hasDirectoryPath {
                return "folder"
            }
            let ext = fileURL?.pathExtension.lowercased() ?? ""
            if !ext.isEmpty {
                return ext
            }
            if let type = contentType?.preferredFilenameExtension {
                return type.lowercased()
            }
            return "file"
        }
    }

    var searchableText: String {
        switch kind {
        case .text:
            return [title, textContent ?? ""].joined(separator: " ")
        case .image:
            return [title, detailText, fileTypeToken].joined(separator: " ")
        case .file:
            let localizedDescription = contentType?.localizedDescription ?? ""
            return [title, detailText, fileTypeToken, localizedDescription].joined(separator: " ")
        }
    }

    var canEdit: Bool {
        kind == .text
    }

    enum CodingKeys: String, CodingKey {
        case id
        case kind
        case textContent
        case imageData
        case filePath
        case timestamp
        case isPinned
    }

    init(text: String) {
        id = UUID()
        kind = .text
        textContent = text
        imageData = nil
        filePath = nil
        timestamp = Date()
        isPinned = false
    }

    required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        kind = try container.decode(ClipboardKind.self, forKey: .kind)
        textContent = try container.decodeIfPresent(String.self, forKey: .textContent)
        imageData = try container.decodeIfPresent(Data.self, forKey: .imageData)
        filePath = try container.decodeIfPresent(String.self, forKey: .filePath)
        timestamp = try container.decode(Date.self, forKey: .timestamp)
        isPinned = try container.decode(Bool.self, forKey: .isPinned)
        cachedImage = nil
        cachedContentType = nil
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(kind, forKey: .kind)
        try container.encodeIfPresent(textContent, forKey: .textContent)
        try container.encodeIfPresent(imageData, forKey: .imageData)
        try container.encodeIfPresent(filePath, forKey: .filePath)
        try container.encode(timestamp, forKey: .timestamp)
        try container.encode(isPinned, forKey: .isPinned)
    }

    init(image: NSImage) {
        id = UUID()
        kind = .image
        textContent = nil
        imageData = image.tiffRepresentation
        filePath = nil
        timestamp = Date()
        isPinned = false
        cachedImage = image
    }

    init(fileURL: URL) {
        id = UUID()
        kind = .file
        textContent = nil
        imageData = nil
        filePath = fileURL.path
        timestamp = Date()
        isPinned = false
    }

    func dragItemProvider() -> NSItemProvider? {
        switch kind {
        case .text:
            guard let textContent else { return nil }
            return NSItemProvider(object: textContent as NSString)
        case .image:
            guard let imageContent else { return nil }
            return NSItemProvider(object: imageContent)
        case .file:
            guard let fileURL else { return nil }
            return NSItemProvider(contentsOf: fileURL)
        }
    }

    func matchesSamePayload(as other: ClipboardItem) -> Bool {
        guard kind == other.kind else { return false }

        switch kind {
        case .text:
            return textContent == other.textContent
        case .image:
            return imageData == other.imageData
        case .file:
            return filePath == other.filePath
        }
    }

    func snapshot() -> ClipboardItem {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        return try! decoder.decode(ClipboardItem.self, from: encoder.encode(self))
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: ClipboardItem, rhs: ClipboardItem) -> Bool {
        lhs.id == rhs.id
    }
}

private enum PreviewFactory {
    static func previewImage(for item: ClipboardItem) -> NSImage? {
        guard let fileURL = item.fileURL else { return nil }

        if let quickLookImage = quickLookThumbnail(for: fileURL) {
            quickLookImage.size = NSSize(width: 320, height: 200)
            return quickLookImage
        }

        return fallbackApplicationIcon(for: fileURL)
    }

    private static func quickLookThumbnail(for fileURL: URL) -> NSImage? {
        let scale = NSScreen.main?.backingScaleFactor ?? 2
        let request = QLThumbnailGenerator.Request(
            fileAt: fileURL,
            size: CGSize(width: 560, height: 420),
            scale: scale,
            representationTypes: .all
        )

        let semaphore = DispatchSemaphore(value: 0)
        var resultImage: NSImage?

        QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { representation, _ in
            defer { semaphore.signal() }
            guard let cgImage = representation?.cgImage else { return }
            resultImage = NSImage(
                cgImage: cgImage,
                size: NSSize(width: cgImage.width, height: cgImage.height)
            )
        }

        semaphore.wait()
        return resultImage
    }

    private static func fallbackApplicationIcon(for fileURL: URL) -> NSImage? {
        if let applicationURL = NSWorkspace.shared.urlForApplication(toOpen: fileURL) {
            let icon = NSWorkspace.shared.icon(forFile: applicationURL.path)
            icon.size = NSSize(width: 128, height: 128)
            return icon
        }

        let icon = NSWorkspace.shared.icon(forFile: fileURL.path)
        icon.size = NSSize(width: 128, height: 128)
        return icon
    }
}

final class ClipboardManager: ObservableObject {
    static let shared = ClipboardManager()

    private static let retentionLimitKey = "unpinnedRetentionLimit"
    private static let monitoringEnabledKey = "clipboardMonitoringEnabled"
    private static let defaultUnpinnedRetentionLimit = 30
    private static let minUnpinnedRetentionLimit = 1
    private static let maxUnpinnedRetentionLimit = 500

    @Published var unpinnedRetentionLimit: Int {
        didSet {
            persistAndApplyRetentionLimit()
        }
    }

    @Published var items: [ClipboardItem] = [] {
        didSet {
            saveItems()
            refreshDisplayedItems()
        }
    }

    @Published var searchQuery = "" {
        didSet {
            refreshDisplayedItems()
        }
    }

    @Published var selectedCategory: ClipboardCategory = .mixed {
        didSet {
            if !availableFileTypeFilters.contains(fileTypeFilter) {
                fileTypeFilter = "all"
            }
            refreshDisplayedItems()
        }
    }

    @Published var fileTypeFilter = "all" {
        didSet {
            refreshDisplayedItems()
        }
    }

    @Published var showPinnedOnly = false {
        didSet {
            refreshDisplayedItems()
        }
    }

    @Published var isMonitoringEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isMonitoringEnabled, forKey: Self.monitoringEnabledKey)
            isMonitoringEnabled ? startMonitoring() : stopMonitoring()
        }
    }

    @Published var displayMode: ClipboardDisplayMode = .list
    @Published private(set) var displayedItems: [ClipboardItem] = []
    @Published private(set) var previewImages: [UUID: NSImage] = [:]

    private let pasteboard = NSPasteboard.general
    private let previewQueue = DispatchQueue(label: "com.gemini.quicktray.previews", qos: .userInitiated)
    private var timer: Timer?
    private var lastChangeCount: Int

    private static func clampedRetentionLimit(_ value: Int) -> Int {
        min(max(value, minUnpinnedRetentionLimit), maxUnpinnedRetentionLimit)
    }

    private var persistenceURL: URL? {
        guard let supportDirectory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }

        let appDirectory = supportDirectory.appendingPathComponent("com.gemini.QuickTray")
        try? FileManager.default.createDirectory(at: appDirectory, withIntermediateDirectories: true)
        return appDirectory.appendingPathComponent("items.json")
    }

    private init() {
        let savedLimit = UserDefaults.standard.integer(forKey: Self.retentionLimitKey)
        let initialLimit = savedLimit > 0 ? savedLimit : Self.defaultUnpinnedRetentionLimit
        unpinnedRetentionLimit = Self.clampedRetentionLimit(initialLimit)
        isMonitoringEnabled = UserDefaults.standard.object(forKey: Self.monitoringEnabledKey) as? Bool ?? true
        lastChangeCount = pasteboard.changeCount

        loadItems()
        trimUnpinnedItemsToLimit()
        loadInitialPreviews()
        refreshDisplayedItems()
        if isMonitoringEnabled {
            startMonitoring()
        }
    }

    var availableFileTypeFilters: [String] {
        let filteredItems = sortedItems().filter { item in
            selectedCategory == .mixed || item.primaryCategory == selectedCategory
        }

        let tokens = Set(filteredItems.map(\.fileTypeToken))
        return ["all"] + tokens.sorted()
    }

    func startMonitoring() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.45, repeats: true) { [weak self] _ in
            self?.checkClipboard()
        }
    }

    func stopMonitoring() {
        timer?.invalidate()
        timer = nil
    }

    func checkClipboard() {
        guard pasteboard.changeCount != lastChangeCount else { return }
        lastChangeCount = pasteboard.changeCount

        let fileOptions: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true]
        if let fileURLs = pasteboard.readObjects(forClasses: [NSURL.self], options: fileOptions) as? [URL],
           !fileURLs.isEmpty {
            for fileURL in fileURLs.reversed() {
                addItem(ClipboardItem(fileURL: fileURL))
            }
            return
        }

        if let image = NSImage(pasteboard: pasteboard) {
            addItem(ClipboardItem(image: image))
            return
        }

        if let string = pasteboard.string(forType: .string) {
            addItem(ClipboardItem(text: string))
        }
    }

    func togglePin(for id: UUID) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].isPinned.toggle()
        items = items
    }

    func clearAll() {
        items.removeAll()
        previewImages.removeAll()
    }

    func removeItem(id: UUID) {
        items.removeAll { $0.id == id }
        previewImages[id] = nil
    }

    func copyToClipboard(item: ClipboardItem, shouldPaste: Bool = false) {
        pasteboard.clearContents()

        switch item.kind {
        case .text:
            if let textContent = item.textContent {
                pasteboard.setString(textContent, forType: .string)
            }
        case .image:
            if let imageContent = item.imageContent {
                pasteboard.writeObjects([imageContent])
            }
        case .file:
            if let fileURL = item.fileURL {
                pasteboard.writeObjects([fileURL as NSURL])
            }
        }

        lastChangeCount = pasteboard.changeCount
        addItem(item, refreshTimestamp: true)

        guard shouldPaste else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) {
            Self.issuePasteShortcut()
        }
    }

    func quickPasteRecent(offsetFromLatest offset: Int) {
        let recentItems = items.sorted { $0.timestamp > $1.timestamp }
        guard recentItems.indices.contains(offset) else { return }
        copyToClipboard(item: recentItems[offset], shouldPaste: true)
    }

    func toggleMonitoring() {
        isMonitoringEnabled.toggle()
    }

    func updateText(for id: UUID, newValue: String) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].textContent = newValue
        items[index].timestamp = Date()
        items = items
    }

    func copyPathToClipboard(item: ClipboardItem) {
        guard let fileURL = item.fileURL else { return }
        pasteboard.clearContents()
        pasteboard.setString(fileURL.path, forType: .string)
        lastChangeCount = pasteboard.changeCount
    }

    func previewImage(for item: ClipboardItem) -> NSImage? {
        switch item.kind {
        case .image:
            return item.imageContent
        case .text:
            return nil
        case .file:
            if let image = previewImages[item.id] {
                return image
            }

            loadPreview(for: item)
            return nil
        }
    }

    func revealInFinder(_ item: ClipboardItem) {
        guard let fileURL = item.fileURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([fileURL])
    }

    func openFile(_ item: ClipboardItem) {
        guard let fileURL = item.fileURL else { return }
        NSWorkspace.shared.open(fileURL)
    }

    private func addItem(_ item: ClipboardItem, refreshTimestamp: Bool = false) {
        if let existingIndex = items.firstIndex(where: { $0.matchesSamePayload(as: item) }) {
            let existingItem = items[existingIndex]
            if refreshTimestamp {
                existingItem.timestamp = Date()
            }
            items = items
            loadPreview(for: existingItem)
            return
        }

        if refreshTimestamp {
            item.timestamp = Date()
        }

        items.append(item)
        trimUnpinnedItemsToLimit()
        loadPreview(for: item)
    }

    private func sortedItems() -> [ClipboardItem] {
        items.sorted {
            if $0.isPinned != $1.isPinned {
                return $0.isPinned && !$1.isPinned
            }
            return $0.timestamp > $1.timestamp
        }
    }

    private func itemMatchesCurrentCategory(_ item: ClipboardItem) -> Bool {
        selectedCategory == .mixed || item.primaryCategory == selectedCategory
    }

    private func itemMatchesCurrentTypeFilter(_ item: ClipboardItem) -> Bool {
        fileTypeFilter == "all" || item.fileTypeToken == fileTypeFilter
    }

    private func itemMatchesPinnedFilter(_ item: ClipboardItem) -> Bool {
        !showPinnedOnly || item.isPinned
    }

    private func searchScore(for item: ClipboardItem, query: String) -> Double {
        let normalizedQuery = normalize(query)
        guard !normalizedQuery.isEmpty else { return 1 }

        let haystack = normalize(item.searchableText)
        if haystack.contains(normalizedQuery) {
            return normalize(item.title).contains(normalizedQuery) ? 1.4 : 1.0
        }

        let queryTokens = Set(normalizedQuery.split(separator: " ").map(String.init))
        let haystackTokens = Set(haystack.split(separator: " ").map(String.init))
        guard !queryTokens.isEmpty, !haystackTokens.isEmpty else { return 0 }

        let overlap = queryTokens.intersection(haystackTokens).count
        guard overlap > 0 else { return 0 }

        let coverage = Double(overlap) / Double(queryTokens.count)
        let titleBonus = normalize(item.title).split(separator: " ").contains { queryTokens.contains(String($0)) } ? 0.2 : 0
        return coverage + titleBonus
    }

    private func refreshDisplayedItems() {
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        let filteredItems = sortedItems()
            .filter(itemMatchesCurrentCategory(_:))
            .filter(itemMatchesCurrentTypeFilter(_:))
            .filter(itemMatchesPinnedFilter(_:))

        guard !query.isEmpty else {
            displayedItems = filteredItems
            return
        }

        displayedItems = filteredItems
            .compactMap { item -> (ClipboardItem, Double)? in
                let score = searchScore(for: item, query: query)
                guard score > 0 else { return nil }
                return (item, score)
            }
            .sorted { lhs, rhs in
                if abs(lhs.1 - rhs.1) > 0.001 {
                    return lhs.1 > rhs.1
                }
                return lhs.0.timestamp > rhs.0.timestamp
            }
            .map(\.0)
    }

    private func trimUnpinnedItemsToLimit() {
        var unpinnedToRemove = items.filter { !$0.isPinned }.count - unpinnedRetentionLimit
        guard unpinnedToRemove > 0 else { return }

        let indexesToRemove = items
            .enumerated()
            .sorted { $0.element.timestamp < $1.element.timestamp }
            .compactMap { index, item -> Int? in
                guard !item.isPinned, unpinnedToRemove > 0 else { return nil }
                unpinnedToRemove -= 1
                return index
            }
            .sorted(by: >)

        for index in indexesToRemove {
            previewImages[items[index].id] = nil
            items.remove(at: index)
        }
    }

    private func loadInitialPreviews() {
        for item in items {
            loadPreview(for: item)
        }
    }

    private func loadPreview(for item: ClipboardItem) {
        guard item.kind == .file else { return }
        guard previewImages[item.id] == nil else { return }

        previewQueue.async { [weak self] in
            guard let self else { return }
            let image = PreviewFactory.previewImage(for: item)
            guard let image else { return }
            DispatchQueue.main.async {
                self.previewImages[item.id] = image
            }
        }
    }

    private func saveItems() {
        guard let persistenceURL else { return }
        let snapshot = items.map { $0.snapshot() }

        DispatchQueue.global(qos: .background).async {
            do {
                let data = try JSONEncoder().encode(snapshot)
                try data.write(to: persistenceURL)
            } catch {
                print("Failed to save clipboard history: \(error)")
            }
        }
    }

    private func loadItems() {
        guard let persistenceURL, FileManager.default.fileExists(atPath: persistenceURL.path) else { return }

        do {
            let data = try Data(contentsOf: persistenceURL)
            items = try JSONDecoder().decode([ClipboardItem].self, from: data)
        } catch {
            print("Failed to load clipboard history: \(error)")
        }
    }

    private func persistAndApplyRetentionLimit() {
        let clamped = Self.clampedRetentionLimit(unpinnedRetentionLimit)
        if clamped != unpinnedRetentionLimit {
            unpinnedRetentionLimit = clamped
            return
        }

        UserDefaults.standard.set(clamped, forKey: Self.retentionLimitKey)
        trimUnpinnedItemsToLimit()
    }

    private func normalize(_ value: String) -> String {
        value
            .lowercased()
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func issuePasteShortcut() {
        let options = [kAXTrustedCheckOptionPrompt.takeRetainedValue() as String: true] as CFDictionary
        guard AXIsProcessTrustedWithOptions(options) else { return }

        guard let source = CGEventSource(stateID: .combinedSessionState) else { return }
        let keyCode = CGKeyCode(kVK_ANSI_V)
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true)
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)
        keyDown?.flags = CGEventFlags.maskCommand
        keyUp?.flags = CGEventFlags.maskCommand
        keyDown?.post(tap: CGEventTapLocation.cghidEventTap)
        keyUp?.post(tap: CGEventTapLocation.cghidEventTap)
    }
}
