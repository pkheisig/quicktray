import SwiftUI
import AppKit
import UniformTypeIdentifiers
import NaturalLanguage

enum ClipboardType: String, Codable {
    case text
    case image
}

class ClipboardItem: Identifiable, Hashable, Codable {
    let id: UUID
    let type: ClipboardType
    let textContent: String?
    let imageData: Data?
    var timestamp: Date
    var isPinned: Bool = false
    
    private var _cachedImage: NSImage?
    var imageContent: NSImage? {
        if type != .image { return nil }
        if let cached = _cachedImage { return cached }
        guard let data = imageData else { return nil }
        _cachedImage = NSImage(data: data)
        return _cachedImage
    }
    
    init(text: String) {
        self.id = UUID()
        self.type = .text
        self.textContent = text
        self.imageData = nil
        self.timestamp = Date()
    }
    
    init(image: NSImage) {
        self.id = UUID()
        self.type = .image
        self.textContent = nil
        self.imageData = image.tiffRepresentation
        self.timestamp = Date()
        self._cachedImage = image
    }
    
    // Hashable conformance
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(isPinned)
        hasher.combine(timestamp)
    }
    
    static func == (lhs: ClipboardItem, rhs: ClipboardItem) -> Bool {
        lhs.id == rhs.id && lhs.isPinned == rhs.isPinned && lhs.timestamp == rhs.timestamp
    }

    // Codable support for the class
    enum CodingKeys: String, CodingKey {
        case id, type, textContent, imageData, timestamp, isPinned
    }

    required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        type = try container.decode(ClipboardType.self, forKey: .type)
        textContent = try container.decodeIfPresent(String.self, forKey: .textContent)
        imageData = try container.decodeIfPresent(Data.self, forKey: .imageData)
        timestamp = try container.decode(Date.self, forKey: .timestamp)
        isPinned = try container.decode(Bool.self, forKey: .isPinned)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(type, forKey: .type)
        try container.encode(textContent, forKey: .textContent)
        try container.encode(imageData, forKey: .imageData)
        try container.encode(timestamp, forKey: .timestamp)
        try container.encode(isPinned, forKey: .isPinned)
    }

    func snapshot() -> ClipboardItem {
        // This is a bit hacky but safe for transfer
        return try! JSONDecoder().decode(ClipboardItem.self, from: JSONEncoder().encode(self))
    }
}

private final class SemanticSearchIndex {
    private struct EmbeddingEntry {
        let fingerprint: Int
        let vector: [Double]?
    }
    
    private var embeddingCache: [UUID: EmbeddingEntry] = [:]
    
    func rankedItems(from items: [ClipboardItem], query rawQuery: String) -> [ClipboardItem] {
        let query = normalize(rawQuery)
        guard !query.isEmpty else {
            return items
        }
        
        let textItems = items.filter { $0.type == .text && !normalize($0.textContent ?? "").isEmpty }
        guard !textItems.isEmpty else {
            return []
        }
        
        pruneCache(validIDs: Set(textItems.map(\.id)))
        let queryVector = embeddingVector(for: query, itemID: nil)
        
        let scored = textItems.compactMap { item -> (ClipboardItem, Double)? in
            guard let text = item.textContent else { return nil }
            
            let normalizedText = normalize(text)
            guard !normalizedText.isEmpty else { return nil }
            
            let lexical = lexicalScore(query: query, text: normalizedText)
            let semantic = semanticScore(queryVector: queryVector, text: normalizedText, itemID: item.id)
            let score = combinedScore(lexical: lexical, semantic: semantic)
            
            guard score >= 0.17 else { return nil }
            return (item, score)
        }
        
        return scored
            .sorted {
                if abs($0.1 - $1.1) > 0.001 {
                    return $0.1 > $1.1
                }
                return $0.0.timestamp > $1.0.timestamp
            }
            .map(\.0)
    }
    
    private func pruneCache(validIDs: Set<UUID>) {
        embeddingCache = embeddingCache.filter { validIDs.contains($0.key) }
    }
    
    private func combinedScore(lexical: Double, semantic: Double) -> Double {
        if lexical >= 0.95 {
            return lexical
        }
        return max(lexical, (semantic * 0.75) + (lexical * 0.25))
    }
    
