import AppKit
import SwiftUI

struct HomeView: View {
    @EnvironmentObject var store: ProfileStore

    var body: some View {
        VStack(spacing: 0) {
            HomeHeader()
            ScrollView {
                VStack(spacing: 10) {
                    if let banner = store.banner { BannerView(banner: banner) }
                    if let error = store.loadError { LoadErrorCard(error: error) }
                    if !store.outdated.isEmpty { UpdatesCard() }
                    ProfilesCard()
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
            }
            .frame(minHeight: 160, maxHeight: 560)
            .fixedSize(horizontal: false, vertical: true)
            Footer()
        }
    }
}

struct HomeHeader: View {
    @EnvironmentObject var store: ProfileStore
    @State private var searching = false

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                if let app = store.listing?.app {
                    BundleIcon(path: app.path, size: 34)
                } else {
                    Image(systemName: "person.crop.circle").font(.system(size: 28))
                }
                VStack(alignment: .leading, spacing: -2) {
                    Text(store.appName)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Text("Profiles")
                        .font(.system(size: 20, weight: .bold))
                }
                Spacer()
                IconButton(symbol: "magnifyingglass", help: "Search") {
                    searching.toggle()
                    if !searching { store.search = "" }
                }
                IconButton(symbol: "plus", help: "New profile") { store.page = .add }
                SettingsMenu()
            }
            if searching {
                TextField("Search profiles", text: $store.search)
                    .textFieldStyle(.roundedBorder)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 10)
    }
}

struct SettingsMenu: View {
    @EnvironmentObject var store: ProfileStore

    var body: some View {
        Menu {
            Button("Refresh") { Task { await store.refresh() } }
            if let dest = store.listing?.dest {
                Button("Open Profiles Folder") { store.openFolder(dest) }
            }
            Divider()
            Button("Create Updater App") { store.installUpdater() }
            Button("Diagnostics") { store.showDoctor() }
            Toggle("Open at Login", isOn: $store.opensAtLogin)
            Divider()
            Text("claude-profiles \(store.listing?.version ?? "")")
            Button("Quit Profiles Menu") { NSApp.terminate(nil) }
        } label: {
            Image(systemName: "gearshape")
                .font(.system(size: 12))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .foregroundStyle(.secondary)
    }
}

struct LoadErrorCard: View {
    let error: String

