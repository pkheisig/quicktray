import Foundation
import AppKit

struct SnippetTemplate: Identifiable, Codable, Hashable {
    let id: UUID
    var title: String
    var body: String
    var isBuiltIn: Bool

    init(id: UUID = UUID(), title: String, body: String, isBuiltIn: Bool = false) {
        self.id = id
        self.title = title
        self.body = body
        self.isBuiltIn = isBuiltIn
    }

    var preview: String {
        String(body.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression).prefix(100))
    }
}

final class SnippetManager: ObservableObject {
    static let shared = SnippetManager()

    private enum Keys {
        static let snippets = "snippets.templates"
        static let defaultEmail = "snippets.defaultEmail"
    }

    @Published var templates: [SnippetTemplate] {
        didSet {
            saveTemplates()
        }
    }

    @Published var defaultEmail: String {
        didSet {
            UserDefaults.standard.set(defaultEmail, forKey: Keys.defaultEmail)
        }
    }

    private init() {
        defaultEmail = UserDefaults.standard.string(forKey: Keys.defaultEmail) ?? "you@example.com"

        if let data = UserDefaults.standard.data(forKey: Keys.snippets),
           let savedTemplates = try? JSONDecoder().decode([SnippetTemplate].self, from: data),
           !savedTemplates.isEmpty {
            templates = savedTemplates
        } else {
            templates = Self.defaultTemplates
        }
    }

    func addTemplate(title: String, body: String) {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedBody = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty, !trimmedBody.isEmpty else { return }
        templates.append(SnippetTemplate(title: trimmedTitle, body: trimmedBody, isBuiltIn: false))
    }

    func updateTemplate(id: UUID, title: String, body: String) {
        guard let index = templates.firstIndex(where: { $0.id == id }) else { return }

        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedBody = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty, !trimmedBody.isEmpty else { return }

        templates[index].title = trimmedTitle
        templates[index].body = trimmedBody
    }

    func removeTemplate(id: UUID) {
        guard let template = templates.first(where: { $0.id == id }) else { return }
        guard !template.isBuiltIn else { return }
        templates.removeAll { $0.id == id }
    }

    func renderedText(for template: SnippetTemplate) -> String {
        renderVariables(in: template.body)
    }

    func pasteTemplate(_ template: SnippetTemplate, shouldPaste: Bool = true) {
        let renderedText = renderVariables(in: template.body)
        ClipboardManager.shared.copyTextToClipboard(
            renderedText,
            shouldPaste: shouldPaste,
            addToHistory: true,
            sourceApplicationName: "QuickTray Snippet",
            sourceBundleIdentifier: Bundle.main.bundleIdentifier
        )
    }

    private func saveTemplates() {
        guard let data = try? JSONEncoder().encode(templates) else { return }
        UserDefaults.standard.set(data, forKey: Keys.snippets)
    }

    private func renderVariables(in template: String) -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale.current
        dateFormatter.dateStyle = .medium
        dateFormatter.timeStyle = .none

        let timeFormatter = DateFormatter()
        timeFormatter.locale = Locale.current
        timeFormatter.dateStyle = .none
        timeFormatter.timeStyle = .short

        let dateTimeFormatter = DateFormatter()
        dateTimeFormatter.locale = Locale.current
        dateTimeFormatter.dateStyle = .medium
        dateTimeFormatter.timeStyle = .short

        let isoFormatter = DateFormatter()
        isoFormatter.locale = Locale(identifier: "en_US_POSIX")
        isoFormatter.dateFormat = "yyyy-MM-dd"

        let now = Date()
        let clipboardText = NSPasteboard.general.string(forType: .string) ?? ""
        let variables: [String: String] = [
            "date": dateFormatter.string(from: now),
            "time": timeFormatter.string(from: now),
            "datetime": dateTimeFormatter.string(from: now),
            "iso_date": isoFormatter.string(from: now),
            "email": defaultEmail,
            "clipboard": clipboardText
        ]

        guard let expression = try? NSRegularExpression(pattern: "\\\\{\\\\{\\\\s*([a-zA-Z0-9_]+)\\\\s*\\\\}\\\\}") else {
            return template
        }

        let fullRange = NSRange(template.startIndex..<template.endIndex, in: template)
        let matches = expression.matches(in: template, range: fullRange)

        var rendered = template
        for match in matches.reversed() {
            guard match.numberOfRanges >= 2,
                  let fullMatchRange = Range(match.range(at: 0), in: rendered),
                  let keyRange = Range(match.range(at: 1), in: rendered) else {
                continue
            }

            let key = String(rendered[keyRange]).lowercased()
            if let replacement = variables[key] {
                rendered.replaceSubrange(fullMatchRange, with: replacement)
            }
        }

        return rendered
    }

    private static let defaultTemplates: [SnippetTemplate] = [
        SnippetTemplate(title: "Email", body: "{{email}}", isBuiltIn: true),
        SnippetTemplate(title: "Today", body: "{{date}}", isBuiltIn: true),
        SnippetTemplate(title: "ISO Date", body: "{{iso_date}}", isBuiltIn: true),
        SnippetTemplate(title: "Timestamp", body: "{{datetime}}", isBuiltIn: true)
    ]
}
