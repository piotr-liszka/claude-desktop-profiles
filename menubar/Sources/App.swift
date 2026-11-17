import AppKit
import SwiftUI

@main
struct ProfilesMenuApp: App {
    @StateObject private var store = ProfileStore()

    var body: some Scene {
        MenuBarExtra {
            ContentView()
                .environmentObject(store)
        } label: {
            // The badge marks profiles that are older than the installed app.
            Image(systemName: store.outdated.isEmpty ? "person.crop.circle" : "person.crop.circle.badge.exclamationmark")
        }
        .menuBarExtraStyle(.window)
    }
}

struct ContentView: View {
    @EnvironmentObject var store: ProfileStore

    var body: some View {
        VStack(spacing: 0) {
            page
        }
        .frame(width: 380)
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
            store.refreshSoon()
        }
    }

    @ViewBuilder private var page: some View {
        switch store.page {
        case .home:
            HomeView()
        case .detail(let label):
            if let p = store.profile(label) { DetailView(profile: p) } else { HomeView() }
        case .add:
            AddView()
        case .icon(let label):
            if let p = store.profile(label) { IconView(profile: p) } else { HomeView() }
        case .remove(let label):
            if let p = store.profile(label) { RemoveView(profile: p) } else { HomeView() }
        case .output(let title, let text):
            OutputView(title: title, text: text)
        }
    }
}
