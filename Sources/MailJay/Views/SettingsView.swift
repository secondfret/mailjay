import SwiftUI

struct SettingsView: View {
    let store: AppStore
    @State private var draft: AppConfiguration = .empty
    @State private var saveMessage = ""

    private let shortcuts: [(title: String, keys: [String])] = [
        ("Fetch new emails", ["⇧", "⌘", "R"]),
        ("Re-categorize all loaded", ["⌥", "⌘", "R"]),
        ("Archive selected", ["⌘", "↩"]),
        ("Move selected to Trash", ["⌘", "⌫"]),
        ("Previous category", ["⌘", "↑"]),
        ("Next category", ["⌘", "↓"]),
        ("Previous account", ["⇧", "⌘", "↑"]),
        ("Next account", ["⇧", "⌘", "↓"]),
    ]

    var body: some View {
        Form {
            Section("Classifier") {
                SecureField("TypeSafe Jev API key", text: $draft.jevAPIKey)
                Text("Email sender, subject, snippet, and up to 8,000 body characters are sent to TypeSafe for classification.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("Triage") {
                Stepper(value: $draft.maxMessages, in: 10...1000, step: 10) {
                    Text("Messages per batch: \(draft.maxMessages)")
                }
                Text("How many new inbox emails to fetch and classify per account, per scan.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Picker("Auto-fetch interval", selection: $draft.autoFetchIntervalMinutes) {
                    Text("Off").tag(0)
                    Text("Every 5 minutes").tag(5)
                    Text("Every 10 minutes").tag(10)
                    Text("Every 15 minutes").tag(15)
                    Text("Every 30 minutes").tag(30)
                    Text("Every hour").tag(60)
                }
                Text("Automatically fetch and classify new mail for every connected inbox. Manual fetch still works anytime.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading) {
                    Text("Minimum confidence: \(draft.confidenceThreshold, format: .percent.precision(.fractionLength(0)))")
                    Slider(value: $draft.confidenceThreshold, in: 0.1...0.9, step: 0.05)
                }
                Text("Lower-confidence messages go to Needs Review and are never selected automatically.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("Privacy") {
                Toggle("Load remote images", isOn: $draft.loadRemoteImages)
                Text("On by default so newsletters and HTML mail look complete. Turn off to block remote images and tracking pixels; senders won’t learn that you opened the message.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            HStack {
                Button("Save") { save() }
                    .buttonStyle(.borderedProminent)
                Text(saveMessage)
                    .foregroundStyle(.secondary)
            }

            Section("Keyboard Shortcuts") {
                ForEach(shortcuts, id: \.title) { item in
                    HStack {
                        Text(item.title)
                        Spacer()
                        shortcutKeys(item.keys)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .padding()
        .frame(width: 560, height: 720)
        .onAppear {
            draft = store.configuration
            saveMessage = ""
        }
    }

    private func shortcutKeys(_ keys: [String]) -> some View {
        HStack(spacing: 5) {
            ForEach(Array(keys.enumerated()), id: \.offset) { _, key in
                Text(key)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(MailJayTheme.textSecondary)
                    .frame(minWidth: 22, minHeight: 22)
                    .padding(.horizontal, 5)
                    .background(
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(MailJayTheme.cardElevated)
                    )
            }
        }
    }

    private func save() {
        do {
            try store.saveConfiguration(draft)
            saveMessage = "Saved securely."
        } catch {
            saveMessage = error.localizedDescription
        }
    }
}
