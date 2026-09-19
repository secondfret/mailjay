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
                    isBusy: store.phase.isScanning || store.backgroundSyncStatus != nil
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
                    systemName: "envelope.stack",
                    isBusy: store.phase.isRecategorizing
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
        let content = listEmptyContent
        return VStack(spacing: 10) {
            Spacer()
            Image(systemName: content.symbol)
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(MailJayTheme.textTertiary)
            Text(content.title)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(MailJayTheme.textSecondary)
            Text(content.message)
                .font(.system(size: 12))
                .foregroundStyle(MailJayTheme.textTertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var listEmptyContent: (symbol: String, title: String, message: String) {
        if !searchText.isEmpty {
            return ("magnifyingglass", "No results", "Try a different search.")
        }
        if !store.isConnected {
            return ("tray", "No account connected", "Connect Gmail from the sidebar to get started.")
        }
        if store.phase.isScanning || store.backgroundSyncStatus != nil {
            return ("arrow.clockwise", "Scanning inbox…", "New mail will show up here as it’s classified.")
        }
        if store.results.isEmpty {
            return ("tray", "Inbox not scanned yet", "Use Scan Inbox or the refresh button to classify recent mail.")
        }
        let pending = store.results.filter(\.isPending)
        if pending.isEmpty {
            return ("checkmark.circle", "You’re caught up", "Nothing left to triage. Scan again anytime for new mail.")
        }
        if store.selectedCategoryID == CategoryID.uncertain {
            return ("questionmark.circle", "Nothing needs review", "Low-confidence messages will appear here.")
        }
        let categoryTitle = store.title(forCategoryID: store.selectedCategoryID)
        return ("tray", "No mail in \(categoryTitle)", "Try another category, or scan for new mail.")
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

/// Idle: action glyph. Busy: dotted squircle with a few randomly lit dots cycling.
private struct BusyActionIcon: View {
    let systemName: String
    let isBusy: Bool

    var body: some View {
        Group {
            if isBusy {
                DottedBusyIndicator()
            } else {
                Image(systemName: systemName)
            }
        }
        .frame(width: 14, height: 14)
    }
}

/// Soft nod to `app.background.dotted`: mostly dim dots, a few lit ones that reshuffle.
private struct DottedBusyIndicator: View {
    private static let columns = 6
    private static let litCount = 5
    private static let tickDuration = 0.084

    /// 6×6 with corners removed (matches the SF Symbol silhouette).
    private static let positions: [(row: Int, col: Int)] = {
        (0..<columns).flatMap { row in
            (0..<columns).compactMap { col in
                let isCorner = (row == 0 || row == columns - 1) && (col == 0 || col == columns - 1)
                return isCorner ? nil : (row, col)
            }
        }
    }()

    var body: some View {
        TimelineView(.animation(minimumInterval: Self.tickDuration, paused: false)) { context in
            let lit = Self.litIndices(at: context.date)
            Canvas { context, size in
                let cell = size.width / CGFloat(Self.columns)
                for (index, position) in Self.positions.enumerated() {
                    let isInner = (1...4).contains(position.row) && (1...4).contains(position.col)
                    let diameter = cell * (isInner ? 0.42 : 0.30)
                    let origin = CGPoint(
                        x: (CGFloat(position.col) + 0.5) * cell - diameter / 2,
                        y: (CGFloat(position.row) + 0.5) * cell - diameter / 2
                    )
                    let rect = CGRect(origin: origin, size: CGSize(width: diameter, height: diameter))
                    context.opacity = lit.contains(index) ? 1.0 : 0.22
                    context.fill(Path(ellipseIn: rect), with: .foreground)
                }
            }
        }
        .accessibilityLabel("Working")
    }

    private static func litIndices(at date: Date) -> Set<Int> {
        let tick = Int(date.timeIntervalSinceReferenceDate / tickDuration)
        var generator = SeededGenerator(seed: UInt64(truncatingIfNeeded: tick) &+ 1)
        return Set((0..<positions.count).shuffled(using: &generator).prefix(litCount))
    }
}

/// Deterministic RNG so TimelineView redraws stay stable within a tick.
private struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed == 0 ? 0xDEAD_BEEF : seed
    }

    mutating func next() -> UInt64 {
        state = state &+ 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
