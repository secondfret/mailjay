import SwiftUI

struct ContentView: View {
    @Bindable var store: AppStore

    var body: some View {
        ZStack {
            HSplitView {
                SidebarView(store: store)
                    .frame(minWidth: 200, idealWidth: MailJayTheme.sidebarWidth, maxWidth: 280)

                MessageListView(store: store)
                    .frame(minWidth: MailJayTheme.listMinWidth, idealWidth: 340)

                Group {
                    if let result = store.selectedResult {
                        MessageDetailView(store: store, result: result)
                    } else {
                        WelcomeView(store: store)
                    }
                }
                .frame(minWidth: 420)
            }

            if store.isPresentingOnboarding {
                OnboardingView(store: store) {
                    store.dismissOnboarding()
                }
                .transition(.opacity)
                .zIndex(1)
            }
        }
        .background(MailJayTheme.canvas)
        .preferredColorScheme(.dark)
        .toolbarBackground(MailJayTheme.canvas, for: .windowToolbar)
        .toolbarBackground(.visible, for: .windowToolbar)
        .animation(.easeInOut(duration: 0.22), value: store.isPresentingOnboarding)
        .alert("MailJay", isPresented: errorPresented) {
            Button("OK") { store.phase = store.isConnected ? .ready : .disconnected }
        } message: {
            Text(store.phase.errorMessage ?? "Unknown error")
        }
    }

    private var errorPresented: Binding<Bool> {
        Binding(
            get: { store.phase.errorMessage != nil },
            set: { if !$0 { store.phase = store.isConnected ? .ready : .disconnected } }
        )
    }
}
