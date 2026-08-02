import SwiftUI
import AppKit
import UniformTypeIdentifiers
import QuickLookThumbnailing
import Carbon.HIToolbox
import Vision
import CryptoKit

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
        case .mixed: return "All"
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
    case list
    case tiles

    var id: String { rawValue }

    var symbolName: String {
        switch self {
        case .list: return "list.bullet"
        case .tiles: return "square.grid.2x2.fill"
        }
    }

    static func restored(from persistedValue: String?) -> ClipboardDisplayMode {
        ClipboardDisplayMode(rawValue: persistedValue ?? "") ?? .list
    }
}

enum ClipboardExclusionRules {
    static func shouldIgnore(
        sourceName: String?,
        sourceBundleIdentifier: String?,
        excludedApplications: [ExcludedApplication],
        recentlyInjectedByExcludedApplication: Bool,
        typelessFallbackActive: Bool
    ) -> Bool {
        if let sourceBundleIdentifier,
           excludedApplications.contains(where: {
               $0.bundleIdentifier.caseInsensitiveCompare(sourceBundleIdentifier) == .orderedSame
           }) {
            return true
        }

        if sourceBundleIdentifier == nil,
           let sourceName,
           excludedApplications.contains(where: {
               $0.displayName.localizedCaseInsensitiveCompare(sourceName) == .orderedSame
           }) {
            return true
        }

        return recentlyInjectedByExcludedApplication || typelessFallbackActive
    }
}

final class ClipboardItem: Identifiable, Hashable, Codable {
    let id: UUID
    let kind: ClipboardKind
    var textContent: String?
    var imageData: Data?
    var imageDiskPath: String?
    var filePath: String?
    var imageWidth: Double?
    var imageHeight: Double?
    var richTextData: Data?
    var htmlData: Data?
    var capturedTypeIdentifiers: [String]
    var sourceApplicationName: String?
    var sourceBundleIdentifier: String?
    var fileGroupID: UUID?
    var fileGroupIndex: Int?
    var timestamp: Date
    var isPinned: Bool
    var payloadFingerprint: String

    private var cachedImage: NSImage?
    private var cachedContentType: UTType?
    private var cachedTitleText: String?
    private var cachedDetailText: String?
    private var cachedSearchableText: String?

    private var cachedSearchableTokens: [String]?
    private var cachedTitleTokens: [String]?
    private var cachedSourceTokens: [String]?

    var searchableTokens: [String] {
        if let cachedSearchableTokens {
            return cachedSearchableTokens
        }
        let tokens = ClipboardManager.tokenizedWords(searchableText)
        cachedSearchableTokens = tokens
        return tokens
    }

    var titleTokens: [String] {
        if let cachedTitleTokens {
            return cachedTitleTokens
        }
        let tokens = ClipboardManager.tokenizedWords(title)
        cachedTitleTokens = tokens
        return tokens
    }

