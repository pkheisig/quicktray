import SwiftUI
import AppKit
import UniformTypeIdentifiers
import NaturalLanguage

enum ClipboardType: String, Codable {
    case text
    case image
}

struct ClipboardItem: Identifiable, Hashable, Codable {
    let id: UUID
    let type: ClipboardType
    let textContent: String?
    let imageData: Data?
    let timestamp: Date
    var isPinned: Bool = false
    
    var imageContent: NSImage? {
        guard let data = imageData else { return nil }
        return NSImage(data: data)
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
    }
    
    // Hashable conformance
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(isPinned) // Update hash if pin state changes
    }
    
    static func == (lhs: ClipboardItem, rhs: ClipboardItem) -> Bool {
        lhs.id == rhs.id && lhs.isPinned == rhs.isPinned
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
        
        // Prioritize images
        if let image = NSImage(pasteboard: pasteboard) {
            addItem(ClipboardItem(image: image))
        } else if let str = pasteboard.string(forType: .string) {
            // Avoid adding duplicates of the immediate last item
            if let last = items.first(where: { !$0.isPinned }), last.type == .text, last.textContent == str {
                return // Duplicate of recent unpinned item
            }
            // Check pinned items too? Maybe not, allow re-copying to bring to top?
            // For now simple logic: just add it.
            addItem(ClipboardItem(text: str))
        }
    }
    
    func addItem(_ item: ClipboardItem) {
        DispatchQueue.main.async {
            // Insert after the last pinned item
            let pinnedCount = self.items.filter { $0.isPinned }.count
            self.items.insert(item, at: pinnedCount)
            
            self.trimUnpinnedItemsToLimit()
        }
    }
    
    func togglePin(for id: UUID) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        
        var item = items[index]
        item.isPinned.toggle()
        
        items.remove(at: index)
        
        if item.isPinned {
            // Move to top (or bottom of pinned list)
            // Let's say newest pinned stays at top? Or oldest pinned?
            // Usually user wants recently pinned at top.
            items.insert(item, at: 0)
        } else {
            // Move to unpinned section, sorted by date
            // Find insertion point based on timestamp
            let pinnedCount = items.filter { $0.isPinned }.count
            // Simple approach: Insert at top of unpinned
            items.insert(item, at: pinnedCount)
            
            // Ideally we re-sort the whole unpinned section by date, but since we add new items to top, 
            // the order should be roughly preserved. 
            // To be strict: 
            // let unpinned = items.filter { !$0.isPinned }.sorted { $0.timestamp > $1.timestamp }
            // items = items.filter { $0.isPinned } + unpinned
        }
        
        trimUnpinnedItemsToLimit()
    }
    
    func clearAll() {
        DispatchQueue.main.async {
            // Maybe keep pinned items?
            // "Delete All" usually means all.
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
    }
    
    // MARK: - Persistence
    
    private func saveItems() {
        guard let url = persistenceURL else { return }
        DispatchQueue.global(qos: .background).async {
            do {
                let data = try JSONEncoder().encode(self.items)
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
        let querySnapshot = searchQuery
        let itemsSnapshot = items
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
