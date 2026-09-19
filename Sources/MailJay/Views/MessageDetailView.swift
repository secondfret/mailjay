import SwiftUI

struct MessageDetailView: View {
    let store: AppStore
    let result: TriageResult

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(result.message.subject)
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(MailJayTheme.textPrimary)
                .textSelection(.enabled)
                .padding(.horizontal, 4)

            messageCard
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            suggestionStrip
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(MailJayTheme.canvas)
    }

    private var messageCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    Circle()
                        .fill(MailAvatar.color(for: result.message.sender))
                        .frame(width: 40, height: 40)
                    Text(MailAvatar.initials(from: result.message.sender))
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(MailAvatar.displayName(from: result.message.sender))
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(MailJayTheme.accent)
                        .textSelection(.enabled)
                    Text(result.message.sender)
                        .font(.system(size: 12))
                        .foregroundStyle(MailJayTheme.textSecondary)
                        .lineLimit(1)
                        .textSelection(.enabled)
                }

                Spacer(minLength: 8)

                if let date = result.message.date {
                    Text(date, format: .dateTime.month(.abbreviated).day().hour().minute())
                        .font(.system(size: 12))
                        .foregroundStyle(MailJayTheme.textTertiary)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)
            .padding(.bottom, 14)

            if let html = result.message.htmlBody, !html.isEmpty {
                EmailHTMLView(html: html, loadRemoteImages: store.configuration.loadRemoteImages)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    Text(result.message.body.isEmpty ? result.message.snippet : result.message.body)
                        .font(.system(size: 14))
                        .foregroundStyle(MailJayTheme.textPrimary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 20)
                        .padding(.bottom, 20)
                }
            }
        }
        .background(
            RoundedRectangle(cornerRadius: MailJayTheme.radiusLg, style: .continuous)
                .fill(MailJayTheme.card)
        )
        .clipShape(RoundedRectangle(cornerRadius: MailJayTheme.radiusLg, style: .continuous))
    }

    private var suggestionStrip: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "bird.circle.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(MailJayTheme.accent)
                Text("\(suggestionTitle)’s suggestion")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(MailJayTheme.textSecondary)
                Spacer()
                Text(result.confidence, format: .percent.precision(.fractionLength(0)))
                    .font(.system(size: 12, weight: .medium).monospacedDigit())
                    .foregroundStyle(MailJayTheme.textTertiary)
            }

            Picker("Category", selection: bucketBinding) {
                ForEach(store.categories) { category in
                    Label(category.title, systemImage: category.systemImage).tag(category.id)
                }
                Label(
                    MailCategory.uncertain.title,
                    systemImage: MailCategory.uncertain.systemImage
                )
                .tag(CategoryID.uncertain)
            }
            .disabled(result.isApplied)
            .labelsHidden()

            VStack(spacing: 6) {
                ForEach(result.probabilities.sorted { $0.value > $1.value }.prefix(4), id: \.key) { categoryID, probability in
                    HStack(spacing: 8) {
                        Text(store.title(forCategoryID: categoryID))
                            .font(.system(size: 11))
                            .foregroundStyle(MailJayTheme.textSecondary)
                            .frame(width: 110, alignment: .leading)
                            .lineLimit(1)
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule()
                                    .fill(MailJayTheme.cardElevated)
                                Capsule()
                                    .fill(MailJayTheme.accent.opacity(0.7))
                                    .frame(width: max(4, geo.size.width * probability))
                            }
                        }
                        .frame(height: 5)
                        Text(probability, format: .percent.precision(.fractionLength(0)))
                            .font(.system(size: 11).monospacedDigit())
                            .foregroundStyle(MailJayTheme.textTertiary)
                            .frame(width: 36, alignment: .trailing)
                    }
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: MailJayTheme.radiusMd, style: .continuous)
                .fill(MailJayTheme.card.opacity(0.72))
        )
    }

    private var bucketBinding: Binding<String> {
        Binding(
            get: { result.bucket },
            set: { store.move(result.id, to: $0) }
        )
    }

    private var suggestionTitle: String { "Jev" }
}
