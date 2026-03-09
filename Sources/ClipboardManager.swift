import SwiftUI
import AppKit
import UniformTypeIdentifiers
import QuickLookThumbnailing
import Carbon.HIToolbox
import Vision

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
    case snippets

    var id: String { rawValue }

    var title: String {
        switch self {
        case .mixed: return "Mixed"
        case .text: return "Text"
        case .images: return "Images"
        case .video: return "Video"
        case .documents: return "Docs"
        case .files: return "Files"
        case .snippets: return "Snippets"
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
        case .snippets: return "text.bubble.fill"
        }
    }
}

enum TextTransformAction: String, CaseIterable, Identifiable {
    case formatJSON
    case urlEncode
    case urlDecode
    case lowercase
    case uppercase
    case stripWhitespace

    var id: String { rawValue }

    var title: String {
        switch self {
        case .formatJSON: return "Format JSON"
        case .urlEncode: return "URL Encode"
        case .urlDecode: return "URL Decode"
        case .lowercase: return "Lowercase"
        case .uppercase: return "UPPERCASE"
        case .stripWhitespace: return "Strip Extra Whitespace"
        }
    }

    var symbolName: String {
        switch self {
        case .formatJSON: return "curlybraces.square"
        case .urlEncode: return "link.badge.plus"
        case .urlDecode: return "link.badge.minus"
        case .lowercase: return "textformat.abc"
        case .uppercase: return "textformat"
        case .stripWhitespace: return "arrow.left.and.right.text.vertical"
        }
    }
}

enum ClipboardDisplayMode: String, CaseIterable, Identifiable {
    case compact
    case list
    case tiles

    var id: String { rawValue }

    var symbolName: String {
        switch self {
        case .compact: return "list.bullet"
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
    var imageDiskPath: String?
    var filePath: String?
    var sourceApplicationName: String?
    var sourceBundleIdentifier: String?
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
        guard let payload = imagePayloadData else { return nil }
        let image = NSImage(data: payload)
        if imageData != nil {
            cachedImage = image
        }
        return image
    }

    var imagePayloadData: Data? {
        if let imageData {
            return imageData
        }
        guard let imageDiskPath else { return nil }
        return try? Data(contentsOf: URL(fileURLWithPath: imageDiskPath))
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
        let sourceText = sourceApplicationName ?? ""
        switch kind {
        case .text:
            return [title, textContent ?? "", sourceText].joined(separator: " ")
        case .image:
            return [title, detailText, fileTypeToken, sourceText].joined(separator: " ")
        case .file:
            let localizedDescription = contentType?.localizedDescription ?? ""
            return [title, detailText, fileTypeToken, localizedDescription, sourceText].joined(separator: " ")
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
        case imageDiskPath
        case filePath
        case sourceApplicationName
        case sourceBundleIdentifier
        case timestamp
        case isPinned
    }

    init(
        text: String,
        sourceApplicationName: String? = nil,
        sourceBundleIdentifier: String? = nil
    ) {
        id = UUID()
        kind = .text
        textContent = text
        imageData = nil
        imageDiskPath = nil
        filePath = nil
        self.sourceApplicationName = sourceApplicationName
        self.sourceBundleIdentifier = sourceBundleIdentifier
        timestamp = Date()
        isPinned = false
    }

    required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        kind = try container.decode(ClipboardKind.self, forKey: .kind)
        textContent = try container.decodeIfPresent(String.self, forKey: .textContent)
        imageData = try container.decodeIfPresent(Data.self, forKey: .imageData)
        imageDiskPath = try container.decodeIfPresent(String.self, forKey: .imageDiskPath)
        filePath = try container.decodeIfPresent(String.self, forKey: .filePath)
        sourceApplicationName = try container.decodeIfPresent(String.self, forKey: .sourceApplicationName)
        sourceBundleIdentifier = try container.decodeIfPresent(String.self, forKey: .sourceBundleIdentifier)
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
        try container.encodeIfPresent(imageDiskPath, forKey: .imageDiskPath)
        try container.encodeIfPresent(filePath, forKey: .filePath)
        try container.encodeIfPresent(sourceApplicationName, forKey: .sourceApplicationName)
        try container.encodeIfPresent(sourceBundleIdentifier, forKey: .sourceBundleIdentifier)
        try container.encode(timestamp, forKey: .timestamp)
        try container.encode(isPinned, forKey: .isPinned)
    }

    init(
        imageData: Data,
        sourceApplicationName: String? = nil,
        sourceBundleIdentifier: String? = nil
    ) {
        id = UUID()
        kind = .image
        textContent = nil
        self.imageData = imageData
        imageDiskPath = nil
        filePath = nil
        self.sourceApplicationName = sourceApplicationName
        self.sourceBundleIdentifier = sourceBundleIdentifier
        timestamp = Date()
        isPinned = false
        cachedImage = nil
    }

    init(
        fileURL: URL,
        sourceApplicationName: String? = nil,
        sourceBundleIdentifier: String? = nil
    ) {
        id = UUID()
        kind = .file
        textContent = nil
        imageData = nil
        imageDiskPath = nil
        filePath = fileURL.path
        self.sourceApplicationName = sourceApplicationName
        self.sourceBundleIdentifier = sourceBundleIdentifier
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
            if imageDiskPath == other.imageDiskPath, imageDiskPath != nil {
                return true
            }
            return imagePayloadData == other.imagePayloadData
        case .file:
            return filePath == other.filePath
        }
    }

