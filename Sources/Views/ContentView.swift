import SwiftUI
import AppKit

struct ContentView: View {
    @StateObject var clipboardManager = ClipboardManager()
    @State private var hoveredItemId: UUID?
    @State private var showClearConfirmation = false
    
    private var hasActiveSearch: Bool {
        !clipboardManager.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(spacing: 10) {
                HStack {
                    Text("QuickTray")
                        .font(.headline)
                        .foregroundColor(.primary)
                    Spacer()
                    
                    Stepper(value: $clipboardManager.unpinnedRetentionLimit, in: 1...500) {
                        Text("Keep \(clipboardManager.unpinnedRetentionLimit)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .controlSize(.small)
                    .help("Set how many unpinned items to retain")
                    
                    if showClearConfirmation {
                        HStack(spacing: 8) {
                            Text("Sure?")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            Button("Yes") {
                                clipboardManager.clearAll()
                                showClearConfirmation = false
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.red)
                            .controlSize(.small)
                            
                            Button("No") {
                                showClearConfirmation = false
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                    } else {
                        Button("Delete All") {
                            showClearConfirmation = true
                        }
                        .buttonStyle(.plain)
                        .foregroundColor(.secondary)
                        .help("Clear All History")
                        .padding(.horizontal, 4)
                    }
                    
                    Button("Quit") {
                        NSApplication.shared.terminate(nil)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                    
                    TextField("Search history", text: $clipboardManager.searchQuery)
                        .textFieldStyle(.roundedBorder)
                    
                    if hasActiveSearch {
                        Button("Clear") {
                            clipboardManager.searchQuery = ""
                        }
                        .buttonStyle(.plain)
                        .foregroundColor(.secondary)
                        .help("Clear search")
                    }
                }
            }
            .padding()
            .background(Color(NSColor.windowBackgroundColor))
            
            Divider()
            
            if clipboardManager.displayedItems.isEmpty {
                VStack {
                    Spacer()
                    Image(systemName: "doc.on.clipboard")
                        .font(.system(size: 40))
                        .foregroundColor(.secondary)
                        .padding(.bottom, 8)
                    Text(hasActiveSearch ? "No matching clipboard items" : "Clipboard is empty")
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .frame(minHeight: 200)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            // Anchor for scrolling to top
                            Color.clear
                                .frame(height: 1)
                                .id("top")
                            
                            ForEach(clipboardManager.displayedItems) { item in
                                HistoryRow(item: item, 
                                           onDelete: { clipboardManager.removeItem(id: item.id) },
                                           onCopy: { clipboardManager.copyToClipboard(item: item) },
                                           onPin: { clipboardManager.togglePin(for: item.id) }
                                )
                                Divider()
                            }
                        }
                    }
                    .onChange(of: clipboardManager.displayedItems.count) { _ in
                        // Only auto-scroll if we are not searching
                        if !hasActiveSearch {
                            withAnimation {
                                proxy.scrollTo("top", anchor: .top)
                            }
                        }
                    }
                    .onAppear {
                        // Ensure we open at the top
                        proxy.scrollTo("top", anchor: .top)
                    }
                }
                .frame(maxHeight: 500)
            }
        }
        .frame(width: 480)
        .background(EffectView(material: .popover, blendingMode: .behindWindow))
    }
}

struct HistoryRow: View {
    let item: ClipboardItem
    let onDelete: () -> Void
    let onCopy: () -> Void
    let onPin: () -> Void
    
    @State private var showDetail = false
    @State private var showCopiedFeedback = false
    @State private var isHovered = false
    
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            // Icon / Thumbnail
            if item.type == .image, let img = item.imageContent {
                Image(nsImage: img)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 40, height: 40)
                    .cornerRadius(4)
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.gray.opacity(0.3), lineWidth: 1))
            } else {
                Image(systemName: "text.alignleft")
                    .frame(width: 40, height: 40)
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(4)
                    .foregroundColor(.secondary)
            }
            
            // Content Preview
            VStack(alignment: .leading, spacing: 4) {
                if item.type == .text, let text = item.textContent {
                    Text(text.trimmingCharacters(in: .whitespacesAndNewlines))
                        .lineLimit(2)
                        .font(.system(size: 13))
                        .foregroundColor(.primary)
                } else {
                    Text("Image")
                        .font(.system(size: 13, weight: .medium))
                    Text("\(Int(item.imageContent?.size.width ?? 0)) × \(Int(item.imageContent?.size.height ?? 0))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                HStack(spacing: 4) {
                    if item.isPinned {
                        Image(systemName: "pin.fill")
                            .font(.caption2)
                            .foregroundColor(.yellow)
                    }
                    Text(item.timestamp, style: .time)
                        .font(.caption2)
                        .foregroundColor(.gray)
                }
            }
            
            Spacer()
            
            // Buttons
            HStack(spacing: 12) {
                // Copy Button
                Button(action: {
                    onCopy()
                    withAnimation {
                        showCopiedFeedback = true
                    }
                    // Hide feedback after 1.5s
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        withAnimation {
                            showCopiedFeedback = false
                        }
                    }
                }) {
                    if showCopiedFeedback {
                        Text("Copied!")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.green)
                            .transition(.scale.combined(with: .opacity))
                    } else {
                        Image(systemName: "doc.on.doc")
                            .foregroundColor(.gray.opacity(0.7))
                    }
                }
                .buttonStyle(.plain)
                .help("Copy to Clipboard")
                
                // Pin Button
                Button(action: onPin) {
                    Image(systemName: item.isPinned ? "pin.slash.fill" : "pin")
                        .foregroundColor(item.isPinned ? .orange : .gray.opacity(0.5))
                        .font(.system(size: 12))
                }
                .buttonStyle(.plain)
                .help(item.isPinned ? "Unpin" : "Pin to Top")
                
                // Delete Button
                Button(action: onDelete) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.gray.opacity(0.5))
                        .font(.system(size: 12))
                }
                .buttonStyle(.plain)
                .help("Delete Item")
            }
            .padding(.top, 4)
        }
        .padding(10)
        .background(isHovered ? Color.blue.opacity(0.1) : Color.clear)
        .background(item.isPinned ? Color.yellow.opacity(0.05) : Color.clear)
        .onHover { hovering in
            isHovered = hovering
        }
        .contentShape(Rectangle())
        // Drag and Drop
        .onDrag {
            if let text = item.textContent {
                return NSItemProvider(object: text as NSString)
            } else if let img = item.imageContent {
                return NSItemProvider(object: img)
            }
            return NSItemProvider()
        }
        // Click to view detail
        .onTapGesture {
            showDetail = true
        }
        .popover(isPresented: $showDetail) {
            DetailView(item: item)
        }
    }
}

struct DetailView: View {
    let item: ClipboardItem
    
    var body: some View {
        VStack {
            if let text = item.textContent {
                ScrollView {
                    Text(text)
                        .padding()
                        .textSelection(.enabled)
                }
            } else if let img = item.imageContent {
                Image(nsImage: img)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .padding()
            }
        }
        .frame(minWidth: 300, maxWidth: 600, minHeight: 200, maxHeight: 600)
    }
}

// Helper for visual blur
struct EffectView: NSViewRepresentable {
    var material: NSVisualEffectView.Material
    var blendingMode: NSVisualEffectView.BlendingMode

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}