    var body: some View {
        Card {
            Label("Could not list the profiles", systemImage: "exclamationmark.triangle")
                .font(.system(size: 13, weight: .semibold))
            Text(error)
                .font(.system(size: 11, design: .monospaced))
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// Like an IDE launcher's "Installed" card: profiles whose copy is older than the app.
struct UpdatesCard: View {
    @EnvironmentObject var store: ProfileStore

    var body: some View {
        Card {
            HStack {
                SectionTitle(text: "Updates", count: store.outdated.count)
                Spacer()
                if store.outdated.count > 1 {
                    Button("Update all") { store.updateAll() }
                        .buttonStyle(.link)
                        .disabled(store.globalBusy != nil)
                }
            }
            if let installed = store.listing?.app?.bundle {
                Text("\(store.appName) \(installed.display) is installed. These profiles still run an older copy.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ForEach(store.outdated) { p in
                UpdateRow(profile: p)
            }
            if store.outdated.contains(where: \.running) {
                Text("Open profiles are quit and reopened.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct UpdateRow: View {
    @EnvironmentObject var store: ProfileStore
    let profile: Profile

    var body: some View {
        HStack(spacing: 12) {
            ProfileIcon(profile: profile, size: 40)
            VStack(alignment: .leading, spacing: 3) {
                Text(profile.name)
                    .font(.system(size: 14, weight: .semibold))
                HStack(spacing: 4) {
                    Text(profile.versionChange.from)
                    Image(systemName: "arrow.right").font(.system(size: 9, weight: .semibold))
                    Text(profile.versionChange.to).foregroundStyle(Color.accentColor)
                }
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            }
            Spacer()
            if let status = store.busy[profile.label] {
                BusyLabel(text: status)
            } else {
                Button("Update") { store.update(profile) }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
            }
        }
    }
}

struct ProfilesCard: View {
    @EnvironmentObject var store: ProfileStore

    var body: some View {
        Card {
            HStack {
                SectionTitle(text: "Profiles", count: store.profiles.count)
                Spacer()
                Button("New profile") { store.page = .add }
                    .buttonStyle(.link)
            }
            if store.listing != nil && store.profiles.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("No profiles yet. A profile is a separate \(store.appName) with its own account, data and Dock icon.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("Create a profile") { store.page = .add }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                }
            } else if store.filteredProfiles.isEmpty && !store.profiles.isEmpty {
                Text("No profile matches \"\(store.search)\".")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            VStack(spacing: 2) {
                ForEach(store.filteredProfiles) { p in
                    ProfileRow(profile: p)
                }
            }
            .padding(.horizontal, -6)
        }
    }
}

struct ProfileRow: View {
    @EnvironmentObject var store: ProfileStore
    let profile: Profile
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 12) {
            ProfileIcon(profile: profile)
            VStack(alignment: .leading, spacing: 2) {
                Text(profile.name)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                subtitle
            }
            Spacer(minLength: 4)
            if let status = store.busy[profile.label] {
                BusyLabel(text: status)
            } else {
                if hovering || profile.running {
                    Button(profile.running ? "Show" : "Open") { store.launch(profile) }
                        .controlSize(.small)
                }
                ProfileActionsMenu(profile: profile)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.primary.opacity(hovering ? 0.06 : 0))
        )
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture { store.page = .detail(profile.label) }
    }

    private var subtitle: some View {
        HStack(spacing: 4) {
            Text(profile.running ? "Running" : "Not running")
            if let v = profile.bundle {
                Text("·")
                Text(v.display)
            }
            if !profile.isCopy {
                Text("·")
                Text("launcher")
            }
            if profile.outdated {
                Text("·")
                Text("update available").foregroundStyle(Color.accentColor)
            }
        }
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
        .lineLimit(1)
    }
}

struct ProfileActionsMenu: View {
    @EnvironmentObject var store: ProfileStore
    let profile: Profile

    var body: some View {
        Menu {
            Button(profile.running ? "Show" : "Open") { store.launch(profile) }
            if profile.running { Button("Quit") { store.quit(profile) } }
            if profile.outdated { Button("Update to \(profile.versionChange.to)") { store.update(profile) } }
            Divider()
            Button("Details") { store.page = .detail(profile.label) }
            Button("Show App in Finder") { store.reveal(profile.path) }
            Button("Open Data Folder") { store.openFolder(profile.dataDir) }
                .disabled(!ProfileStore.exists(profile.dataDir))
            if !profile.configDir.isEmpty {
                Button("Open Claude Code Folder") { store.openFolder(profile.configDir) }
                    .disabled(!ProfileStore.exists(profile.configDir))
            }
            Button("Copy Terminal Command") { store.copyEnv(profile) }
            Divider()
            if profile.isCopy {
                Button("Change Icon...") {
                    store.iconDraft = IconChoice()
                    store.page = .icon(profile.label)
                }
            }
            Button("Remove...") {
                store.purge = false
                store.purgeConfirm = ""
                store.page = .remove(profile.label)
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 12, weight: .semibold))
                .rotationEffect(.degrees(90))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .foregroundStyle(.secondary)
    }
}

struct BusyLabel: View {
    let text: String

    var body: some View {
        HStack(spacing: 6) {
            ProgressView().controlSize(.small)
            Text(text)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }
}

struct Footer: View {
    @EnvironmentObject var store: ProfileStore

    var body: some View {
        VStack(spacing: 0) {
            Divider()
            HStack {
                if let status = store.globalBusy {
                    BusyLabel(text: status)
                } else if let app = store.listing?.app {
                    Text("\(app.name) \(app.bundle?.display ?? "") installed")
                } else if store.listing != nil {
                    Text("\(store.appName) was not found in /Applications")
                }
                Spacer()
                if let dest = store.listing?.dest {
                    Button {
                        store.openFolder(dest)
                    } label: {
                        Text((dest as NSString).abbreviatingWithTildeInPath)
                    }
                    .buttonStyle(.plain)
                    .help("Open the folder that holds the profiles")
                }
            }
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
    }
}
