import AppKit
import SwiftUI

struct OnboardingView: View {
    @Bindable var store: AppStore
    let onDismiss: () -> Void

    @State private var step = 0
    @State private var stepDirection = 1
    @State private var jevAPIKey = ""

    private let totalSteps = 5

    private let cardCornerRadius: CGFloat = 20
    private let cardWidth: CGFloat = 480
    private let heroHeight: CGFloat = 280

    var body: some View {
        ZStack {
            Color.black.opacity(0.55)
                .ignoresSafeArea()
                .onTapGesture { /* absorb */ }

            ZStack(alignment: .topTrailing) {
                VStack(spacing: 0) {
                    ZStack {
                        stepContent
                            .id(step)
                            .transition(stepTransition)
                    }
                    .clipped()
                    .animation(.spring(response: 0.42, dampingFraction: 0.86), value: step)

                    footer
                        .padding(.horizontal, 24)
                        .padding(.bottom, 18)
                        .padding(.top, 4)
                }

                closeButton
                    .padding(.top, 12)
                    .padding(.trailing, 12)
            }
            .frame(width: cardWidth)
            .fixedSize(horizontal: false, vertical: true)
            .background(MailJayTheme.pane)
            .clipShape(RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous)
                    .stroke(MailJayTheme.hairline, lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.45), radius: 40, y: 18)
        }
        .onAppear {
            jevAPIKey = store.configuration.jevAPIKey
        }
        .onChange(of: store.isConnected) { _, connected in
            if connected, step == 3 {
                goTo(4)
            }
        }
    }

    private var isIllustratedStep: Bool { step < 3 }

    private var closeButton: some View {
        Button(action: finish) {
            Image(systemName: "xmark")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(isIllustratedStep ? Color.black.opacity(0.5) : MailJayTheme.textSecondary)
                .frame(width: 28, height: 28)
                .background {
                    if isIllustratedStep {
                        Circle().fill(.white.opacity(0.85))
                    } else {
                        Circle().fill(MailJayTheme.card)
                    }
                }
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help("Close")
    }

    @ViewBuilder
    private var stepContent: some View {
        switch step {
        case 0:
            illustratedStep(
                imageName: "Step1",
                text: "MailJay automatically organizes your email into categories. You'll start with some default categories and can make your own by clicking \"Customize Categories\" in the sidebar."
            )
        case 1:
            illustratedStep(
                imageName: "Step2",
                text: "For now, MailJay doesn't send emails! Use your normal email app for that. It's just to help you quickly archive and delete what's not important."
            )
        case 2:
            illustratedStep(
                imageName: "Step3",
                text: "MailJay uses Jev. It's super cheap and fast. You'll need your own API Key."
            ) {
                VStack(spacing: 10) {
                    SecureField("TypeSafe Jev API key", text: $jevAPIKey)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: MailJayTheme.radiusSm, style: .continuous)
                                .fill(MailJayTheme.card)
                        )
                        .onChange(of: jevAPIKey) { _, _ in
                            persistAPIKeyIfNeeded()
                        }

                    HStack(spacing: 0) {
                        Text("Get a Jev API Key ")
                            .font(.system(size: 13))
                            .foregroundStyle(MailJayTheme.textSecondary)
                        Link("here", destination: URL(string: "https://docs.typesafe.ai/introduction")!)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(MailJayTheme.accent)
                            .underline()
                        Text(".")
                            .font(.system(size: 13))
                            .foregroundStyle(MailJayTheme.textSecondary)
                    }
                }
            }
        case 3:
            connectStep
        default:
            howToUseStep
        }
    }

    private func illustratedStep<Extra: View>(
        imageName: String,
        text: String,
        @ViewBuilder extra: () -> Extra = { EmptyView() }
    ) -> some View {
        VStack(spacing: 0) {
            onboardingImage(imageName)
            VStack(spacing: 12) {
                Text(text)
                    .font(.system(size: 14))
                    .foregroundStyle(MailJayTheme.textSecondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
                extra()
            }
            .padding(.horizontal, 28)
            .padding(.top, 16)
            .padding(.bottom, 12)
        }
    }

    private var connectStep: some View {
        VStack(spacing: 16) {
            Image(systemName: "envelope.badge.shield.half.filled")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(MailJayTheme.accent)
            Text("MailJay only works with Gmail. Connect a Gmail account to get started.")
                .font(.system(size: 14))
                .foregroundStyle(MailJayTheme.textSecondary)
                .multilineTextAlignment(.center)
                .lineSpacing(3)
                .padding(.horizontal, 28)

            if store.isConnected, let email = store.activeAccountEmail {
                HStack(spacing: 10) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color(hex: 0x10B981))
                    Text(email)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(MailJayTheme.textPrimary)
                        .lineLimit(1)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: MailJayTheme.radiusSm, style: .continuous)
                        .fill(MailJayTheme.card)
                )
            } else {
                Button {
                    Task { await store.addAccount() }
                } label: {
                    HStack(spacing: 8) {
                        if store.phase.isBusy {
                            ProgressView()
                                .controlSize(.small)
                        }
                        Text(store.phase.isBusy ? "Waiting for Google…" : "Connect Gmail")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: MailJayTheme.radiusSm, style: .continuous)
                            .fill(MailJayTheme.accent)
                    )
                }
                .buttonStyle(.plain)
                .disabled(store.phase.isBusy || !hasAPIKey)

                if !hasAPIKey {
                    Text("Add your Jev API key on the previous step first.")
                        .font(.system(size: 12))
                        .foregroundStyle(MailJayTheme.textTertiary)
                }

                if case .failed(let message) = store.phase {
                    Text(message)
                        .font(.system(size: 12))
                        .foregroundStyle(Color(hex: 0xEF4444).opacity(0.9))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 28)
                }
            }
        }
        .padding(.top, 44)
        .padding(.bottom, 8)
    }

    private var howToUseStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("How to use MailJay")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(MailJayTheme.textPrimary)
                .frame(maxWidth: .infinity)

            VStack(spacing: 8) {
                actionRow(
                    systemImage: "arrow.clockwise",
                    title: "Fetch new emails",
                    keys: ["⇧", "⌘", "R"]
                )
                actionRow(
                    systemImage: "envelope.stack",
                    title: "Re-categorize loaded mail",
                    keys: ["⌥", "⌘", "R"]
                )
                actionRow(
                    systemImage: MailAction.archive.systemImage,
                    title: "Archive selected",
                    keys: ["⌘", "↩"]
                )
                actionRow(
                    systemImage: MailAction.delete.systemImage,
                    title: "Delete selected",
                    keys: ["⌘", "⌫"]
                )
            }
            .padding(.horizontal, 24)
        }
        .padding(.top, 44)
        .padding(.bottom, 8)
    }

    private func actionRow(systemImage: String, title: String, keys: [String]) -> some View {
        HStack(spacing: 14) {
            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(MailJayTheme.textSecondary)
                .frame(width: 28, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(MailJayTheme.card)
                )
            Text(title)
                .font(.system(size: 13))
                .foregroundStyle(MailJayTheme.textPrimary)
            Spacer(minLength: 8)
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
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: MailJayTheme.radiusSm, style: .continuous)
                .fill(MailJayTheme.card.opacity(0.55))
        )
    }

    private var footer: some View {
        HStack(spacing: 16) {
            stepDots
            Spacer()
            if step > 0 {
                Button("Back") { goTo(step - 1) }
                    .buttonStyle(.plain)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(MailJayTheme.textSecondary)
            }
            primaryButton
        }
    }

    private var stepDots: some View {
        HStack(spacing: 6) {
            ForEach(0..<totalSteps, id: \.self) { index in
                Capsule()
                    .fill(index == step ? MailJayTheme.accent : MailJayTheme.textTertiary.opacity(0.55))
                    .frame(width: index == step ? 16 : 6, height: 6)
                    .animation(.spring(response: 0.35, dampingFraction: 0.8), value: step)
            }
        }
    }

    @ViewBuilder
    private var primaryButton: some View {
        let label: String = {
            if step == totalSteps - 1 { return "Done" }
            if step == 3, !store.isConnected { return "Skip" }
            return "Next"
        }()

        Button {
            if step == totalSteps - 1 {
                finish()
            } else if step == 3, !store.isConnected {
                goTo(4)
            } else {
                if step == 2 { persistAPIKeyIfNeeded() }
                goTo(step + 1)
            }
        } label: {
            Text(label)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: MailJayTheme.radiusSm, style: .continuous)
                        .fill(MailJayTheme.accent)
                )
        }
        .buttonStyle(.plain)
        .disabled(step == 3 && store.phase.isBusy)
    }

    private var stepTransition: AnyTransition {
        .asymmetric(
            insertion: .move(edge: stepDirection > 0 ? .trailing : .leading).combined(with: .opacity),
            removal: .move(edge: stepDirection > 0 ? .leading : .trailing).combined(with: .opacity)
        )
    }

    private var hasAPIKey: Bool {
        !jevAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !store.configuration.jevAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func onboardingImage(_ name: String) -> some View {
        Group {
            if let nsImage = NSImage(named: name) ?? bundleImage(named: name) {
                Image(nsImage: nsImage)
                    .resizable()
                    .scaledToFill()
            } else {
                Color.white
                    .overlay {
                        Image(systemName: "photo")
                            .foregroundStyle(MailJayTheme.textTertiary)
                    }
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: heroHeight)
        .clipped()
        .background(Color.white)
    }

    private func bundleImage(named name: String) -> NSImage? {
        // Never touch Bundle.module here: SPM's Bundle.module asserts when its
        // resource bundle isn't discoverable in a packaged .app, and that kills
        // first-launch onboarding on a fresh Mac.
        let candidates: [URL?] = [
            Bundle.main.url(forResource: name, withExtension: "png", subdirectory: "Onboarding"),
            Bundle.main.url(forResource: name, withExtension: "png"),
            Bundle.main.resourceURL?
                .appending(path: "Onboarding/\(name).png", directoryHint: .notDirectory),
            Bundle.main.bundleURL
                .appending(path: "Contents/Resources/Onboarding/\(name).png", directoryHint: .notDirectory)
        ]
        for case let url? in candidates {
            if let image = NSImage(contentsOf: url) { return image }
        }
        return nil
    }

    private func goTo(_ next: Int) {
        let clamped = min(max(next, 0), totalSteps - 1)
        guard clamped != step else { return }
        stepDirection = clamped > step ? 1 : -1
        withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) {
            step = clamped
        }
    }

    private func persistAPIKeyIfNeeded() {
        let trimmed = jevAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        var config = store.configuration
        guard config.jevAPIKey != trimmed else { return }
        config.jevAPIKey = trimmed
        try? store.saveConfiguration(config)
    }

    private func finish() {
        persistAPIKeyIfNeeded()
        onDismiss()
    }
}