    private func semanticScore(queryVector: [Double]?, text: String, itemID: UUID) -> Double {
        guard let queryVector else { return 0 }
        guard let textVector = embeddingVector(for: text, itemID: itemID) else { return 0 }
        return max(0, cosineSimilarity(queryVector, textVector))
    }
    
    private func embeddingVector(for text: String, itemID: UUID?) -> [Double]? {
        let input = embeddingInput(text)
        let fingerprint = input.hashValue
        
        if let itemID, let cached = embeddingCache[itemID], cached.fingerprint == fingerprint {
            return cached.vector
        }
        
        let language = NLLanguageRecognizer.dominantLanguage(for: input) ?? .english
        let embedding = NLEmbedding.sentenceEmbedding(for: language) ?? NLEmbedding.sentenceEmbedding(for: .english)
        let vector = embedding?.vector(for: input)
        
        if let itemID {
            embeddingCache[itemID] = EmbeddingEntry(fingerprint: fingerprint, vector: vector)
        }
        
        return vector
    }
    
    private func lexicalScore(query: String, text: String) -> Double {
        if text.contains(query) {
            return 1.0
        }
        
        let queryTokens = tokenSet(from: query)
        let textTokens = tokenSet(from: text)
        guard !queryTokens.isEmpty, !textTokens.isEmpty else { return 0 }
        
        let overlap = queryTokens.intersection(textTokens).count
        guard overlap > 0 else { return 0 }
        
        let coverage = Double(overlap) / Double(queryTokens.count)
        return min(coverage, 0.95)
    }
    
    private func tokenSet(from text: String) -> Set<String> {
        let tokens = text
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.count >= 2 }
        return Set(tokens)
    }
    
    private func normalize(_ text: String) -> String {
        text
            .lowercased()
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    private func embeddingInput(_ text: String) -> String {
        String(normalize(text).prefix(1024))
    }
    
    private func cosineSimilarity(_ lhs: [Double], _ rhs: [Double]) -> Double {
        guard lhs.count == rhs.count, !lhs.isEmpty else { return 0 }
        
        var dot = 0.0
        var lhsNorm = 0.0
        var rhsNorm = 0.0
        
        for index in lhs.indices {
            dot += lhs[index] * rhs[index]
            lhsNorm += lhs[index] * lhs[index]
            rhsNorm += rhs[index] * rhs[index]
        }
        
        guard lhsNorm > 0, rhsNorm > 0 else { return 0 }
        return dot / (sqrt(lhsNorm) * sqrt(rhsNorm))
    }
}

class ClipboardManager: ObservableObject {
    private static let retentionLimitKey = "unpinnedRetentionLimit"
    private static let defaultUnpinnedRetentionLimit = 20
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
    
    @Published var searchQuery: String = "" {
        didSet {
            refreshDisplayedItems()
        }
    }
    
    @Published private(set) var displayedItems: [ClipboardItem] = []
    
    private var timer: Timer?
    private let pasteboard = NSPasteboard.general
    private var lastChangeCount: Int
    private let searchQueue = DispatchQueue(label: "com.gemini.quicktray.semantic-search", qos: .userInitiated)
    private var activeSearchID = UUID()
    private let semanticSearchIndex = SemanticSearchIndex()
    
    private static func clampedRetentionLimit(_ value: Int) -> Int {
        min(max(value, minUnpinnedRetentionLimit), maxUnpinnedRetentionLimit)
    }
    
    private var persistenceURL: URL? {
        guard let supportDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
        let appDir = supportDir.appendingPathComponent("com.gemini.QuickTray")
        
        // Ensure dir exists
        try? FileManager.default.createDirectory(at: appDir, withIntermediateDirectories: true)
        
        return appDir.appendingPathComponent("items.json")
    }
    
    init() {
        let savedLimit = UserDefaults.standard.integer(forKey: Self.retentionLimitKey)
        let initialLimit = savedLimit > 0 ? savedLimit : Self.defaultUnpinnedRetentionLimit
        self.unpinnedRetentionLimit = Self.clampedRetentionLimit(initialLimit)
        self.lastChangeCount = pasteboard.changeCount
        loadItems()
        trimUnpinnedItemsToLimit()
        refreshDisplayedItems()
        startMonitoring()
    }
    
