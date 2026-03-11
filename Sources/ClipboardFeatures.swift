import Foundation

enum ClipboardPasteMode: String, Codable, CaseIterable, Identifiable {
    case rich
    case plain
    case markdown

    var id: String { rawValue }

    var title: String {
        switch self {
        case .rich:
            return "Rich"
        case .plain:
            return "Plain"
        case .markdown:
            return "Markdown"
        }
    }

    var shortTitle: String {
        switch self {
        case .rich:
            return "RTF"
        case .plain:
            return "TXT"
        case .markdown:
            return "MD"
        }
    }

    var symbolName: String {
        switch self {
        case .rich:
            return "textformat"
        case .plain:
            return "text.alignleft"
        case .markdown:
            return "chevron.left.forwardslash.chevron.right"
        }
    }

    var helpText: String {
        switch self {
        case .rich:
            return "Paste with original rich formatting when available."
        case .plain:
            return "Strip formatting and paste plain text only."
        case .markdown:
            return "Render Markdown into rich text before pasting."
        }
    }
}
