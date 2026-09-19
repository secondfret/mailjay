import SwiftUI

struct WelcomeView: View {
    let store: AppStore

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: emptyState.symbol)
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(MailJayTheme.textTertiary)
            Text(emptyState.title)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(MailJayTheme.textPrimary)
            if !emptyState.message.isEmpty {
                Text(emptyState.message)
                    .font(.system(size: 13))
                    .foregroundStyle(MailJayTheme.textSecondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 420)
            }

            switch emptyState.action {
            case .connect:
                HStack(spacing: 12) {
                    SettingsLink {
                        Text("Open Settings")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(MailJayTheme.textSecondary)
                    }
                    .buttonStyle(.plain)

                    primaryButton("Connect Gmail") {
                        Task { await store.addAccount() }
                    }
                }
                .padding(.top, 4)
            case .scan:
                primaryButton("Scan Inbox") {
                    Task { await store.scanInbox() }
                }
                .padding(.top, 4)
            case .none:
                EmptyView()
            }

            if case .loading(let message) = store.phase {
                ProgressView(message)
                    .tint(MailJayTheme.accent)
            }
            if case .applying(let message) = store.phase {
                ProgressView(message)
                    .tint(MailJayTheme.accent)
            }
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(MailJayTheme.canvas)
    }

    private var emptyState: DetailEmptyState {
        if !store.isConnected {
            return DetailEmptyState(
                symbol: "envelope.badge.shield.half.filled",
                title: "Connect your private inbox",
                message: "Authorize Gmail to get started\(classifierSetupHint). Tokens are stored in your Mac keychain.",
                action: .connect
            )
        }

        if store.phase.isBusy {
            return DetailEmptyState(
                symbol: "bird.circle.fill",
                title: "Working…",
                message: "",
                action: .none
            )
        }

        let pending = store.results.filter(\.isPending)
        if pending.isEmpty {
            if store.results.isEmpty {
                return DetailEmptyState(
                    symbol: "bird.circle.fill",
                    title: "Ready to triage",
                    message: "Scan your inbox to classify recent mail into buckets. Nothing changes in Gmail until you Archive or Delete.",
                    action: .scan
                )
            }
            return DetailEmptyState(
                symbol: "checkmark.circle",
                title: "You’re caught up",
                message: "No pending mail left to triage. Scan again anytime for new messages.",
                action: .none
            )
        }

        if store.filteredResults.isEmpty {
            let categoryTitle = store.title(forCategoryID: store.selectedCategoryID)
            return DetailEmptyState(
                symbol: "tray",
                title: "No mail in \(categoryTitle)",
                message: "Pick another category in the sidebar, or select a message from All Results.",
                action: .none
            )
        }

        return DetailEmptyState(
            symbol: "envelope.open",
            title: "Select a message",
            message: "Choose an email from the list to read it and review Jev’s suggestion.",
            action: .none
        )
    }

    private var classifierSetupHint: String {
        store.configuration.jevAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? " (add your TypeSafe Jev API key in Settings first)"
            : ""
    }

    private func primaryButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: MailJayTheme.radiusSm, style: .continuous)
                    .fill(MailJayTheme.accent)
            )
            .buttonStyle(.plain)
    }
}

private struct DetailEmptyState {
    enum Action {
        case none
        case connect
        case scan
    }

    let symbol: String
    let title: String
    let message: String
    let action: Action
}
