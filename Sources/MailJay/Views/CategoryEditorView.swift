import AppKit
import SwiftUI

struct CategoryEditorView: View {
    @Bindable var store: AppStore
    @Environment(\.dismiss) private var dismiss

    @State private var jsonText = ""
    @State private var errorMessage = ""
    @State private var statusMessage = ""
    @State private var preview: [MailCategory] = []

    var body: some View {
        VStack(spacing: 0) {
            headerBar
            Divider()
            HStack(spacing: 0) {
                jsonEditor
                Divider()
                previewPane
                    .frame(width: 240)
            }
            Divider()
            footerBar
        }
        .frame(width: 820, height: 560)
        .background(.background)
        .onAppear {
            loadFromStore()
        }
    }

    private var headerBar: some View {
        HStack(spacing: 12) {
            Button("Cancel") { dismiss() }
                .keyboardShortcut(.cancelAction)
            Spacer()
            Text("Customize Categories")
                .font(.headline)
            Spacer()
            Button("Copy Prompt") { copyPrompt() }
                .help("Copy an LLM prompt that explains the JSON schema")
            Button("Save") { save() }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var footerBar: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Button("Reset to Defaults") {
                applyPrettyJSON(MailCategory.defaults)
                statusMessage = "Restored defaults (not saved yet)."
                errorMessage = ""
            }
            Button("Format JSON") { formatJSON() }
            Spacer()
            if !errorMessage.isEmpty {
                Text(errorMessage)
                    .foregroundStyle(.red)
                    .lineLimit(2)
            } else if !statusMessage.isEmpty {
                Text(statusMessage)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            } else {
                Text("Paste LLM JSON here, or edit it. Needs Review stays automatic.")
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var jsonEditor: some View {
        TextEditor(text: $jsonText)
            .font(.system(.body, design: .monospaced))
            .scrollContentBackground(.hidden)
            .padding(12)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onChange(of: jsonText) { _, _ in
                refreshPreview()
            }
    }

    private var previewPane: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Preview")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.top, 12)
                .padding(.bottom, 6)
            if preview.isEmpty {
                Text(errorMessage.isEmpty ? "Invalid or empty JSON" : errorMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
                Spacer()
            } else {
                List(preview) { category in
                    Label(category.title, systemImage: category.systemImage)
                }
                .listStyle(.sidebar)
            }
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private func loadFromStore() {
        applyPrettyJSON(store.categories)
        errorMessage = ""
        statusMessage = ""
    }

    private func applyPrettyJSON(_ categories: [MailCategory]) {
        jsonText = MailCategory.prettyJSON(categories)
        preview = categories
    }

    private func refreshPreview() {
        do {
            preview = try MailCategory.decodeList(from: jsonText)
            if errorMessage.hasPrefix("JSON") || errorMessage.hasPrefix("Could not") {
                errorMessage = ""
            }
        } catch {
            preview = []
        }
    }

    private func formatJSON() {
        do {
            let categories = try MailCategory.decodeList(from: jsonText)
            applyPrettyJSON(categories)
            errorMessage = ""
            statusMessage = "Formatted."
        } catch {
            errorMessage = error.localizedDescription
            statusMessage = ""
        }
    }

    private func copyPrompt() {
        let prompt = MailCategory.llmAuthoringPrompt(currentJSON: jsonText)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(prompt, forType: .string)
        statusMessage = "Prompt copied — paste it into your LLM, then paste the JSON back here."
        errorMessage = ""
    }

    private func save() {
        do {
            let categories = try MailCategory.decodeList(from: jsonText)
            try store.saveCategories(categories)
            errorMessage = ""
            statusMessage = ""
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
            statusMessage = ""
        }
    }
}

extension MailCategory {
    static func prettyJSON(_ categories: [MailCategory]) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(categories),
              let text = String(data: data, encoding: .utf8) else {
            return "[]"
        }
        return text
    }

    static func decodeList(from text: String) throws -> [MailCategory] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw CategoryJSONError.empty
        }
        guard let data = trimmed.data(using: .utf8) else {
            throw CategoryJSONError.invalidEncoding
        }
        do {
            return try JSONDecoder().decode([MailCategory].self, from: data)
        } catch {
            throw CategoryJSONError.decodeFailed(error.localizedDescription)
        }
    }

    /// Prompt users can paste into ChatGPT/Claude/etc. to generate valid category JSON.
    static func llmAuthoringPrompt(currentJSON: String) -> String {
        let example = prettyJSON(defaults)
        let current = currentJSON.trimmingCharacters(in: .whitespacesAndNewlines)
        return """
        You are helping me configure triage categories for MailJay, a macOS Gmail triage app.

        Return ONLY a JSON array (no markdown fences, no commentary) that matches this schema exactly.
        Each element is one category object with these fields:

        - id (string, required): Stable slug used in the app and Gmail wiring. Use lowercase kebab or snake case like "junk", "receipts", "travel". Never use reserved ids "all" or "uncertain". Keep existing ids stable when editing.
        - title (string, required): Short sidebar label, e.g. "Needs Reply".
        - systemImage (string, required): An SF Symbol name that exists on macOS, e.g. "trash", "receipt", "arrowshape.turn.up.left", "archivebox", "airplane", "briefcase".
        - modelDescription (string, required): Fuller criteria sent to TypeSafe Jev. Explain when mail belongs here and what the user should do with it. Prefer distinctive paragraphs so categories do not overlap.
        - gmailLabelName (string or null, required key): If set, Archive applies Gmail label "Jev/{gmailLabelName}". Use null when no Gmail label should be applied (e.g. junk).
        - sortOrder (integer, required): 0-based display order in the sidebar.

        Rules:
        - Output a JSON array with at least one category.
        - Every id must be unique.
        - Do not include a "Needs Review" / uncertain category — the app creates that from low confidence.
        - Prefer 3–8 focused categories over many vague ones.
        - Do not include modelLabel or other unused fields — Jev only reads modelDescription.
        - modelDescription should be a full paragraph of criteria.

        Example of valid output:
        \(example)

        My current categories JSON (edit/improve this unless I ask for a full redesign):
        \(current.isEmpty ? example : current)

        Now produce the improved JSON array only.
        """
    }
}

private enum CategoryJSONError: LocalizedError {
    case empty
    case invalidEncoding
    case decodeFailed(String)

    var errorDescription: String? {
        switch self {
        case .empty:
            "JSON is empty."
        case .invalidEncoding:
            "Could not read JSON text."
        case .decodeFailed(let detail):
            "JSON error: \(detail)"
        }
    }
}
