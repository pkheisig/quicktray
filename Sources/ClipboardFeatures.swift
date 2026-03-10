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

enum ClipboardPrivacyMode: String, Codable {
    case standard
    case masked
}

enum ClipboardAppRuleBehavior: String, Codable, CaseIterable, Identifiable {
    case save
    case mask
    case ignore

    var id: String { rawValue }

    var title: String {
        switch self {
        case .save:
            return "Save"
        case .mask:
            return "Mask"
        case .ignore:
            return "Ignore"
        }
    }

    var description: String {
        switch self {
        case .save:
            return "Store normally"
        case .mask:
            return "Store, but hide contents in history"
        case .ignore:
            return "Never store clips from this app"
        }
    }
}

struct AppClipboardRule: Identifiable, Codable, Hashable {
    var bundleIdentifier: String
    var applicationName: String
    var behavior: ClipboardAppRuleBehavior

    var id: String { bundleIdentifier }
}

struct SourceApplicationSummary: Identifiable, Hashable {
    var bundleIdentifier: String
    var applicationName: String
    var clipCount: Int
    var behavior: ClipboardAppRuleBehavior

    var id: String { bundleIdentifier }
}

struct ClipboardInspectionField: Identifiable, Hashable {
    let label: String
    let value: String

    var id: String { label }
}

struct ClipboardInspection {
    let summary: [ClipboardInspectionField]
    let typeIdentifiers: [String]
    let sensitivityFlags: [String]
    let hexPreview: String
}

enum SensitiveDataDetector {
    private static let keyPatterns: [(String, NSRegularExpression)] = [
        ("API key", try! NSRegularExpression(pattern: #"(?i)\b(?:api[_-]?key|secret|client[_-]?secret|access[_-]?token|auth(?:orization)?|password)\b\s*[:=]\s*['"]?[A-Za-z0-9_\-\/+=:.]{8,}"#)),
        ("Bearer token", try! NSRegularExpression(pattern: #"(?i)\bBearer\s+[A-Za-z0-9_\-\/+=:.]{12,}"#)),
        ("JWT", try! NSRegularExpression(pattern: #"\beyJ[A-Za-z0-9_\-]+?\.[A-Za-z0-9_\-]+?\.[A-Za-z0-9_\-]+\b"#)),
        ("OpenAI key", try! NSRegularExpression(pattern: #"\bsk-[A-Za-z0-9]{20,}\b"#)),
        ("GitHub token", try! NSRegularExpression(pattern: #"\b(?:ghp|github_pat)_[A-Za-z0-9_]{20,}\b"#)),
        ("AWS key", try! NSRegularExpression(pattern: #"\bAKIA[0-9A-Z]{16}\b"#)),
        ("Google API key", try! NSRegularExpression(pattern: #"\bAIza[0-9A-Za-z\-_]{30,}\b"#)),
        ("Slack token", try! NSRegularExpression(pattern: #"\bxox[abprs]-[A-Za-z0-9-]{10,}\b"#))
    ]

    private static let ansiExpression = try! NSRegularExpression(pattern: #"\u{001B}\[[0-9;]*[A-Za-z]"#)
    private static let numberExpression = try! NSRegularExpression(pattern: #"\b(?:\d[ -]?){13,19}\b"#)

    static func findings(in text: String) -> [String] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        let range = NSRange(trimmed.startIndex..<trimmed.endIndex, in: trimmed)
        var matches: [String] = []

        for (label, expression) in keyPatterns where expression.firstMatch(in: trimmed, range: range) != nil {
            matches.append(label)
        }

        let numberMatches = numberExpression.matches(in: trimmed, range: range)
        for match in numberMatches {
            guard let numberRange = Range(match.range, in: trimmed) else { continue }
            let digits = trimmed[numberRange].filter(\.isNumber)
            if isLikelyPaymentCard(String(digits)) {
                matches.append("Payment card")
                break
            }
        }

        if matches.isEmpty,
           trimmed.count >= 24,
           trimmed.range(of: #"[A-Za-z]"#, options: .regularExpression) != nil,
           trimmed.range(of: #"\d"#, options: .regularExpression) != nil,
           trimmed.range(of: #"\s"#, options: .regularExpression) == nil {
            matches.append("Long secret-like string")
        }

        return Array(Set(matches)).sorted()
    }

    static func containsANSIEscapes(in text: String) -> Bool {
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return ansiExpression.firstMatch(in: text, range: range) != nil
    }

    private static func isLikelyPaymentCard(_ digits: String) -> Bool {
        guard (13...19).contains(digits.count) else { return false }

        var sum = 0
        let reversedDigits = digits.reversed().compactMap { Int(String($0)) }
        for (index, digit) in reversedDigits.enumerated() {
            if index.isMultiple(of: 2) {
                sum += digit
            } else {
                let doubled = digit * 2
                sum += doubled > 9 ? doubled - 9 : doubled
            }
        }

        return sum % 10 == 0
    }
}
