import SwiftUI
import AppKit
import UniformTypeIdentifiers

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
        }
    }
    private var timer: Timer?
    private let pasteboard = NSPasteboard.general
    private var lastChangeCount: Int
    
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
}