    func setImageDataInMemory(_ data: Data?) {
        imageData = data
        if data == nil {
            cachedImage = nil
        }
    }

    func clearImageCache() {
        cachedImage = nil
    }

    func snapshot(omitImageData: Bool = false) -> ClipboardItem {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        let copy = try! decoder.decode(ClipboardItem.self, from: encoder.encode(self))
        if omitImageData, copy.kind == .image {
            copy.imageData = nil
            copy.cachedImage = nil
        }
        return copy
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
    private static let imageRAMItemLimit = 20
    private static let stackPasteTimeout: TimeInterval = 45
    private static let stackCaptureWindow: TimeInterval = 15 * 60
    private static let secureBundleBlacklist: Set<String> = [
        "com.1password.1password",
        "com.1password.1password7",
        "com.bitwarden.desktop",
        "com.apple.keychainaccess"
    ]
    private static let secureNameBlacklist: [String] = [
        "1password",
        "bitwarden",
        "keychain access"
    ]

    @Published var unpinnedRetentionLimit: Int {
        didSet {
            persistAndApplyRetentionLimit()
        }
    }

    @Published var items: [ClipboardItem] = [] {
        didSet {
            historyRevision += 1
            saveItems()
            refreshDisplayedItems()
            enforceImageMemoryBudget()
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
    private var historyRevision = 0
    private var lastActivatedItemID: UUID?
    private var stackQueue: [UUID] = []
    private var stackCursor = 0
    private var stackQueueRevision = -1
    private var lastStackPasteDate: Date?
    private var sourceAppIconCache: [String: NSImage] = [:]

    private static func clampedRetentionLimit(_ value: Int) -> Int {
        min(max(value, minUnpinnedRetentionLimit), maxUnpinnedRetentionLimit)
    }

    private var appSupportDirectoryURL: URL? {
        guard let supportDirectory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }

        let appDirectory = supportDirectory.appendingPathComponent("com.gemini.QuickTray", isDirectory: true)
        try? FileManager.default.createDirectory(at: appDirectory, withIntermediateDirectories: true)
        return appDirectory
    }

    private var persistenceURL: URL? {
        appSupportDirectoryURL?.appendingPathComponent("items.json")
    }

    private var imageCacheDirectoryURL: URL? {
        guard let appSupportDirectoryURL else { return nil }
        let imageDirectory = appSupportDirectoryURL.appendingPathComponent("image-cache", isDirectory: true)
        try? FileManager.default.createDirectory(at: imageDirectory, withIntermediateDirectories: true)
        return imageDirectory
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

    func preferredSelectionID(in visibleItems: [ClipboardItem]) -> UUID? {
        guard !visibleItems.isEmpty else { return nil }
        if visibleItems.count > 1,
           let lastActivatedItemID,
           visibleItems[0].id == lastActivatedItemID {
            return visibleItems[1].id
        }
        return visibleItems[0].id
    }

    func sourceAppIcon(for item: ClipboardItem) -> NSImage? {
        if let bundleIdentifier = item.sourceBundleIdentifier {
            if let cachedIcon = sourceAppIconCache[bundleIdentifier] {
                return cachedIcon
            }

            var icon: NSImage?
            if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) {
                icon = NSWorkspace.shared.icon(forFile: appURL.path)
            } else if let runningIcon = NSWorkspace.shared.runningApplications
                .first(where: { $0.bundleIdentifier == bundleIdentifier })?.icon {
                icon = runningIcon
            }

            if let icon {
                icon.size = NSSize(width: 14, height: 14)
                sourceAppIconCache[bundleIdentifier] = icon
                return icon
            }
        }

        guard let sourceName = item.sourceApplicationName else { return nil }
        return NSWorkspace.shared.runningApplications.first(where: { $0.localizedName == sourceName })?.icon
    }

    var availableFileTypeFilters: [String] {
        let filteredItems = sortedItems().filter { item in
            selectedCategory == .mixed
                || selectedCategory == .snippets
                || item.primaryCategory == selectedCategory
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

        let sourceApplication = NSWorkspace.shared.frontmostApplication
        let sourceName = sourceApplication?.localizedName
        let sourceBundleIdentifier = sourceApplication?.bundleIdentifier
        if Self.isSecureSourceApplication(name: sourceName, bundleIdentifier: sourceBundleIdentifier) {
            return
        }

        let fileOptions: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true]
        if let fileURLs = pasteboard.readObjects(forClasses: [NSURL.self], options: fileOptions) as? [URL],
           !fileURLs.isEmpty {
            for fileURL in fileURLs.reversed() {
                addItem(
                    ClipboardItem(
                        fileURL: fileURL,
                        sourceApplicationName: sourceName,
                        sourceBundleIdentifier: sourceBundleIdentifier
                    )
                )
            }
            return
        }

        let imageData = pasteboard.data(forType: .tiff) ?? NSImage(pasteboard: pasteboard)?.tiffRepresentation
        if let imageData {
            addItem(
                ClipboardItem(
                    imageData: imageData,
                    sourceApplicationName: sourceName,
                    sourceBundleIdentifier: sourceBundleIdentifier
                )
            )
            return
        }

        if let string = pasteboard.string(forType: .string) {
            addItem(
                ClipboardItem(
                    text: string,
                    sourceApplicationName: sourceName,
                    sourceBundleIdentifier: sourceBundleIdentifier
                )
            )
        }
    }

    func togglePin(for id: UUID) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].isPinned.toggle()
        items = items
    }