    func startMonitoring() {
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.checkClipboard()
        }
    }
    
    func checkClipboard() {
        guard pasteboard.changeCount != lastChangeCount else { return }
        lastChangeCount = pasteboard.changeCount
        
        if let image = NSImage(pasteboard: pasteboard) {
            addItem(ClipboardItem(image: image))
        } else if let str = pasteboard.string(forType: .string) {
            addItem(ClipboardItem(text: str))
        }
    }
    
    func addItem(_ item: ClipboardItem) {
        DispatchQueue.main.async {
            // Check if item with same content already exists
            if let existingIndex = self.items.firstIndex(where: { 
                if $0.type != item.type { return false }
                if item.type == .text {
                    return $0.textContent == item.textContent
                } else {
                    return $0.imageData == item.imageData
                }
            }) {
                // Move existing item to top and update its timestamp
                let existingItem = self.items.remove(at: existingIndex)
                existingItem.timestamp = Date()
                self.items.insert(existingItem, at: 0)
            } else {
                // Insert new item at the absolute top
                self.items.insert(item, at: 0)
            }
            
            self.trimUnpinnedItemsToLimit()
        }
    }
    
    func togglePin(for id: UUID) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        
        let item = items[index]
        item.isPinned.toggle()
        
        items.remove(at: index)
        
        // When pinning/unpinning, we still move it to the top because it's an "active" interaction
        items.insert(item, at: 0)
        
        trimUnpinnedItemsToLimit()
    }
    
    func clearAll() {
        DispatchQueue.main.async {
            self.items.removeAll()
        }
    }
    
    func removeItem(id: UUID) {
        DispatchQueue.main.async {
            self.items.removeAll { $0.id == id }
        }
    }

    func copyToClipboard(item: ClipboardItem) {
        pasteboard.clearContents()
        if item.type == .text, let text = item.textContent {
            pasteboard.setString(text, forType: .string)
        } else if item.type == .image, let image = item.imageContent {
            pasteboard.writeObjects([image])
        }
        lastChangeCount = pasteboard.changeCount
        
        // Move to top when copied from history
        addItem(item)
    }
    
    // MARK: - Persistence
    
    private func saveItems() {
        guard let url = persistenceURL else { return }
        // Create a thread-safe snapshot by encoding existing data
        let itemsSnapshot = self.items.map { $0.snapshot() }
        DispatchQueue.global(qos: .background).async {
            do {
                let data = try JSONEncoder().encode(itemsSnapshot)
                try data.write(to: url)
            } catch {
                print("Failed to save items: \(error)")
            }
        }
    }
    
    private func loadItems() {
        guard let url = persistenceURL, FileManager.default.fileExists(atPath: url.path) else { return }
        do {
            let data = try Data(contentsOf: url)
            let loadedItems = try JSONDecoder().decode([ClipboardItem].self, from: data)
            self.items = loadedItems
        } catch {
            print("Failed to load items: \(error)")
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
    
    private func trimUnpinnedItemsToLimit() {
        var unpinnedToRemove = items.filter { !$0.isPinned }.count - unpinnedRetentionLimit
        guard unpinnedToRemove > 0 else { return }
        
        for index in items.indices.reversed() where unpinnedToRemove > 0 {
            guard !items[index].isPinned else { continue }
            items.remove(at: index)
            unpinnedToRemove -= 1
        }
    }
    
    private func refreshDisplayedItems() {
        let querySnapshot = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        let itemsSnapshot = items
        
        // If query is empty, update immediately on main thread to ensure UI is in sync
        if querySnapshot.isEmpty {
            self.displayedItems = itemsSnapshot
            return
        }
        
        let searchID = UUID()
        activeSearchID = searchID
        
        searchQueue.async { [weak self] in
            guard let self else { return }
            let rankedItems = self.semanticSearchIndex.rankedItems(from: itemsSnapshot, query: querySnapshot)
            
            DispatchQueue.main.async {
                guard self.activeSearchID == searchID else { return }
                self.displayedItems = rankedItems
            }
        }
    }
}
