import SwiftUI

struct SidebarView: View {
    @Bindable var store: AppStore

    var body: some View {
        VStack(spacing: 0) {
            brandHeader
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    accountsSection

                    sectionLabel("Mailbox")
                        .padding(.top, store.accounts.isEmpty ? 4 : 10)
                    ForEach(primaryItems, id: \.self) { categoryID in
                        sidebarRow(categoryID)
                    }

                    if !categoryItems.isEmpty {
                        sectionLabel("Categories")
                            .padding(.top, 14)
                        ForEach(categoryItems, id: \.self) { categoryID in
                            sidebarRow(categoryID)
                        }
                    }

                    if store.sidebarItems.contains(CategoryID.uncertain) {
                        sectionLabel("Review")
                            .padding(.top, 14)
                        sidebarRow(CategoryID.uncertain)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 16)
            }
            footer
        }
        .background(MailJayTheme.sidebar)
        .sheet(isPresented: $store.isPresentingCategoryEditor) {
            CategoryEditorView(store: store)
        }
        .task {
            await store.resolveActiveAccountEmailIfNeeded()
        }
    }

    private var primaryItems: [String] {
        store.sidebarItems.filter { $0 == CategoryID.all }
    }

    private var categoryItems: [String] {
        store.sidebarItems.filter { $0 != CategoryID.all && $0 != CategoryID.uncertain }
    }

    private var brandHeader: some View {
        HStack(spacing: 8) {
            Text("MailJay")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(MailJayTheme.textPrimary)
            Spacer()
        }
        .padding(.horizontal, 18)
        .padding(.top, 18)
        .padding(.bottom, 8)
    }

    private var accountsSection: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(store.accounts) { account in
                accountRow(account)
            }

            Button {
                Task { await store.addAccount() }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "plus")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(MailJayTheme.textTertiary)
                        .frame(width: 16)
                    Text(store.accounts.isEmpty ? "Connect Gmail" : "Add account")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(MailJayTheme.textTertiary)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(store.phase.isBusy)
            .help("Connect another Gmail account")
        }
    }

    private func accountRow(_ account: MailAccount) -> some View {
        let isActive = account.email == store.activeAccountEmail

        return Button {
            store.switchAccount(to: account.email)
        } label: {
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(MailAvatar.color(for: account.email).opacity(isActive ? 1 : 0.7))
                        .frame(width: 18, height: 18)
                    Text(MailAvatar.initials(from: account.email))
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.white)
                }
                .frame(width: 16)

                Text(shortAccountLabel(account.email))
                    .font(.system(size: 13, weight: isActive ? .semibold : .regular))
                    .foregroundStyle(isActive ? MailJayTheme.textPrimary : MailJayTheme.textSecondary)
                    .lineLimit(1)

                Spacer(minLength: 0)

                if isActive {
                    Circle()
                        .fill(MailJayTheme.accent)
                        .frame(width: 6, height: 6)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: MailJayTheme.radiusSm, style: .continuous)
                    .fill(isActive ? MailJayTheme.card : Color.clear)
            )
            .contentShape(RoundedRectangle(cornerRadius: MailJayTheme.radiusSm, style: .continuous))
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Remove Account…", role: .destructive) {
                store.removeAccount(account.email)
            }
        }
        .help(account.email)
    }

    private func shortAccountLabel(_ email: String) -> String {
        if let at = email.firstIndex(of: "@") {
            return String(email[..<at])
        }
        return email
    }

    private func sectionLabel(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.system(size: 10, weight: .semibold))
            .tracking(0.6)
            .foregroundStyle(MailJayTheme.textTertiary)
            .padding(.horizontal, 10)
            .padding(.bottom, 4)
            .padding(.top, 2)
    }

    private func sidebarRow(_ categoryID: String) -> some View {
        let isSelected = store.selectedCategoryID == categoryID
        let count = store.count(forCategoryID: categoryID)

        return Button {
            store.selectCategory(categoryID)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: store.systemImage(forCategoryID: categoryID))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(isSelected ? Color.white : MailJayTheme.textSecondary)
                    .frame(width: 16)
                Text(store.title(forCategoryID: categoryID))
                    .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? Color.white : MailJayTheme.textPrimary)
                    .lineLimit(1)
                Spacer(minLength: 0)
                if count > 0 {
                    Text(count, format: .number)
                        .font(.system(size: 11, weight: .medium).monospacedDigit())
                        .foregroundStyle(isSelected ? Color.white.opacity(0.85) : MailJayTheme.textSecondary)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: MailJayTheme.radiusSm, style: .continuous)
                    .fill(isSelected ? MailJayTheme.accent : Color.clear)
            )
            .contentShape(RoundedRectangle(cornerRadius: MailJayTheme.radiusSm, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var footer: some View {
        VStack(spacing: 0) {
            footerRow(title: "Customize Categories", systemImage: "slider.horizontal.3") {
                store.isPresentingCategoryEditor = true
            }
            .disabled(!store.isConnected || store.phase.isBusy)

            footerDivider

            SettingsLink {
                footerLabel(title: "Settings", systemImage: "gearshape")
            }
            .buttonStyle(.plain)

            footerDivider

            footerRow(title: "Help", systemImage: "questionmark.circle") {
                store.presentOnboarding()
            }
            .help("Show onboarding")
        }
        .background(
            RoundedRectangle(cornerRadius: MailJayTheme.radiusSm, style: .continuous)
                .fill(MailJayTheme.sidebar)
        )
        .padding(14)
        .background(MailJayTheme.sidebar)
    }

    private var footerDivider: some View {
        Rectangle()
            .fill(MailJayTheme.hairline)
            .frame(height: 1)
            .padding(.leading, 36)
    }

    private func footerRow(title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            footerLabel(title: title, systemImage: systemImage)
        }
        .buttonStyle(.plain)
    }

    private func footerLabel(title: String, systemImage: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(MailJayTheme.textTertiary)
                .frame(width: 16)
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(MailJayTheme.textSecondary)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
    }
}
