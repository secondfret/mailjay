import AppKit
import Sparkle
import SwiftUI

@main
struct MailJayApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var store = AppStore()
    private let updaterController = SPUStandardUpdaterController(
        startingUpdater: true,
        updaterDelegate: nil,
        userDriverDelegate: nil
    )

    var body: some Scene {
        WindowGroup("MailJay") {
            ContentView(store: store)
                .frame(minWidth: 940, minHeight: 620)
                .preferredColorScheme(.dark)
                .background(WindowConfigurator())
        }
        .defaultSize(width: 1160, height: 760)
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(after: .newItem) {
                Button("Fetch New Emails") {
                    Task { await store.scanInbox() }
                }
                .keyboardShortcut("r", modifiers: [.command, .shift])
                .disabled(!store.isConnected || store.phase.isBusy)

                Button("Re-categorize All Loaded") {
                    Task { await store.reclassifyLoaded() }
                }
                .keyboardShortcut("r", modifiers: [.command, .option])
                .disabled(!store.isConnected || store.results.filter(\.isPending).isEmpty || store.phase.isBusy)
            }

            CommandGroup(after: .pasteboard) {
                Button("Archive Selected") {
                    Task { await store.applySelected(.archive) }
                }
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(store.currentBucketSelectedCount == 0 || store.phase.isBusy)

                Button("Move Selected to Trash") {
                    Task { await store.applySelected(.delete) }
                }
                .keyboardShortcut(.delete, modifiers: .command)
                .disabled(store.currentBucketSelectedCount == 0 || store.phase.isBusy)
            }

            CommandGroup(after: .appInfo) {
                Button("Check for Updates...") {
                    updaterController.checkForUpdates(nil)
                }
            }

            CommandMenu("Navigate") {
                Button("Previous Category") {
                    store.navigateCategory(by: -1)
                }
                .keyboardShortcut(.upArrow, modifiers: .command)

                Button("Next Category") {
                    store.navigateCategory(by: 1)
                }
                .keyboardShortcut(.downArrow, modifiers: .command)

                Divider()

                Button("Previous Account") {
                    store.navigateAccount(by: -1)
                }
                .keyboardShortcut(.upArrow, modifiers: [.command, .shift])
                .disabled(store.accounts.count < 2)

                Button("Next Account") {
                    store.navigateAccount(by: 1)
                }
                .keyboardShortcut(.downArrow, modifiers: [.command, .shift])
                .disabled(store.accounts.count < 2)
            }
        }

        Settings {
            SettingsView(store: store)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.appearance = NSAppearance(named: .darkAqua)
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
}

/// Forces an opaque flat window chrome so Tahoe liquid-glass sidebars/materials don't leak through.
private struct WindowConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { configure(view) }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async { configure(nsView) }
    }

    private func configure(_ view: NSView) {
        guard let window = view.window else { return }
        window.appearance = NSAppearance(named: .darkAqua)
        window.isOpaque = true
        window.backgroundColor = MailJayTheme.nsCanvas
        window.titlebarAppearsTransparent = true
        window.hasShadow = true
    }
}