    func clearAll() {
        removeAllImagePayloadsFromDisk()
        items.removeAll()
        previewImages.removeAll()
        stackQueue = []
        stackCursor = 0
    }

    func removeItem(id: UUID) {
        if let item = items.first(where: { $0.id == id }) {
            removeImagePayload(for: item)
        }
        items.removeAll { $0.id == id }
        previewImages[id] = nil
    }

    func copyToClipboard(
        item: ClipboardItem,
        shouldPaste: Bool = false,
        asPlainText: Bool = false,
        refreshHistoryEntry: Bool = true
    ) {
        if asPlainText {
            guard let plainText = plainTextRepresentation(for: item) else { return }
            copyTextToClipboard(
                plainText,
                shouldPaste: shouldPaste,
                addToHistory: true,
                sourceApplicationName: "QuickTray",
                sourceBundleIdentifier: Bundle.main.bundleIdentifier
            )
            return
        }

        pasteboard.clearContents()

        switch item.kind {
        case .text:
            if let textContent = item.textContent {
                pasteboard.setString(textContent, forType: .string)
            }
        case .image:
            if let imagePayload = item.imagePayloadData {
                pasteboard.setData(imagePayload, forType: .tiff)
            } else if let imageContent = item.imageContent {
                pasteboard.writeObjects([imageContent])
            }
        case .file:
            if let fileURL = item.fileURL {
                pasteboard.writeObjects([fileURL as NSURL])
            }
        }

        lastChangeCount = pasteboard.changeCount
        if refreshHistoryEntry {
            let activatedItem = addItem(item, refreshTimestamp: true)
            lastActivatedItemID = activatedItem.id
        }

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

    func pasteNextStackItem() {
        let now = Date()
        if shouldResetStackQueue(at: now) {
            rebuildStackQueue(referenceDate: now)
        }

        if !stackQueue.indices.contains(stackCursor) {
            rebuildStackQueue(referenceDate: now)
            if !stackQueue.indices.contains(stackCursor) {
                return
            }
        }

        let itemID = stackQueue[stackCursor]
        stackCursor += 1
        lastStackPasteDate = now

        guard let item = items.first(where: { $0.id == itemID }) else { return }
        copyToClipboard(item: item, shouldPaste: true, refreshHistoryEntry: false)
    }

    func extractTextFromMostRecentImage(shouldPaste: Bool = false) {
        let recentImage = items
            .filter { $0.kind == .image }
            .sorted { $0.timestamp > $1.timestamp }
            .first

        guard
            let recentImage,
            let image = recentImage.imageContent,
            let cgImage = cgImage(from: image)
        else {
            return
        }

        let request = VNRecognizeTextRequest { [weak self] request, _ in
            guard let self else { return }
            let observations = request.results as? [VNRecognizedTextObservation] ?? []
            let extractedLines = observations.compactMap { $0.topCandidates(1).first?.string }
            let extractedText = extractedLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !extractedText.isEmpty else { return }

            DispatchQueue.main.async {
                self.copyTextToClipboard(
                    extractedText,
                    shouldPaste: shouldPaste,
                    addToHistory: true,
                    sourceApplicationName: "QuickTray OCR",
                    sourceBundleIdentifier: Bundle.main.bundleIdentifier
                )
            }
        }
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true

        DispatchQueue.global(qos: .userInitiated).async {
            let handler = VNImageRequestHandler(cgImage: cgImage)
            try? handler.perform([request])
        }
    }

    @discardableResult
    func applyTextTransform(_ action: TextTransformAction, to item: ClipboardItem, shouldPaste: Bool = false) -> String? {
        guard let originalText = item.textContent else { return nil }

        let transformedText: String?
        switch action {
        case .formatJSON:
            transformedText = formattedJSON(from: originalText)
        case .urlEncode:
            transformedText = originalText.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)
        case .urlDecode:
            transformedText = originalText.removingPercentEncoding
        case .lowercase:
            transformedText = originalText.lowercased()
        case .uppercase:
            transformedText = originalText.uppercased()
        case .stripWhitespace:
            transformedText = originalText
                .split(whereSeparator: \.isNewline)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .joined(separator: "\n")
        }

        guard let transformedText else { return nil }
        copyTextToClipboard(
            transformedText,
            shouldPaste: shouldPaste,
            addToHistory: true,
            sourceApplicationName: "QuickTray Transform",
            sourceBundleIdentifier: Bundle.main.bundleIdentifier
        )
        return transformedText
    }

