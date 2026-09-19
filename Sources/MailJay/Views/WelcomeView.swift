import SwiftUI

struct WelcomeView: View {
    let store: AppStore

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: statusImage)
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(MailJayTheme.textTertiary)
            Text(statusTitle)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(MailJayTheme.textPrimary)
            Text(statusMessage)
                .font(.system(size: 13))
                .foregroundStyle(MailJayTheme.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
            if !store.isConnected {
                HStack(spacing: 12) {
                    SettingsLink {
                        Text("Open Settings")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(MailJayTheme.textSecondary)
                    }
                    .buttonStyle(.plain)

                    Button("Connect Gmail") { Task { await store.addAccount() } }
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
                .padding(.top, 4)
            } else if !store.phase.isBusy {
                Button("Scan Inbox") { Task { await store.scanInbox() } }
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: MailJayTheme.radiusSm, style: .continuous)
                            .fill(MailJayTheme.accent)
                    )
                    .buttonStyle(.plain)
                    .padding(.top, 4)
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

    private var statusImage: String { store.isConnected ? "sparkles" : "envelope.badge.shield.half.filled" }
    private var statusTitle: String { store.isConnected ? "Ready to triage" : "Connect your private inbox" }
    private var statusMessage: String {
        store.isConnected
            ? "Review buckets, select messages, then Archive or Delete. Nothing changes in Gmail until you click one of those actions."
            : "Authorize Gmail to get started\(classifierSetupHint). Tokens are stored in your Mac keychain."
    }

    private var classifierSetupHint: String {
        store.configuration.jevAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? " (add your TypeSafe Jev API key in Settings first)"
            : ""
    }
}