    var sourceTokens: [String] {
        if let cachedSourceTokens {
            return cachedSourceTokens
        }
        let tokens = ClipboardManager.tokenizedWords(sourceApplicationName ?? "")
        cachedSourceTokens = tokens
        return tokens
    }

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
        cacheImageMetadata(from: image)
        if imageData != nil {
            cachedImage = image
        }
        return image
    }

    var imageDimensions: NSSize? {
        guard kind == .image else { return nil }
        if let imageWidth, let imageHeight {
            return NSSize(width: imageWidth, height: imageHeight)
        }
        if let cachedImage {
            cacheImageMetadata(from: cachedImage)
            return cachedImage.size
        }
        guard let payload = imagePayloadData else { return nil }
        if let imageRep = NSBitmapImageRep(data: payload) {
            let size = imageRep.size
            imageWidth = Double(size.width)
            imageHeight = Double(size.height)
            invalidateDerivedTextCaches()
            return size
        }
        if let image = NSImage(data: payload) {
            cacheImageMetadata(from: image)
            return image.size
        }
        return nil
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
        if let cachedTitleText {
            return cachedTitleText
        }

        let resolvedTitle: String
        switch kind {
        case .text:
            let firstLine = textContent?
                .split(whereSeparator: \.isNewline)
                .first?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            resolvedTitle = firstLine.isEmpty ? "Untitled text clip" : String(firstLine.prefix(120))
        case .image:
            resolvedTitle = "Image clip"
        case .file:
            resolvedTitle = fileURL?.lastPathComponent ?? "Missing file"
        }

        cachedTitleText = resolvedTitle
        return resolvedTitle
    }

    var detailText: String {
        if let cachedDetailText {
            return cachedDetailText
        }

        let resolvedDetail: String
        switch kind {
        case .text:
            resolvedDetail = ""
        case .image:
            let size = imageDimensions ?? .zero
            let width = Int(size.width)
            let height = Int(size.height)
            resolvedDetail = "\(width) × \(height)"
        case .file:
            if let fileURL {
                resolvedDetail = fileURL.path
            } else {
                resolvedDetail = "Original file is unavailable"
            }
        }

        cachedDetailText = resolvedDetail
        return resolvedDetail
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
        if let cachedSearchableText {
            return cachedSearchableText
        }

        let sourceText = sourceApplicationName ?? ""
        let resolvedSearchableText: String
        switch kind {
        case .text:
            resolvedSearchableText = [title, textContent ?? "", sourceText].joined(separator: " ")
        case .image:
            resolvedSearchableText = [title, detailText, fileTypeToken, sourceText].joined(separator: " ")
        case .file:
            let localizedDescription = contentType?.localizedDescription ?? ""
            resolvedSearchableText = [title, detailText, fileTypeToken, localizedDescription, sourceText].joined(separator: " ")
        }

        cachedSearchableText = resolvedSearchableText
        return resolvedSearchableText
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
        case imageWidth
        case imageHeight
        case richTextData
        case htmlData
        case capturedTypeIdentifiers
        case sourceApplicationName
        case sourceBundleIdentifier
        case fileGroupID
        case fileGroupIndex
        case timestamp
        case isPinned
        case payloadFingerprint
    }

    init(
        text: String,
        richTextData: Data? = nil,
        htmlData: Data? = nil,
        capturedTypeIdentifiers: [String] = [],
        sourceApplicationName: String? = nil,
        sourceBundleIdentifier: String? = nil
    ) {
        id = UUID()
        kind = .text
        textContent = text
        imageData = nil
        imageDiskPath = nil
        filePath = nil
        imageWidth = nil
        imageHeight = nil
        self.richTextData = richTextData
        self.htmlData = htmlData
        self.capturedTypeIdentifiers = capturedTypeIdentifiers
        self.sourceApplicationName = sourceApplicationName
        self.sourceBundleIdentifier = sourceBundleIdentifier
        fileGroupID = nil
        fileGroupIndex = nil
        timestamp = Date()
        isPinned = false
        payloadFingerprint = Self.fingerprint(forText: text)
    }

    private init(copying item: ClipboardItem, omitImageData: Bool = false) {
        id = item.id
        kind = item.kind
        textContent = item.textContent
        imageData = omitImageData && item.kind == .image ? nil : item.imageData
        imageDiskPath = item.imageDiskPath
        filePath = item.filePath
        imageWidth = item.imageWidth
        imageHeight = item.imageHeight
        richTextData = item.richTextData
        htmlData = item.htmlData
        capturedTypeIdentifiers = item.capturedTypeIdentifiers
        sourceApplicationName = item.sourceApplicationName
        sourceBundleIdentifier = item.sourceBundleIdentifier
        fileGroupID = item.fileGroupID
        fileGroupIndex = item.fileGroupIndex
        timestamp = item.timestamp
        isPinned = item.isPinned
        payloadFingerprint = item.payloadFingerprint
        cachedImage = nil
        cachedContentType = nil
        cachedTitleText = nil
        cachedDetailText = nil
        cachedSearchableText = nil
    }

    required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        kind = try container.decode(ClipboardKind.self, forKey: .kind)
        textContent = try container.decodeIfPresent(String.self, forKey: .textContent)
        imageData = try container.decodeIfPresent(Data.self, forKey: .imageData)
        imageDiskPath = try container.decodeIfPresent(String.self, forKey: .imageDiskPath)
        filePath = try container.decodeIfPresent(String.self, forKey: .filePath)
        imageWidth = try container.decodeIfPresent(Double.self, forKey: .imageWidth)
        imageHeight = try container.decodeIfPresent(Double.self, forKey: .imageHeight)
        richTextData = try container.decodeIfPresent(Data.self, forKey: .richTextData)
        htmlData = try container.decodeIfPresent(Data.self, forKey: .htmlData)
        capturedTypeIdentifiers = try container.decodeIfPresent([String].self, forKey: .capturedTypeIdentifiers) ?? []
        sourceApplicationName = try container.decodeIfPresent(String.self, forKey: .sourceApplicationName)
        sourceBundleIdentifier = try container.decodeIfPresent(String.self, forKey: .sourceBundleIdentifier)
        fileGroupID = try container.decodeIfPresent(UUID.self, forKey: .fileGroupID)
        fileGroupIndex = try container.decodeIfPresent(Int.self, forKey: .fileGroupIndex)
        timestamp = try container.decode(Date.self, forKey: .timestamp)
        isPinned = try container.decode(Bool.self, forKey: .isPinned)
        payloadFingerprint = try container.decodeIfPresent(String.self, forKey: .payloadFingerprint) ?? Self.fallbackFingerprint(
            kind: kind,
            textContent: textContent,
            imageData: imageData,
            imageDiskPath: imageDiskPath,
            filePath: filePath
        )
        cachedImage = nil
        cachedContentType = nil
        cachedTitleText = nil
        cachedDetailText = nil
        cachedSearchableText = nil
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(kind, forKey: .kind)
        try container.encodeIfPresent(textContent, forKey: .textContent)
        try container.encodeIfPresent(imageData, forKey: .imageData)
        try container.encodeIfPresent(imageDiskPath, forKey: .imageDiskPath)
        try container.encodeIfPresent(filePath, forKey: .filePath)
        try container.encodeIfPresent(imageWidth, forKey: .imageWidth)
        try container.encodeIfPresent(imageHeight, forKey: .imageHeight)
        try container.encodeIfPresent(richTextData, forKey: .richTextData)
        try container.encodeIfPresent(htmlData, forKey: .htmlData)
        try container.encode(capturedTypeIdentifiers, forKey: .capturedTypeIdentifiers)
        try container.encodeIfPresent(sourceApplicationName, forKey: .sourceApplicationName)
        try container.encodeIfPresent(sourceBundleIdentifier, forKey: .sourceBundleIdentifier)
        try container.encodeIfPresent(fileGroupID, forKey: .fileGroupID)
        try container.encodeIfPresent(fileGroupIndex, forKey: .fileGroupIndex)
        try container.encode(timestamp, forKey: .timestamp)
        try container.encode(isPinned, forKey: .isPinned)
        try container.encode(payloadFingerprint, forKey: .payloadFingerprint)
    }

    init(
        imageData: Data,
        capturedTypeIdentifiers: [String] = [],
        sourceApplicationName: String? = nil,
        sourceBundleIdentifier: String? = nil
    ) {
        id = UUID()
        kind = .image
        textContent = nil
        self.imageData = imageData
        imageDiskPath = nil
        filePath = nil
        let imageSize = Self.imageSize(from: imageData)
        imageWidth = imageSize.map { Double($0.width) }
        imageHeight = imageSize.map { Double($0.height) }
        richTextData = nil
        htmlData = nil
        self.capturedTypeIdentifiers = capturedTypeIdentifiers
        self.sourceApplicationName = sourceApplicationName
        self.sourceBundleIdentifier = sourceBundleIdentifier
        fileGroupID = nil
        fileGroupIndex = nil
        timestamp = Date()
        isPinned = false
        cachedImage = nil
        payloadFingerprint = Self.fingerprint(forImageData: imageData)
    }

    init(
        fileURL: URL,
        fileGroupID: UUID? = nil,
        fileGroupIndex: Int? = nil,
        timestamp: Date = Date(),
        capturedTypeIdentifiers: [String] = [],
        sourceApplicationName: String? = nil,
        sourceBundleIdentifier: String? = nil
    ) {
        id = UUID()
        kind = .file
        textContent = nil
        imageData = nil
        imageDiskPath = nil
        filePath = fileURL.path
        imageWidth = nil
        imageHeight = nil
        richTextData = nil
        htmlData = nil
        self.capturedTypeIdentifiers = capturedTypeIdentifiers
        self.sourceApplicationName = sourceApplicationName
        self.sourceBundleIdentifier = sourceBundleIdentifier
        self.fileGroupID = fileGroupID
        self.fileGroupIndex = fileGroupIndex
        self.timestamp = timestamp
        isPinned = false
        payloadFingerprint = Self.fingerprint(forFileURL: fileURL)
    }

    func dragItemProvider() -> NSItemProvider? {
        switch kind {
        case .text:
            guard let textContent else { return nil }
            return NSItemProvider(object: textContent as NSString)
        case .image:
            let provider = NSItemProvider()
            let typeIdentifier = preferredImageDragTypeIdentifier
            let imageData = self.imageData
            let imageDiskPath = self.imageDiskPath
            provider.registerDataRepresentation(
                forTypeIdentifier: typeIdentifier,
                visibility: .all
            ) { completion in
                if let imageData {
                    completion(imageData, nil)
                    return nil
                }

                guard let imageDiskPath else {
                    completion(nil, nil)
                    return nil
                }

                DispatchQueue.global(qos: .userInitiated).async {
                    let data = try? Data(contentsOf: URL(fileURLWithPath: imageDiskPath))
                    completion(data, nil)
                }
                return nil
            }
            return provider
        case .file:
            guard let fileURL else { return nil }
            return NSItemProvider(contentsOf: fileURL)
        }
    }

    func matchesSamePayload(as other: ClipboardItem) -> Bool {
        guard kind == other.kind else { return false }
        return payloadFingerprint == other.payloadFingerprint
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

    private func cacheImageMetadata(from image: NSImage?) {
        guard let image else { return }
        let size = image.size
        imageWidth = Double(size.width)
        imageHeight = Double(size.height)
        invalidateDerivedTextCaches()
    }

    fileprivate func invalidateDerivedTextCaches() {
        cachedTitleText = nil
        cachedDetailText = nil
        cachedSearchableText = nil
        cachedSearchableTokens = nil
        cachedTitleTokens = nil
        cachedSourceTokens = nil
    }

    private static func imageSize(from data: Data) -> NSSize? {
        if let imageRep = NSBitmapImageRep(data: data) {
            return imageRep.size
        }
        return NSImage(data: data)?.size
    }

    private var preferredImageDragTypeIdentifier: String {
        capturedTypeIdentifiers
            .compactMap(UTType.init)
            .first(where: { $0.conforms(to: .image) })?
            .identifier ?? UTType.tiff.identifier
    }

    func snapshot(omitImageData: Bool = false) -> ClipboardItem {
        ClipboardItem(copying: self, omitImageData: omitImageData)
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: ClipboardItem, rhs: ClipboardItem) -> Bool {
        lhs.id == rhs.id
    }

    static func fingerprint(forText text: String) -> String {
        let length = text.count
        if length < 2000 {
            return "text:\(length):\(sha256Hex(Data(text.utf8)))"
        } else {
            let prefix = text.prefix(1000)
            let suffix = text.suffix(1000)
            return "text:\(length):\(sha256Hex(Data((String(prefix) + String(suffix)).utf8)))"
        }
    }

    static func fingerprint(forImageData data: Data) -> String {
        let length = data.count
        if length < 4000 {
            return "image:\(length):\(sha256Hex(data))"
        } else {
            let prefix = data.prefix(2000)
            let suffix = data.suffix(2000)
            return "image:\(length):\(sha256Hex(prefix + suffix))"
        }
    }

    static func fingerprint(forFileURL url: URL) -> String {
        let path = url.path
        let length = path.count
        if length < 1000 {
            return "file:\(length):\(sha256Hex(Data(path.utf8)))"
        } else {
            let prefix = path.prefix(500)
            let suffix = path.suffix(500)
            return "file:\(length):\(sha256Hex(Data((String(prefix) + String(suffix)).utf8)))"
        }
    }

    static func fallbackFingerprint(
        kind: ClipboardKind,
        textContent: String?,
        imageData: Data?,
        imageDiskPath: String?,
        filePath: String?
    ) -> String {
        switch kind {
        case .text:
            return fingerprint(forText: textContent ?? "")
        case .image:
            if let imageData {
                return fingerprint(forImageData: imageData)
            }
            if let imageDiskPath, let data = try? Data(contentsOf: URL(fileURLWithPath: imageDiskPath)) {
                return fingerprint(forImageData: data)
            }
            return "image:\(imageDiskPath ?? "")"
        case .file:
            return "file:\(filePath ?? "")"
        }
    }

    static func sha256Hex(_ data: Data) -> String {
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}

private enum PreviewFactory {
    static func previewImage(for item: ClipboardItem, completion: @escaping (NSImage?) -> Void) {
        guard let fileURL = item.fileURL else {
            completion(nil)
            return
        }

        let scale = NSScreen.main?.backingScaleFactor ?? 2
        let request = QLThumbnailGenerator.Request(
            fileAt: fileURL,
            size: CGSize(width: 560, height: 420),
            scale: scale,
            representationTypes: .all
        )
        QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { representation, _ in
            guard let cgImage = representation?.cgImage else {
                completion(fallbackApplicationIcon(for: fileURL))
                return
            }

            let image = NSImage(
                cgImage: cgImage,
                size: NSSize(width: cgImage.width, height: cgImage.height)
            )
            image.size = NSSize(width: 320, height: 200)
            completion(image)
        }
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
    private static let preferredPasteModeKey = "preferredPasteMode"
    private static let selectedCategoryKey = "selectedCategory"
    private static let fileTypeFilterKey = "fileTypeFilter"
    private static let showPinnedOnlyKey = "showPinnedOnly"
    private static let displayModeKey = "displayMode"
    private static let defaultUnpinnedRetentionLimit = 30
    private static let minUnpinnedRetentionLimit = 1
    private static let maxUnpinnedRetentionLimit = 500
    private static let imageRAMItemLimit = 20
    private static let stackPasteTimeout: TimeInterval = 45
    private static let stackCaptureWindow: TimeInterval = 15 * 60

    @Published var unpinnedRetentionLimit: Int {
        didSet {
            persistAndApplyRetentionLimit()
        }
    }

    @Published var items: [ClipboardItem] = [] {
        didSet {
            guard !suppressItemSideEffects else { return }
            historyRevision += 1
            scheduleSaveItems()
            scheduleDisplayedItemsRefresh()
        }
    }

    @Published var searchQuery = "" {
        didSet {
            scheduleDisplayedItemsRefresh()
        }
    }

    @Published var selectedCategory: ClipboardCategory {
        didSet {
            UserDefaults.standard.set(selectedCategory.rawValue, forKey: Self.selectedCategoryKey)
            if !availableFileTypeFilters.contains(fileTypeFilter) {
                fileTypeFilter = "all"
            }
            scheduleDisplayedItemsRefresh()
        }
    }

    @Published var fileTypeFilter: String {
        didSet {
            UserDefaults.standard.set(fileTypeFilter, forKey: Self.fileTypeFilterKey)
            scheduleDisplayedItemsRefresh()
        }
    }

    @Published var showPinnedOnly: Bool {
        didSet {
            UserDefaults.standard.set(showPinnedOnly, forKey: Self.showPinnedOnlyKey)
            scheduleDisplayedItemsRefresh()
        }
    }

    @Published var isMonitoringEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isMonitoringEnabled, forKey: Self.monitoringEnabledKey)
            isMonitoringEnabled ? startMonitoring() : stopMonitoring()
        }
    }

    @Published var preferredPasteMode: ClipboardPasteMode {
        didSet {
            UserDefaults.standard.set(preferredPasteMode.rawValue, forKey: Self.preferredPasteModeKey)
        }
    }

    @Published var displayMode: ClipboardDisplayMode {
        didSet {
            UserDefaults.standard.set(displayMode.rawValue, forKey: Self.displayModeKey)
        }
    }
    @Published private(set) var displayedItems: [ClipboardItem] = []
    @Published private(set) var displayRevision = 0
    @Published private(set) var previewImages: [UUID: NSImage] = [:]

    private let pasteboard = NSPasteboard.general
    private let previewQueue = DispatchQueue(label: "com.gemini.quicktray.previews", qos: .userInitiated)
    private let persistenceQueue = DispatchQueue(label: "com.gemini.quicktray.persistence", qos: .utility)
    private var timer: Timer?
    private var lastChangeCount: Int
    private var historyRevision = 0
    private var suppressItemSideEffects = false
    private var lastActivatedItemID: UUID?
    private var stackQueue: [UUID] = []
    private var usesCustomStackQueue = false
    private var stackCursor = 0
    private var stackQueueRevision = -1
    private var lastStackPasteDate: Date?
    private var pendingPasteTargetProcessIdentifier: pid_t?
    private var lastPasteTargetProcessIdentifier: pid_t?
    private var previewLoadsInFlight: Set<UUID> = []
    private var lastWrittenPasteboardSignature: String?
    private var displayedItemsRefreshWorkItem: DispatchWorkItem?
    private var saveItemsWorkItem: DispatchWorkItem?
    private var saveItemsGeneration = 0
    private var clipboardMonitoringSuspendedUntil: Date?
    private var excludedAppPasteEventTap: CFMachPort?
    private var excludedAppPasteEventSource: CFRunLoopSource?
    private var lastPasteShortcutDate: Date?
    private var lastExcludedAppPasteShortcutDate: Date?
    private static let postPasteMonitoringSuspension: TimeInterval = 0.5
    private static let excludedAppPasteIgnoreWindow: TimeInterval = 2.0
    private static let typelessPasteFallbackIgnoreWindow: TimeInterval = 0.9
    private static let parrotGeneratedEventMarker: Int64 = 0x5041_5252_4F54

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
        selectedCategory = ClipboardCategory(
            rawValue: UserDefaults.standard.string(forKey: Self.selectedCategoryKey) ?? ""
        ) ?? .mixed
        fileTypeFilter = UserDefaults.standard.string(forKey: Self.fileTypeFilterKey) ?? "all"
        showPinnedOnly = UserDefaults.standard.object(forKey: Self.showPinnedOnlyKey) as? Bool ?? false
        isMonitoringEnabled = UserDefaults.standard.object(forKey: Self.monitoringEnabledKey) as? Bool ?? true
        preferredPasteMode = ClipboardPasteMode(rawValue: UserDefaults.standard.string(forKey: Self.preferredPasteModeKey) ?? "") ?? .rich
        displayMode = ClipboardDisplayMode.restored(
            from: UserDefaults.standard.string(forKey: Self.displayModeKey)
        )
        lastChangeCount = pasteboard.changeCount

        loadItems()
        trimUnpinnedItemsToLimit()
        if !availableFileTypeFilters.contains(fileTypeFilter) {
            fileTypeFilter = "all"
        }
        loadInitialPreviews()
        refreshDisplayedItemsNow()
        installExcludedAppPasteEventMonitor()
        if isMonitoringEnabled {
            startMonitoring()
        }
    }

    private func scheduleDisplayedItemsRefresh(delay: TimeInterval = 0.04) {
        displayedItemsRefreshWorkItem?.cancel()

        let workItem = DispatchWorkItem { [weak self] in
            self?.refreshDisplayedItemsNow()
        }
        displayedItemsRefreshWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }

    private func scheduleSaveItems() {
        guard let persistenceURL else { return }

        saveItemsWorkItem?.cancel()
        let snapshot = items.map { $0.snapshot(omitImageData: true) }
        saveItemsGeneration += 1
        let generation = saveItemsGeneration

        let workItem = DispatchWorkItem { [weak self, snapshot, persistenceURL] in
            guard let self else { return }
            guard generation == self.saveItemsGeneration else { return }
            do {
                let data = try JSONEncoder().encode(snapshot)
                try data.write(to: persistenceURL, options: .atomic)
            } catch {
                print("Failed to save clipboard history: \(error)")
            }
        }

        saveItemsWorkItem = workItem
        persistenceQueue.asyncAfter(deadline: .now() + 0.15, execute: workItem)
    }

    func flushPendingSave() {
        guard let persistenceURL else { return }

        saveItemsWorkItem?.cancel()
        saveItemsWorkItem = nil
        let snapshot = items.map { $0.snapshot(omitImageData: true) }
        saveItemsGeneration += 1

        persistenceQueue.sync {
            do {
                let data = try JSONEncoder().encode(snapshot)
                try data.write(to: persistenceURL, options: .atomic)
            } catch {
                print("Failed to save clipboard history: \(error)")
            }
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

    func capturePasteTargetApplication(_ application: NSRunningApplication? = NSWorkspace.shared.frontmostApplication) {
        let currentProcessIdentifier = ProcessInfo.processInfo.processIdentifier

        if let application, application.processIdentifier != currentProcessIdentifier {
            rememberPasteTarget(application)
            return
        }

        if let fallbackApplication = Self.visibleApplicationBelowQuickTray(excluding: currentProcessIdentifier) {
            rememberPasteTarget(fallbackApplication)
        }
    }

    var pasteStackItems: [ClipboardItem] {
        stackQueue.compactMap { itemID in
            items.first(where: { $0.id == itemID })
        }
    }

    var availableFileTypeFilters: [String] {
        let filteredItems = items.filter { item in
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
        if let suspendedUntil = clipboardMonitoringSuspendedUntil, suspendedUntil > Date() {
            return
        }

        let sourceApplication = NSWorkspace.shared.frontmostApplication
        let sourceName = sourceApplication?.localizedName
        let sourceBundleIdentifier = sourceApplication?.bundleIdentifier

        guard pasteboard.changeCount != lastChangeCount else { return }
        lastChangeCount = pasteboard.changeCount
        lastWrittenPasteboardSignature = nil

        let capturedTypes = (pasteboard.types ?? []).map(\.rawValue)
        guard !shouldIgnoreClipboardChange(sourceName: sourceName, sourceBundleIdentifier: sourceBundleIdentifier) else {
            return
        }

        let fileOptions: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true]
        if let fileURLs = pasteboard.readObjects(forClasses: [NSURL.self], options: fileOptions) as? [URL],
           !fileURLs.isEmpty {
            let captureDate = Date()
            let groupID = fileURLs.count > 1 ? UUID() : nil
            let capturedItems = fileURLs.enumerated().map { index, fileURL in
                ClipboardItem(
                    fileURL: fileURL,
                    fileGroupID: groupID,
                    fileGroupIndex: groupID == nil ? nil : index,
                    timestamp: captureDate.addingTimeInterval(-Double(index) * 0.000_001),
                    capturedTypeIdentifiers: capturedTypes,
                    sourceApplicationName: sourceName,
                    sourceBundleIdentifier: sourceBundleIdentifier
                )
            }
            addItems(capturedItems, refreshTimestamps: true)
            return
        }

        let imageData = pasteboard.data(forType: .tiff) ?? NSImage(pasteboard: pasteboard)?.tiffRepresentation
        if let imageData {
            addItem(
                ClipboardItem(
                    imageData: imageData,
                    capturedTypeIdentifiers: capturedTypes,
                    sourceApplicationName: sourceName,
                    sourceBundleIdentifier: sourceBundleIdentifier
                )
            )
            return
        }

        let rtfData = pasteboard.data(forType: .rtf)
        let htmlData = pasteboard.data(forType: .html)
        let plainString = pasteboard.string(forType: .string)
            ?? Self.extractStringFromRichPayload(rtfData: rtfData, htmlData: htmlData)

        if let string = plainString {
            addItem(
                ClipboardItem(
                    text: string,
                    richTextData: rtfData,
                    htmlData: htmlData,
                    capturedTypeIdentifiers: capturedTypes,
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

    func setPinned(_ isPinned: Bool, for itemIDs: Set<UUID>) {
        guard !itemIDs.isEmpty else { return }
        var changed = false
        for item in items where itemIDs.contains(item.id) && item.isPinned != isPinned {
            item.isPinned = isPinned
            changed = true
        }
        if changed {
            items = items
        }
    }

    private func shouldIgnoreClipboardChange(sourceName: String?, sourceBundleIdentifier: String?) -> Bool {
        let settings = AppSettings.shared
        let now = Date()
        let recentlyInjectedByExcludedApplication = lastExcludedAppPasteShortcutDate.map {
            now.timeIntervalSince($0) <= Self.excludedAppPasteIgnoreWindow
        } ?? false
        let typelessFallbackActive = settings.isApplicationExcluded(
            bundleIdentifier: AppSettings.typelessBundleIdentifier
        ) && Self.isTypelessRunning() && (lastPasteShortcutDate.map {
            now.timeIntervalSince($0) <= Self.typelessPasteFallbackIgnoreWindow
        } ?? false)

        return ClipboardExclusionRules.shouldIgnore(
            sourceName: sourceName,
            sourceBundleIdentifier: sourceBundleIdentifier,
            excludedApplications: settings.excludedApplications,
            recentlyInjectedByExcludedApplication: recentlyInjectedByExcludedApplication,
            typelessFallbackActive: typelessFallbackActive
        )
    }

    func clearAll() {
        removeAllImagePayloadsFromDisk()
        items.removeAll()
        previewImages.removeAll()
        stackQueue = []
        usesCustomStackQueue = false
        stackCursor = 0
        previewLoadsInFlight.removeAll()
    }

    func removeItem(id: UUID) {
        removeItems(ids: [id])
    }

    func removeItems(ids itemIDs: Set<UUID>) {
        guard !itemIDs.isEmpty else { return }
        for item in items where itemIDs.contains(item.id) {
            removeImagePayload(for: item)
        }
        items.removeAll { itemIDs.contains($0.id) }
        stackQueue.removeAll { itemIDs.contains($0) }
        stackCursor = min(stackCursor, max(stackQueue.count - 1, 0))
        for itemID in itemIDs {
            previewImages[itemID] = nil
            previewLoadsInFlight.remove(itemID)
        }
    }

    func copyFileGroupToClipboard(_ groupItems: [ClipboardItem], shouldPaste: Bool) {
        let orderedItems = groupItems
            .filter { $0.kind == .file }
            .sorted { ($0.fileGroupIndex ?? 0) < ($1.fileGroupIndex ?? 0) }
        let fileURLs = orderedItems.compactMap(\.fileURL)
        guard fileURLs.count > 1 else {
            if let item = orderedItems.first {
                copyToClipboard(item: item, shouldPaste: shouldPaste, refreshHistoryEntry: false)
            }
            return
        }

        let signature = "file-group:" + orderedItems.map(\.payloadFingerprint).joined(separator: "|")
        if !pasteboardAlreadyContains(signature: signature) {
            pasteboard.clearContents()
            guard pasteboard.writeObjects(fileURLs.map { $0 as NSURL }) else { return }
            lastChangeCount = pasteboard.changeCount
            lastWrittenPasteboardSignature = signature
        }

        if shouldPaste {
            schedulePasteShortcut()
        }
    }

    func copyToClipboard(
        item: ClipboardItem,
        shouldPaste: Bool = false,
        asPlainText: Bool = false,
        pasteMode: ClipboardPasteMode? = nil,
        refreshHistoryEntry: Bool = false
    ) {
        if asPlainText {
            guard let plainText = plainTextRepresentation(for: item) else { return }
            copyTextToClipboard(
                plainText,
                shouldPaste: shouldPaste,
                addToHistory: refreshHistoryEntry,
                sourceApplicationName: "QuickTray",
                sourceBundleIdentifier: Bundle.main.bundleIdentifier
            )
            return
        }

        let effectivePasteMode = pasteMode ?? preferredPasteMode
        let signature = pasteboardSignature(for: item, pasteMode: effectivePasteMode)

        switch item.kind {
        case .text:
            writeStandardItemToPasteboard(
                item,
                signature: signature,
                shouldPaste: shouldPaste,
                refreshHistoryEntry: refreshHistoryEntry,
                pasteMode: effectivePasteMode
            )
        case .file:
            writeStandardItemToPasteboard(
                item,
                signature: signature,
                shouldPaste: shouldPaste,
                refreshHistoryEntry: refreshHistoryEntry,
                pasteMode: effectivePasteMode
            )
        case .image:
            writeImageToPasteboard(
                item: item,
                signature: signature,
                shouldPaste: shouldPaste,
                refreshHistoryEntry: refreshHistoryEntry
            )
        }
    }

    func quickPasteRecent(offsetFromLatest offset: Int) {
        let recentItems = items.sorted { $0.timestamp > $1.timestamp }
        guard recentItems.indices.contains(offset) else { return }
        copyToClipboard(item: recentItems[offset], shouldPaste: true, refreshHistoryEntry: false)
    }

    func enqueueForPasteStack(_ item: ClipboardItem) {
        guard !stackQueue.contains(item.id) else { return }
        usesCustomStackQueue = true
        stackQueue.append(item.id)
        stackQueueRevision = historyRevision
    }

    func createPasteStack(from items: [ClipboardItem]) {
        let orderedIDs = items.map(\.id)
        guard !orderedIDs.isEmpty else { return }
        stackQueue = orderedIDs
        usesCustomStackQueue = true
        stackCursor = 0
        stackQueueRevision = historyRevision
        lastStackPasteDate = nil
    }

    func clearPasteStack() {
        stackQueue = []
        usesCustomStackQueue = false
        stackCursor = 0
        stackQueueRevision = historyRevision
        lastStackPasteDate = nil
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

        guard let recentImage else { return }
        extractText(from: recentImage, shouldPaste: shouldPaste)
    }

    func extractText(from item: ClipboardItem, shouldPaste: Bool = false) {
        guard item.kind == .image,
              let image = item.imageContent,
              let cgImage = cgImage(from: image) else { return }

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
        let signature = pasteboardSignature(forText: text)
        if !pasteboardAlreadyContains(signature: signature) {
            pasteboard.clearContents()
            pasteboard.setString(text, forType: .string)
            lastChangeCount = pasteboard.changeCount
            lastWrittenPasteboardSignature = signature
        }

        if addToHistory {
            let item = ClipboardItem(
                text: text,
                capturedTypeIdentifiers: [NSPasteboard.PasteboardType.string.rawValue],
                sourceApplicationName: sourceApplicationName,
                sourceBundleIdentifier: sourceBundleIdentifier
            )
            let insertedItem = addItem(item, refreshTimestamp: true)
            lastActivatedItemID = insertedItem.id
        }

        guard shouldPaste else { return }
        schedulePasteShortcut()
    }

    func toggleMonitoring() {
        isMonitoringEnabled.toggle()
    }

    func updateText(for id: UUID, newValue: String) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].textContent = newValue
        items[index].richTextData = nil
        items[index].htmlData = nil
        items[index].capturedTypeIdentifiers = [NSPasteboard.PasteboardType.string.rawValue]
        items[index].timestamp = Date()
        items[index].payloadFingerprint = ClipboardItem.fingerprint(forText: newValue)
        items[index].invalidateDerivedTextCaches()
        clearPasteboardSignatureIfNeeded(for: id)
        items = items
    }

    func copyPathToClipboard(item: ClipboardItem) {
        guard let fileURL = item.fileURL else { return }
        pasteboard.clearContents()
        pasteboard.setString(fileURL.path, forType: .string)
        lastChangeCount = pasteboard.changeCount
    }

    func previewImage(for item: ClipboardItem) -> NSImage? {
        if let image = previewImages[item.id] {
            return image
        }

        switch item.kind {
        case .text:
            return nil
        case .image:
            if let inMemoryImage = item.imageData != nil ? item.imageContent : nil {
                return inMemoryImage
            }
            loadPreview(for: item)
            return nil
        case .file:
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
        if let existingIndex = items.firstIndex(where: { $0.matchesSamePayload(as: item) }) {
            let existingItem = items[existingIndex]
            if refreshTimestamp {
                existingItem.timestamp = item.timestamp
                if item.kind == .file {
                    existingItem.fileGroupID = item.fileGroupID
                    existingItem.fileGroupIndex = item.fileGroupIndex
                }
            }
            if existingItem.sourceApplicationName == nil {
                existingItem.sourceApplicationName = item.sourceApplicationName
            }
            if existingItem.sourceBundleIdentifier == nil {
                existingItem.sourceBundleIdentifier = item.sourceBundleIdentifier
            }
            if existingItem.richTextData == nil {
                existingItem.richTextData = item.richTextData
            }
            if existingItem.htmlData == nil {
                existingItem.htmlData = item.htmlData
            }
            if existingItem.capturedTypeIdentifiers.isEmpty {
                existingItem.capturedTypeIdentifiers = item.capturedTypeIdentifiers
            }
            existingItem.invalidateDerivedTextCaches()
            persistImagePayloadIfNeeded(for: existingItem)
            items = items
            enforceImageMemoryBudget()
            loadPreview(for: existingItem)
            return existingItem
        }

        if refreshTimestamp {
            item.timestamp = Date()
        }

        persistImagePayloadIfNeeded(for: item)
        items.append(item)
        trimUnpinnedItemsToLimit()
        enforceImageMemoryBudget()
        loadPreview(for: item)
        return item
    }

    private func addItems(_ capturedItems: [ClipboardItem], refreshTimestamps: Bool) {
        guard capturedItems.count > 1 else {
            if let item = capturedItems.first {
                addItem(item, refreshTimestamp: refreshTimestamps)
            }
            return
        }

        let sideEffectsWereSuppressed = suppressItemSideEffects
        suppressItemSideEffects = true
        for item in capturedItems {
            addItem(item, refreshTimestamp: refreshTimestamps)
        }
        suppressItemSideEffects = sideEffectsWereSuppressed

        guard !sideEffectsWereSuppressed else { return }
        historyRevision += 1
        scheduleSaveItems()
        scheduleDisplayedItemsRefresh()
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

    private func searchScore(for item: ClipboardItem, queryTokens: [String]) -> Double {
        guard !queryTokens.isEmpty else { return 1 }

        let searchableTokens = item.searchableTokens
        guard !searchableTokens.isEmpty else { return 0 }

        var totalScore = 0.0
        var strongMatchCount = 0

        for queryToken in queryTokens {
            var bestTokenScore = 0.0
            for candidate in searchableTokens {
                bestTokenScore = max(
                    bestTokenScore,
                    fuzzyTokenScore(query: queryToken, candidate: candidate)
                )
                if bestTokenScore >= 1.5 {
                    break
                }
            }
            guard bestTokenScore > 0.32 else { return 0 }
            totalScore += bestTokenScore
            if bestTokenScore > 0.55 {
                strongMatchCount += 1
            }
        }

        let avgTokenScore = totalScore / Double(queryTokens.count)
        let coverage = Double(strongMatchCount) / Double(queryTokens.count)

        let titleTokens = item.titleTokens
        let sourceTokens = item.sourceTokens
        let hasTitleHit = queryTokens.contains { queryToken in
            titleTokens.contains(where: { fuzzyTokenScore(query: queryToken, candidate: $0) > 0.8 })
        }
        let hasSourceHit = queryTokens.contains { queryToken in
            sourceTokens.contains(where: { fuzzyTokenScore(query: queryToken, candidate: $0) > 0.8 })
        }

        return avgTokenScore + coverage + (hasTitleHit ? 0.18 : 0) + (hasSourceHit ? 0.15 : 0)
    }

    private func refreshDisplayedItemsNow() {
        if selectedCategory == .snippets {
            displayedItems = []
            displayRevision += 1
            return
        }

        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        let filteredItems = sortedItems().filter { item in
            itemMatchesCurrentCategory(item)
                && itemMatchesCurrentTypeFilter(item)
                && itemMatchesPinnedFilter(item)
        }

        guard !query.isEmpty else {
            displayedItems = filteredItems
            displayRevision += 1
            return
        }

        let queryTokens = Self.tokenizedWords(query)
        guard !queryTokens.isEmpty else {
            displayedItems = filteredItems
            displayRevision += 1
            return
        }

        displayedItems = filteredItems
            .compactMap { item -> (ClipboardItem, Double)? in
                let score = searchScore(for: item, queryTokens: queryTokens)
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
        displayRevision += 1
    }

    private func trimUnpinnedItemsToLimit() {
        let unpinnedCount = items.filter { !$0.isPinned }.count
        let excessCount = unpinnedCount - unpinnedRetentionLimit
        guard excessCount > 0 else { return }

        var remainingToRemove = excessCount
        let sortedIndexes = items.enumerated().sorted { $0.element.timestamp < $1.element.timestamp }
        var indexesToRemove: [Int] = []
        indexesToRemove.reserveCapacity(excessCount)

        for (index, item) in sortedIndexes where !item.isPinned && remainingToRemove > 0 {
            indexesToRemove.append(index)
            remainingToRemove -= 1
        }

        guard !indexesToRemove.isEmpty else { return }

        let removalSet = Set(indexesToRemove)
        let removedItems = items.enumerated()
            .filter { removalSet.contains($0.offset) }
            .map(\.element)

        for item in removedItems {
            removeImagePayload(for: item)
            previewImages[item.id] = nil
            previewLoadsInFlight.remove(item.id)
        }

        items = items.enumerated()
            .compactMap { removalSet.contains($0.offset) ? nil : $0.element }
    }

    private func loadInitialPreviews() {
        for item in sortedItems().prefix(12) where item.kind != .text {
            loadPreview(for: item)
        }
    }

    private func loadPreview(for item: ClipboardItem) {
        guard item.kind != .text else { return }
        guard previewImages[item.id] == nil else { return }
        guard !previewLoadsInFlight.contains(item.id) else { return }
        previewLoadsInFlight.insert(item.id)

        previewQueue.async { [weak self] in
            guard let self else { return }
            let image: NSImage?
            switch item.kind {
            case .text:
                image = nil
            case .image:
                image = item.imagePayloadData.flatMap(NSImage.init(data:))
            case .file:
                PreviewFactory.previewImage(for: item) { image in
                    DispatchQueue.main.async {
                        self.previewLoadsInFlight.remove(item.id)
                        if let image {
                            self.previewImages[item.id] = image
                        }
                    }
                }
                return
            }
            DispatchQueue.main.async {
                self.previewLoadsInFlight.remove(item.id)
                if let image {
                    self.previewImages[item.id] = image
                }
            }
        }
    }

    private func schedulePasteShortcut() {
        let targetProcessIdentifier = pendingPasteTargetProcessIdentifier ?? lastPasteTargetProcessIdentifier
        pendingPasteTargetProcessIdentifier = nil
        suspendClipboardMonitoring(for: Self.postPasteMonitoringSuspension)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            let targetApplication = targetProcessIdentifier.flatMap(NSRunningApplication.init(processIdentifier:))
            let eventTargetProcessIdentifier = targetApplication?.processIdentifier

            if let application = targetApplication {
                application.activate(options: [.activateIgnoringOtherApps])
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                DispatchQueue.global(qos: .userInteractive).async {
                    Self.issuePasteShortcut(targetProcessIdentifier: eventTargetProcessIdentifier)
                }
            }
        }
    }

    private func suspendClipboardMonitoring(for duration: TimeInterval) {
        let resumeDate = Date().addingTimeInterval(duration)
        if let clipboardMonitoringSuspendedUntil {
            self.clipboardMonitoringSuspendedUntil = max(clipboardMonitoringSuspendedUntil, resumeDate)
        } else {
            clipboardMonitoringSuspendedUntil = resumeDate
        }
    }

    private func installExcludedAppPasteEventMonitor() {
        guard excludedAppPasteEventTap == nil else { return }

        let eventMask = CGEventMask(1 << CGEventType.keyDown.rawValue)
        let selfPointer = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())

        guard let eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: eventMask,
            callback: { _, type, event, refcon in
                guard type == .keyDown, let refcon else {
                    return Unmanaged.passUnretained(event)
                }

                let manager = Unmanaged<ClipboardManager>.fromOpaque(refcon).takeUnretainedValue()
                manager.noteExcludedAppPasteShortcutIfNeeded(event)
                return Unmanaged.passUnretained(event)
            },
            userInfo: selfPointer
        ) else {
            return
        }

        let eventSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), eventSource, .commonModes)
        CGEvent.tapEnable(tap: eventTap, enable: true)

        excludedAppPasteEventTap = eventTap
        excludedAppPasteEventSource = eventSource
    }

    private func noteExcludedAppPasteShortcutIfNeeded(_ event: CGEvent) {
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        guard keyCode == Int64(kVK_ANSI_V) else { return }
        guard event.flags.contains(.maskCommand) else { return }

        let sourceProcessIdentifier = pid_t(event.getIntegerValueField(.eventSourceUnixProcessID))
        let generatedEventMarker = event.getIntegerValueField(.eventSourceUserData)

        DispatchQueue.main.async { [weak self] in
            let now = Date()
            self?.lastPasteShortcutDate = now
            let isExcludedParrotEvent = generatedEventMarker == Self.parrotGeneratedEventMarker
                && AppSettings.shared.isApplicationExcluded(
                    bundleIdentifier: AppSettings.parrotBundleIdentifier
                )
            if Self.isExcludedApplicationProcess(sourceProcessIdentifier) || isExcludedParrotEvent {
                self?.lastExcludedAppPasteShortcutDate = now
            }
        }
    }

    private func restorePasteTargetApplication(processIdentifier: pid_t) {
        guard let application = NSRunningApplication(processIdentifier: processIdentifier) else { return }
        application.activate(options: [.activateIgnoringOtherApps])
    }

    private func rememberPasteTarget(_ application: NSRunningApplication) {
        pendingPasteTargetProcessIdentifier = application.processIdentifier
        lastPasteTargetProcessIdentifier = application.processIdentifier
    }

    private func writeStandardItemToPasteboard(
        _ item: ClipboardItem,
        signature: String,
        shouldPaste: Bool,
        refreshHistoryEntry: Bool,
        pasteMode: ClipboardPasteMode
    ) {
        if !pasteboardAlreadyContains(signature: signature) {
            pasteboard.clearContents()

            switch item.kind {
            case .text:
                writeTextItemToPasteboard(item, mode: pasteMode)
            case .file:
                if let fileURL = item.fileURL {
                    pasteboard.writeObjects([fileURL as NSURL])
                }
            case .image:
                break
            }

            lastChangeCount = pasteboard.changeCount
            lastWrittenPasteboardSignature = signature
        }

        if shouldPaste {
            schedulePasteShortcut()
        }

        guard refreshHistoryEntry else { return }
        recordActivation(for: item, deferUIWork: shouldPaste)
    }

    private func writeImageToPasteboard(
        item: ClipboardItem,
        signature: String,
        shouldPaste: Bool,
        refreshHistoryEntry: Bool
    ) {
        if !pasteboardAlreadyContains(signature: signature) {
            pasteboard.clearContents()

            let pasteboardItem = NSPasteboardItem()
            let provider = LazyImagePasteboardDataProvider(imageData: item.imageData, imageDiskPath: item.imageDiskPath)
            pasteboardItem.setDataProvider(provider, forTypes: [.tiff])

            if pasteboard.writeObjects([pasteboardItem]) {
                lastChangeCount = pasteboard.changeCount
                lastWrittenPasteboardSignature = signature
            }
        }

        if shouldPaste {
            schedulePasteShortcut()
        }

        guard refreshHistoryEntry else { return }
        recordActivation(for: item, deferUIWork: shouldPaste)
    }

    private func recordActivation(for item: ClipboardItem, deferUIWork: Bool) {
        let applyActivation = { [weak self] in
            guard let self else { return }
            if let existingIndex = self.items.firstIndex(where: { $0.id == item.id }) {
                let existingItem = self.items[existingIndex]
                existingItem.timestamp = Date()
                self.items = self.items
                self.lastActivatedItemID = existingItem.id
                return
            }

            let activatedItem = self.addItem(item, refreshTimestamp: true)
            self.lastActivatedItemID = activatedItem.id
        }

        if deferUIWork {
            DispatchQueue.main.async(execute: applyActivation)
        } else {
            applyActivation()
        }
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

    private static func issuePasteShortcut(targetProcessIdentifier: pid_t?) {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        guard AXIsProcessTrustedWithOptions(options) else { return }

        guard let source = CGEventSource(stateID: .combinedSessionState) else { return }
        let keyCode = CGKeyCode(kVK_ANSI_V)
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true)
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)
        keyDown?.flags = CGEventFlags.maskCommand
        keyUp?.flags = CGEventFlags.maskCommand

        if let targetProcessIdentifier {
            keyDown?.postToPid(targetProcessIdentifier)
            keyUp?.postToPid(targetProcessIdentifier)
        } else {
            keyDown?.post(tap: CGEventTapLocation.cghidEventTap)
            keyUp?.post(tap: CGEventTapLocation.cghidEventTap)
        }
    }

    private static func visibleApplicationBelowQuickTray(excluding currentProcessIdentifier: pid_t) -> NSRunningApplication? {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let windowInfoList = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return nil
        }

        for windowInfo in windowInfoList {
            guard let ownerProcessIdentifier = windowInfo[kCGWindowOwnerPID as String] as? pid_t else { continue }
            guard ownerProcessIdentifier != currentProcessIdentifier else { continue }
            guard let layer = windowInfo[kCGWindowLayer as String] as? Int, layer == 0 else { continue }
            guard let application = NSRunningApplication(processIdentifier: ownerProcessIdentifier) else { continue }
            return application
        }

        return nil
    }

    private static func isExcludedApplicationProcess(_ processIdentifier: pid_t) -> Bool {
        guard processIdentifier > 0 else { return false }
        guard let application = NSRunningApplication(processIdentifier: processIdentifier) else { return false }
        return AppSettings.shared.isApplicationExcluded(
            bundleIdentifier: application.bundleIdentifier,
            name: application.localizedName
        )
    }

    private static func isTypelessRunning() -> Bool {
        NSWorkspace.shared.runningApplications.contains { application in
            if application.bundleIdentifier == AppSettings.typelessBundleIdentifier {
                return true
            }

            if application.localizedName?.localizedCaseInsensitiveContains("Typeless") == true {
                return true
            }

            return application.bundleURL?.path.localizedCaseInsensitiveContains("/Typeless.app") == true
                || application.executableURL?.path.localizedCaseInsensitiveContains("/Typeless.app/") == true
        }
    }

    private func pasteboardAlreadyContains(signature: String) -> Bool {
        lastWrittenPasteboardSignature == signature && pasteboard.changeCount == lastChangeCount
    }

    private func pasteboardSignature(for item: ClipboardItem, pasteMode: ClipboardPasteMode) -> String {
        switch item.kind {
        case .text:
            return "item:\(item.id.uuidString):text:\(pasteMode.rawValue)"
        case .image:
            return "item:\(item.id.uuidString):image"
        case .file:
            return "item:\(item.id.uuidString):file"
        }
    }

    private func pasteboardSignature(forText text: String) -> String {
        var hasher = Hasher()
        hasher.combine(text)
        return "text:\(hasher.finalize())"
    }

    private func clearPasteboardSignatureIfNeeded(for itemID: UUID) {
        guard let lastWrittenPasteboardSignature else { return }
        guard lastWrittenPasteboardSignature.contains(itemID.uuidString) else { return }
        self.lastWrittenPasteboardSignature = nil
    }

    private func loadItems() {
        guard let persistenceURL, FileManager.default.fileExists(atPath: persistenceURL.path) else { return }

        do {
            let data = try Data(contentsOf: persistenceURL)
            suppressItemSideEffects = true
            items = try JSONDecoder().decode([ClipboardItem].self, from: data)
            for item in items {
                persistImagePayloadIfNeeded(for: item)
            }
            suppressItemSideEffects = false
            historyRevision += 1
            enforceImageMemoryBudget()
            scheduleSaveItems()
        } catch {
            suppressItemSideEffects = false
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

    static func normalize(_ value: String) -> String {
        value
            .folding(options: [.diacriticInsensitive, .widthInsensitive, .caseInsensitive], locale: .current)
            .lowercased()
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func tokenizedWords(_ value: String) -> [String] {
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

        usesCustomStackQueue = false
        stackCursor = 0
        stackQueueRevision = historyRevision
        lastStackPasteDate = nil
    }

    private func shouldResetStackQueue(at date: Date) -> Bool {
        if stackQueue.isEmpty {
            return true
        }
        if usesCustomStackQueue {
            let remainingItemIDs = Set(items.map(\.id))
            return stackQueue.allSatisfy { !remainingItemIDs.contains($0) } || stackCursor >= stackQueue.count
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
                continue
            } else {
                imageItem.setImageDataInMemory(nil)
                imageItem.clearImageCache()
            }
        }
    }

    private func writeTextItemToPasteboard(_ item: ClipboardItem, mode: ClipboardPasteMode) {
        guard let textContent = item.textContent else { return }

        switch mode {
        case .plain:
            pasteboard.setString(textContent, forType: .string)
        case .rich:
            pasteboard.setString(textContent, forType: .string)
            if let richTextData = item.richTextData {
                pasteboard.setData(richTextData, forType: .rtf)
            }
            if let htmlData = item.htmlData {
                pasteboard.setData(htmlData, forType: .html)
            }
        case .markdown:
            pasteboard.setString(textContent, forType: .string)
            if let markdownRTF = Self.markdownRTFData(from: textContent) {
                pasteboard.setData(markdownRTF, forType: .rtf)
            }
        }
    }

    private static func extractStringFromRichPayload(rtfData: Data?, htmlData: Data?) -> String? {
        if let rtfData,
           let attributed = try? NSAttributedString(
                data: rtfData,
                options: [.documentType: NSAttributedString.DocumentType.rtf],
                documentAttributes: nil
           ) {
            let string = attributed.string.trimmingCharacters(in: .whitespacesAndNewlines)
            if !string.isEmpty {
                return string
            }
        }

        if let htmlData,
           let attributed = try? NSAttributedString(
                data: htmlData,
                options: [.documentType: NSAttributedString.DocumentType.html],
                documentAttributes: nil
           ) {
            let string = attributed.string.trimmingCharacters(in: .whitespacesAndNewlines)
            if !string.isEmpty {
                return string
            }
        }

        return nil
    }

    private static func markdownRTFData(from markdown: String) -> Data? {
        guard let attributed = try? AttributedString(markdown: markdown) else { return nil }
        let nsAttributed = NSAttributedString(attributed)
        let fullRange = NSRange(location: 0, length: nsAttributed.length)
        return try? nsAttributed.data(
            from: fullRange,
            documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
        )
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
}

private final class LazyImagePasteboardDataProvider: NSObject, NSPasteboardItemDataProvider {
    private let imageData: Data?
    private let imageDiskPath: String?

    init(imageData: Data?, imageDiskPath: String?) {
        self.imageData = imageData
        self.imageDiskPath = imageDiskPath
    }

    func pasteboard(
        _ pasteboard: NSPasteboard?,
        item: NSPasteboardItem,
        provideDataForType type: NSPasteboard.PasteboardType
    ) {
        guard type == .tiff else { return }

        if let imageData {
            item.setData(imageData, forType: type)
            return
        }

        guard let imageDiskPath else { return }
        let url = URL(fileURLWithPath: imageDiskPath)
        guard let data = try? Data(contentsOf: url) else { return }
        item.setData(data, forType: type)
    }
}