    func copyTextToClipboard(
        _ text: String,
        shouldPaste: Bool = false,
        addToHistory: Bool = true,
        sourceApplicationName: String? = nil,
        sourceBundleIdentifier: String? = nil
    ) {
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        lastChangeCount = pasteboard.changeCount

        if addToHistory {
            let item = ClipboardItem(
                text: text,
                sourceApplicationName: sourceApplicationName,
                sourceBundleIdentifier: sourceBundleIdentifier
            )
            let insertedItem = addItem(item, refreshTimestamp: true)
            lastActivatedItemID = insertedItem.id
        }

        guard shouldPaste else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) {
            Self.issuePasteShortcut()
        }
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

    @discardableResult
    private func addItem(_ item: ClipboardItem, refreshTimestamp: Bool = false) -> ClipboardItem {
        persistImagePayloadIfNeeded(for: item)

        if let existingIndex = items.firstIndex(where: { $0.matchesSamePayload(as: item) }) {
            let existingItem = items[existingIndex]
            if refreshTimestamp {
                existingItem.timestamp = Date()
            }
            if existingItem.sourceApplicationName == nil {
                existingItem.sourceApplicationName = item.sourceApplicationName
            }
            if existingItem.sourceBundleIdentifier == nil {
                existingItem.sourceBundleIdentifier = item.sourceBundleIdentifier
            }
            persistImagePayloadIfNeeded(for: existingItem)
            items = items
            loadPreview(for: existingItem)
            return existingItem
        }

        if refreshTimestamp {
            item.timestamp = Date()
        }

        items.append(item)
        trimUnpinnedItemsToLimit()
        loadPreview(for: item)
        return item
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
        if selectedCategory == .snippets {
            return false
        }
        return selectedCategory == .mixed || item.primaryCategory == selectedCategory
    }

    private func itemMatchesCurrentTypeFilter(_ item: ClipboardItem) -> Bool {
        fileTypeFilter == "all" || item.fileTypeToken == fileTypeFilter
    }

    private func itemMatchesPinnedFilter(_ item: ClipboardItem) -> Bool {
        !showPinnedOnly || item.isPinned
    }

