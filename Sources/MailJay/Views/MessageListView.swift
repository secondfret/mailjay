import SwiftUI

struct MessageListView: View {
    @Bindable var store: AppStore
    @State private var searchText = ""

    private var displayedResults: [TriageResult] {
        let source = store.filteredResults
        guard !searchText.isEmpty else { return source }
        return source.filter {
            $0.message.sender.localizedCaseInsensitiveContains(searchText) ||
            $0.message.subject.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            if displayedResults.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(displayedResults) { result in
                            MessageRow(store: store, result: result, isSelected: store.selectedMessageID == result.id)
                                .onTapGesture {
                                    store.selectedMessageID = result.id
                                }
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                }
            }
        }
        .background(MailJayTheme.pane)
        .searchable(text: $searchText, prompt: "Search results")
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 10) {
                selectAllCheckbox

                VStack(alignment: .leading, spacing: 2) {
                    Text(store.title(forCategoryID: store.selectedCategoryID))
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(MailJayTheme.textPrimary)
                    if let status = store.phase.statusMessage {
                        HStack(spacing: 6) {
                            ProgressView()
                                .controlSize(.mini)
                            Text(status)
                                .font(.system(size: 11))
                                .foregroundStyle(MailJayTheme.textSecondary)
                                .lineLimit(1)
                        }
                    } else if let status = store.backgroundSyncStatus {
                        HStack(spacing: 6) {
                            ProgressView()
                                .controlSize(.mini)
                            Text(status)
                                .font(.system(size: 11))
                                .foregroundStyle(MailJayTheme.textSecondary)
                                .lineLimit(1)
                        }
                    } else if store.currentBucketSelectedCount > 0 {
                        Text("\(store.currentBucketSelectedCount) selected")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(MailJayTheme.textSecondary)
                    } else {
                        Text("\(displayedResults.count) messages")
                            .font(.system(size: 11, weight: .medium).monospacedDigit())
                            .foregroundStyle(MailJayTheme.textTertiary)
                    }
                }

                Spacer(minLength: 8)

                listActions
            }
            .padding(.horizontal, 10)
            .padding(.top, 12)
            .padding(.bottom, 8)
        }
    }

    private var selectAllCheckbox: some View {
        Toggle(
            "Select all messages",
            isOn: Binding(
                get: { store.allVisibleSelected },
                set: { store.setAllVisibleSelected($0) }
            )
        )
        .labelsHidden()
        .toggleStyle(.checkbox)
        .disabled(store.currentBucketSelectableCount == 0 || store.phase.isBusy)
        .help(store.allVisibleSelected ? "Deselect all" : "Select all")
        .frame(width: MessageRowMetrics.checkboxColumnWidth, alignment: .center)
        .padding(.top, 1)
    }

    private var listActions: some View {
        HStack(spacing: 2) {
            listActionButton(
                help: "Find up to \(store.configuration.maxMessages) new inbox emails per connected account",
                disabled: !store.isConnected || (store.phase.isBusy && !store.phase.isScanning)
            ) {
                guard !store.phase.isBusy else { return }
                Task { await store.scanInbox() }
            } label: {
                BusyActionIcon(
                    systemName: "arrow.clockwise",
                    isBusy: store.phase.isScanning || store.backgroundSyncStatus != nil,
                    style: .spin
                )
            }

            listActionButton(
                help: "Run the current classifier again on every loaded email",
                disabled: !store.isConnected
                    || store.results.filter(\.isPending).isEmpty
                    || (store.phase.isBusy && !store.phase.isRecategorizing)
            ) {
                guard !store.phase.isBusy else { return }
                Task { await store.reclassifyLoaded() }
            } label: {
                BusyActionIcon(
                    systemName: "sparkles.rectangle.stack",
                    isBusy: store.phase.isRecategorizing,
                    style: .spin
                )
            }

            listActionButton(
                help: "Archive selected messages in this list (remove from Inbox)",
                disabled: store.currentBucketSelectedCount == 0 || store.phase.isBusy
            ) {
                Task { await store.applySelected(.archive) }
            } label: {
                Image(systemName: MailAction.archive.systemImage)
            }

            listActionButton(
                help: "Move selected messages in this list to Gmail Trash",
                disabled: store.currentBucketSelectedCount == 0 || store.phase.isBusy
            ) {
                Task { await store.applySelected(.delete) }
            } label: {
                Image(systemName: MailAction.delete.systemImage)
            }
        }
    }

    private func listActionButton<Label: View>(
        help: String,
        disabled: Bool,
        action: @escaping () -> Void,
        @ViewBuilder label: () -> Label
    ) -> some View {
        Button(action: action) {
            label()
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(disabled ? MailJayTheme.textTertiary : MailJayTheme.textSecondary)
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .help(help)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Spacer()
            Image(systemName: searchText.isEmpty ? "tray" : "magnifyingglass")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(MailJayTheme.textTertiary)
            Text(searchText.isEmpty ? "No classified mail" : "No results")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(MailJayTheme.textSecondary)
            Text(searchText.isEmpty ? "Connect Gmail, then scan your inbox." : "Try a different search.")
                .font(.system(size: 12))
                .foregroundStyle(MailJayTheme.textTertiary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private enum MessageRowMetrics {
    static let checkboxColumnWidth: CGFloat = 16
}

private struct MessageRow: View {
    let store: AppStore
    let result: TriageResult
    let isSelected: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Toggle("Select \(result.message.subject)", isOn: selectedBinding)
                .labelsHidden()
                .toggleStyle(.checkbox)
                .disabled(result.isApplied)
                .frame(width: MessageRowMetrics.checkboxColumnWidth, alignment: .center)
                .padding(.top, 2)

            ZStack {
                Circle()
                    .fill(MailAvatar.color(for: result.message.sender))
                    .frame(width: 32, height: 32)
                Text(MailAvatar.initials(from: result.message.sender))
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white)
            }

            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(MailAvatar.displayName(from: result.message.sender))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(MailJayTheme.textPrimary)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    if let date = result.message.date {
                        Text(date, format: .dateTime.month(.abbreviated).day().hour().minute())
                            .font(.system(size: 11))
                            .foregroundStyle(MailJayTheme.textTertiary)
                    }
                }
                Text(result.message.subject)
                    .font(.system(size: 13))
                    .foregroundStyle(MailJayTheme.textPrimary.opacity(0.88))
                    .lineLimit(1)
                Text(result.message.snippet)
                    .font(.system(size: 12))
                    .foregroundStyle(MailJayTheme.textSecondary)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: MailJayTheme.radiusMd, style: .continuous)
                .fill(isSelected ? MailJayTheme.accentSoft : Color.clear)
        )
        .contentShape(RoundedRectangle(cornerRadius: MailJayTheme.radiusMd, style: .continuous))
    }

    private var selectedBinding: Binding<Bool> {
        Binding(
            get: { result.isSelected },
            set: { store.setSelected(result.id, selected: $0) }
        )
    }
}

/// Action glyph that keeps animating while a long job runs (macOS 14+).
private struct BusyActionIcon: View {
    enum Style {
        case spin
        case pulse
    }

    let systemName: String
    let isBusy: Bool
    let style: Style

    var body: some View {
        switch style {
        case .spin:
            TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !isBusy)) { context in
                Image(systemName: systemName)
                    .rotationEffect(.degrees(isBusy ? spinDegrees(at: context.date) : 0))
            }
        case .pulse:
            Image(systemName: systemName)
                .symbolEffect(.pulse, options: .repeating, isActive: isBusy)
        }
    }

    private func spinDegrees(at date: Date) -> Double {
        date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 0.9) / 0.9 * 360
    }
}