    private func searchScore(for item: ClipboardItem, query: String) -> Double {
        let queryTokens = tokenizedWords(query)
        guard !queryTokens.isEmpty else { return 1 }

        let searchableTokens = tokenizedWords(item.searchableText)
        guard !searchableTokens.isEmpty else { return 0 }

        var tokenScores: [Double] = []
        tokenScores.reserveCapacity(queryTokens.count)

        for queryToken in queryTokens {
            let bestTokenScore = searchableTokens.reduce(0.0) { partial, candidate in
                max(partial, fuzzyTokenScore(query: queryToken, candidate: candidate))
            }
            guard bestTokenScore > 0.32 else { return 0 }
            tokenScores.append(bestTokenScore)
        }

        let avgTokenScore = tokenScores.reduce(0, +) / Double(tokenScores.count)
        let coverage = Double(tokenScores.filter { $0 > 0.55 }.count) / Double(tokenScores.count)

        let titleTokens = tokenizedWords(item.title)
        let sourceTokens = tokenizedWords(item.sourceApplicationName ?? "")
        let hasTitleHit = queryTokens.contains { queryToken in
            titleTokens.contains(where: { fuzzyTokenScore(query: queryToken, candidate: $0) > 0.8 })
        }
        let hasSourceHit = queryTokens.contains { queryToken in
            sourceTokens.contains(where: { fuzzyTokenScore(query: queryToken, candidate: $0) > 0.8 })
        }

        return avgTokenScore + coverage + (hasTitleHit ? 0.18 : 0) + (hasSourceHit ? 0.15 : 0)
    }

    private func refreshDisplayedItems() {
        if selectedCategory == .snippets {
            displayedItems = []
            return
        }

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
            removeImagePayload(for: items[index])
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
        let snapshot = items.map { $0.snapshot(omitImageData: true) }

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
            for item in items {
                persistImagePayloadIfNeeded(for: item)
            }
            enforceImageMemoryBudget()
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
            .folding(options: [.diacriticInsensitive, .widthInsensitive, .caseInsensitive], locale: .current)
            .lowercased()
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func tokenizedWords(_ value: String) -> [String] {
        normalize(value)
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map(String.init)
    }

    private func fuzzyTokenScore(query: String, candidate: String) -> Double {
        if query == candidate {
            return 1.5
        }
        if candidate.hasPrefix(query) {
            return 1.35
        }
        if candidate.contains(query) {
            return 1.2
        }

        if let subsequenceScore = subsequenceCompactness(query: query, candidate: candidate) {
            return 0.78 + (subsequenceScore * 0.35)
        }

        if let editDistance = levenshteinDistanceLimited(query, candidate, maxDistance: 2), editDistance <= 2 {
            return 0.72 - (Double(editDistance) * 0.12)
        }

        return 0
    }

    private func subsequenceCompactness(query: String, candidate: String) -> Double? {
        guard !query.isEmpty, !candidate.isEmpty else { return nil }

        let queryChars = Array(query)
        let candidateChars = Array(candidate)
        var queryIndex = 0
        var firstMatchIndex: Int?
        var lastMatchIndex: Int?

        for (index, char) in candidateChars.enumerated() where queryIndex < queryChars.count {
            guard char == queryChars[queryIndex] else { continue }
            if firstMatchIndex == nil {
                firstMatchIndex = index
            }
            lastMatchIndex = index
            queryIndex += 1
        }

        guard queryIndex == queryChars.count, let firstMatchIndex, let lastMatchIndex else {
            return nil
        }

        let span = max(1, lastMatchIndex - firstMatchIndex + 1)
        let density = Double(queryChars.count) / Double(span)
        let lengthPenalty = Double(queryChars.count) / Double(candidateChars.count)
        return (density * 0.7) + (lengthPenalty * 0.3)
    }

    private func levenshteinDistanceLimited(_ lhs: String, _ rhs: String, maxDistance: Int) -> Int? {
        let lhsChars = Array(lhs)
        let rhsChars = Array(rhs)
        guard abs(lhsChars.count - rhsChars.count) <= maxDistance else { return nil }

        var previous = Array(0...rhsChars.count)
        var current = Array(repeating: 0, count: rhsChars.count + 1)

        for (i, lhsChar) in lhsChars.enumerated() {
            current[0] = i + 1
            var minInRow = current[0]

            for (j, rhsChar) in rhsChars.enumerated() {
                let cost = lhsChar == rhsChar ? 0 : 1
                current[j + 1] = min(
                    previous[j + 1] + 1,
                    current[j] + 1,
                    previous[j] + cost
                )
                minInRow = min(minInRow, current[j + 1])
            }

            if minInRow > maxDistance {
                return nil
            }

            swap(&previous, &current)
        }

        let distance = previous[rhsChars.count]
        return distance <= maxDistance ? distance : nil
    }

    private func plainTextRepresentation(for item: ClipboardItem) -> String? {
        switch item.kind {
        case .text:
            return item.textContent
        case .image:
            return nil
        case .file:
            return item.fileURL?.path
        }
    }

    private func rebuildStackQueue(referenceDate: Date) {
        let earliestDate = referenceDate.addingTimeInterval(-Self.stackCaptureWindow)
        let candidates = items
            .filter { $0.timestamp >= earliestDate }
            .sorted { $0.timestamp < $1.timestamp }

        if !candidates.isEmpty {
            stackQueue = candidates.map(\.id)
        } else {
            stackQueue = items
                .sorted { $0.timestamp < $1.timestamp }
                .suffix(12)
                .map(\.id)
        }

        stackCursor = 0
        stackQueueRevision = historyRevision
        lastStackPasteDate = nil
    }

    private func shouldResetStackQueue(at date: Date) -> Bool {
        if stackQueue.isEmpty {
            return true
        }
        if stackQueueRevision != historyRevision {
            return true
        }
        if let lastStackPasteDate, date.timeIntervalSince(lastStackPasteDate) > Self.stackPasteTimeout {
            return true
        }
        return stackCursor >= stackQueue.count
    }

    private func persistImagePayloadIfNeeded(for item: ClipboardItem) {
        guard item.kind == .image else { return }
        guard item.imageDiskPath == nil else { return }
        guard let imagePayload = item.imagePayloadData else { return }
        guard let imageCacheDirectoryURL else { return }

        let destinationURL = imageCacheDirectoryURL.appendingPathComponent("\(item.id.uuidString).tiff")
        do {
            try imagePayload.write(to: destinationURL, options: .atomic)
            item.imageDiskPath = destinationURL.path
        } catch {
            print("Failed to cache image payload: \(error)")
        }
    }

    private func removeImagePayload(for item: ClipboardItem) {
        guard item.kind == .image else { return }
        guard let imageDiskPath = item.imageDiskPath else { return }
        try? FileManager.default.removeItem(atPath: imageDiskPath)
    }

    private func removeAllImagePayloadsFromDisk() {
        guard let imageCacheDirectoryURL else { return }
        try? FileManager.default.removeItem(at: imageCacheDirectoryURL)
        try? FileManager.default.createDirectory(at: imageCacheDirectoryURL, withIntermediateDirectories: true)
    }

    private func enforceImageMemoryBudget() {
        let imageItems = items
            .filter { $0.kind == .image }
            .sorted { $0.timestamp > $1.timestamp }

        for (index, imageItem) in imageItems.enumerated() {
            if index < Self.imageRAMItemLimit {
                if imageItem.imageData == nil, let imagePayload = imageItem.imagePayloadData {
                    imageItem.setImageDataInMemory(imagePayload)
                }
            } else {
                imageItem.setImageDataInMemory(nil)
                imageItem.clearImageCache()
            }
        }
    }

    private func formattedJSON(from input: String) -> String? {
        guard let rawData = input.data(using: .utf8) else { return nil }
        guard let object = try? JSONSerialization.jsonObject(with: rawData) else { return nil }
        guard JSONSerialization.isValidJSONObject(object) else { return nil }
        guard let prettyData = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]) else {
            return nil
        }
        return String(data: prettyData, encoding: .utf8)
    }

    private static func isSecureSourceApplication(name: String?, bundleIdentifier: String?) -> Bool {
        if let bundleIdentifier, secureBundleBlacklist.contains(bundleIdentifier) {
            return true
        }

        guard let name else { return false }
        let normalizedName = name.lowercased()
        return secureNameBlacklist.contains(where: { normalizedName.contains($0) })
    }

    private func cgImage(from image: NSImage) -> CGImage? {
        var proposedRect = CGRect(origin: .zero, size: image.size)
        if let cgImage = image.cgImage(forProposedRect: &proposedRect, context: nil, hints: nil) {
            return cgImage
        }

        guard let imageData = image.tiffRepresentation,
              let imageRep = NSBitmapImageRep(data: imageData) else {
            return nil
        }
        return imageRep.cgImage
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
