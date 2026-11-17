import AppKit
import SwiftUI

// Wraps a page's content so long pages scroll inside the menu bar window.
struct PageBody<Content: View>: View {
    @EnvironmentObject var store: ProfileStore
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                if let banner = store.banner { BannerView(banner: banner) }
                content
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 12)
        }
        .frame(minHeight: 160, maxHeight: 560)
        .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - Details

struct DetailView: View {
    @EnvironmentObject var store: ProfileStore
    let profile: Profile

    var body: some View {
        VStack(spacing: 0) {
            PageHeader(title: "Profiles")
            PageBody {
                DetailSummary(profile: profile)
                DetailLocations(profile: profile)
                DetailTerminal(profile: profile)
                HStack {
                    if profile.isCopy {
                        Button("Change Icon...") {
                            store.iconDraft = IconChoice()
                            store.page = .icon(profile.label)
                        }
                    }
                    Spacer()
                    Button("Remove...") {
                        store.purge = false
                        store.purgeConfirm = ""
                        store.page = .remove(profile.label)
                    }
                    .foregroundStyle(Color.red)
                }
                .controlSize(.small)
                .disabled(store.busy[profile.label] != nil)
            }
            Footer()
        }
    }
}

struct DetailSummary: View {
    @EnvironmentObject var store: ProfileStore
    let profile: Profile

    var body: some View {
        Card {
            HStack(spacing: 14) {
                ProfileIcon(profile: profile, size: 64)
                VStack(alignment: .leading, spacing: 4) {
                    Text(profile.name)
                        .font(.system(size: 17, weight: .bold))
                    Text(statusLine)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    if profile.outdated {
                        HStack(spacing: 4) {
                            Text(profile.versionChange.from)
                            Image(systemName: "arrow.right").font(.system(size: 9, weight: .semibold))
                            Text(profile.versionChange.to).foregroundStyle(Color.accentColor)
                        }
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    }
                }
            }
            if let status = store.busy[profile.label] {
                BusyLabel(text: status)
            } else {
                HStack(spacing: 8) {
                    Button(profile.running ? "Show" : "Open") { store.launch(profile) }
                        .buttonStyle(.borderedProminent)
                    if profile.running {
                        Button("Quit") { store.quit(profile) }
                    }
                    if profile.outdated {
                        Button("Update") { store.update(profile) }
                    }
                }
                .controlSize(.regular)
            }
        }
    }

    private var statusLine: String {
        var parts: [String] = []
        if profile.running {
            parts.append(profile.pid.map { "Running (pid \($0))" } ?? "Running")
        } else {
            parts.append("Not running")
        }
        if let v = profile.bundle { parts.append("version \(v.display)") }
        return parts.joined(separator: " · ")
    }
}

struct DetailLocations: View {
    let profile: Profile

    var body: some View {
        Card {
            SectionTitle(text: "Where things are")
            InfoRow(title: profile.isCopy ? "App (a copy of \(profile.appName))" : "Launcher (starts the shared \(profile.appName))",
                    value: profile.path)
            InfoRow(title: "App data: sign-in, history, settings",
                    value: profile.dataDir,
                    note: ProfileStore.exists(profile.dataDir) ? nil : "Created the first time the profile opens.")
            if profile.configDir.isEmpty {
                InfoRow(title: "Claude Code settings", value: "~/.claude (shared, not separate)", revealable: false)
            } else {
                InfoRow(title: "Claude Code settings (CLAUDE_CONFIG_DIR)",
                        value: profile.configDir,
                        note: ProfileStore.exists(profile.configDir) ? nil : "Created when Claude Code first runs in this profile.")
            }
            InfoRow(title: "Built from" + (profile.appBundle.map { " (version \($0.display))" } ?? ""),
                    value: profile.app,
                    note: profile.appExists ? nil : "This app no longer exists, so the profile cannot be updated.")
            if !profile.extraEnv.isEmpty {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Environment")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    ForEach(profile.extraEnv, id: \.self) { line in
                        Text(line)
                            .font(.system(size: 12, design: .monospaced))
                            .textSelection(.enabled)
                    }
                }
            }
        }
    }
}

struct DetailTerminal: View {
    @EnvironmentObject var store: ProfileStore
    let profile: Profile

    var body: some View {
        Card {
            SectionTitle(text: "Claude Code in a terminal")
            Text("Run this in a terminal to use this profile's settings and login, then run claude.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(alignment: .top) {
                Text(store.terminalCommand(profile))
                    .font(.system(size: 11, design: .monospaced))
                    .textSelection(.enabled)
                    .lineLimit(3)
                    .truncationMode(.middle)
                Spacer(minLength: 4)
                IconButton(symbol: "doc.on.doc", help: "Copy") { store.copyEnv(profile) }
            }
        }
    }
}

// MARK: - New profile

struct AddView: View {
    @EnvironmentObject var store: ProfileStore
    @State private var advanced = false

    private var draft: ProfileDraft { store.addDraft }

    private var labelError: String? {
        if draft.label.isEmpty { return nil }
        if !ProfileDraft.isValidLabel(draft.label) { return "Use letters, digits, - and _ (up to 32), not starting with -." }
        if store.profile(draft.label) != nil { return "A profile with this label already exists." }
        return nil
    }

    private var canCreate: Bool {
        ProfileDraft.isValidLabel(draft.label) && labelError == nil && draft.icon.isValid
            && draft.badEnvLine == nil && store.globalBusy == nil
    }

    private var iconKinds: [IconKind] {
        // A shared launcher has no copy to draw on: only the app's icon or your own.
        draft.sharedApp ? [.appIcon, .file] : IconKind.allCases
    }

    var body: some View {
        VStack(spacing: 0) {
            PageHeader(title: "New profile")
            PageBody {
                Card {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Label")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                        TextField("e.g. Work", text: $store.addDraft.label)
                            .textFieldStyle(.roundedBorder)
                        if let labelError {
                            Text(labelError).font(.system(size: 11)).foregroundStyle(Color.red)
                        } else if !draft.label.isEmpty {
                            Text("Creates \(store.appName) \(draft.label).app in \(destShort).")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Icon")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                        IconPicker(choice: $store.addDraft.icon, kinds: iconKinds)
                    }
                }
                Card {
                    DisclosureGroup("Advanced", isExpanded: $advanced) {
                        AdvancedFields()
                            .padding(.top, 8)
                    }
                    .font(.system(size: 12))
                }
                HStack {
                    Button("Cancel") { store.page = .home }
                    Spacer()
                    if let status = store.globalBusy {
                        BusyLabel(text: status)
                    } else {
                        Button("Create Profile") { store.create() }
                            .buttonStyle(.borderedProminent)
                            .keyboardShortcut(.defaultAction)
                            .disabled(!canCreate)
                    }
                }
            }
        }
        .onChange(of: store.addDraft.sharedApp) { shared in
            if shared && (store.addDraft.icon.kind == .badge || store.addDraft.icon.kind == .color) {
                store.addDraft.icon.kind = .appIcon
            }
        }
    }

    private var destShort: String {
        ((store.listing?.dest ?? "~/Applications") as NSString).abbreviatingWithTildeInPath
    }
}

struct AdvancedFields: View {
    @EnvironmentObject var store: ProfileStore

    private var label: String { store.addDraft.label.isEmpty ? "<label>" : store.addDraft.label }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle(isOn: $store.addDraft.sharedApp) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Start the installed app instead of a copy")
                    Text("All such profiles share one Dock icon. Use this if passkeys or single sign-on fail in a copy.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            PathField(title: "App", placeholder: store.listing?.app?.path ?? "/Applications/Claude.app",
                      path: $store.addDraft.appPath, chooseFiles: true, chooseFolders: false, fileTypes: ["app"])
            PathField(title: "App data folder",
                      placeholder: "\(store.listing?.app?.defaultDataDir ?? "~/Library/Application Support/Claude")-\(label)",
                      path: $store.addDraft.dataDir)
            Toggle("Own Claude Code settings folder", isOn: $store.addDraft.ownConfigDir)
            if store.addDraft.ownConfigDir {
                PathField(title: "Claude Code folder", placeholder: "~/.claude-\(label.lowercased())",
                          path: $store.addDraft.configDir)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("Environment variables, one NAME=VALUE per line")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                TextField("NAME=value", text: $store.addDraft.env, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12, design: .monospaced))
                    .lineLimit(2...5)
                if let bad = store.addDraft.badEnvLine {
                    Text("Not NAME=VALUE: \(bad)").font(.system(size: 11)).foregroundStyle(Color.red)
                }
            }
        }
    }
}

// MARK: - Change icon

struct IconView: View {
    @EnvironmentObject var store: ProfileStore
    let profile: Profile

    var body: some View {
        VStack(spacing: 0) {
            PageHeader(title: "Change icon", back: .detail(profile.label))
            PageBody {
                Card {
                    HStack(spacing: 12) {
                        ProfileIcon(profile: profile, size: 48)
                        Text(profile.name).font(.system(size: 15, weight: .semibold))
                    }
                    IconPicker(choice: $store.iconDraft)
                    Text("The app is rebuilt with the same data, settings and environment."
                         + (profile.running ? " It is open, so it is quit and reopened." : ""))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                HStack {
                    Button("Cancel") { store.page = .detail(profile.label) }
                    Spacer()
                    if let status = store.busy[profile.label] {
                        BusyLabel(text: status)
                    } else {
                        Button("Apply") { store.changeIcon(profile) }
                            .buttonStyle(.borderedProminent)
                            .keyboardShortcut(.defaultAction)
                            .disabled(!store.iconDraft.isValid)
                    }
                }
            }
        }
    }
}

// MARK: - Remove

struct RemoveView: View {
    @EnvironmentObject var store: ProfileStore
    let profile: Profile

    private var folders: [String] {
        [profile.dataDir, profile.configDir].filter { ProfileStore.exists($0) }
    }

    private var confirmed: Bool { !store.purge || folders.isEmpty || store.purgeConfirm == profile.label }

    var body: some View {
        VStack(spacing: 0) {
            PageHeader(title: "Remove \(profile.name)", back: .detail(profile.label))
            PageBody {
                Card {
                    HStack(spacing: 12) {
                        ProfileIcon(profile: profile, size: 48)
                        Text("Deletes \((profile.path as NSString).abbreviatingWithTildeInPath). Its data is kept unless you also delete it below.")
                            .font(.system(size: 12))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if profile.running {
                        Label("It is open, so it is quit first.", systemImage: "info.circle")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    Toggle("Also delete its data and Claude Code folder", isOn: $store.purge)
                    if store.purge {
                        PurgeConfirm(profile: profile, folders: folders)
                    }
                }
                HStack {
                    Button("Cancel") { store.page = .detail(profile.label) }
                    Spacer()
                    if let status = store.busy[profile.label] {
                        BusyLabel(text: status)
                    } else {
                        Button(store.purge ? "Remove and Delete Data" : "Remove") { store.remove(profile) }
                            .buttonStyle(.borderedProminent)
                            .tint(.red)
                            .disabled(!confirmed)
                    }
                }
            }
        }
    }
}

struct PurgeConfirm: View {
    @EnvironmentObject var store: ProfileStore
    let profile: Profile
    let folders: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if folders.isEmpty {
                Text("There are no folders to delete yet.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            } else {
                Text("This permanently deletes:")
                    .font(.system(size: 11, weight: .semibold))
                ForEach(folders, id: \.self) { f in
                    Text((f as NSString).abbreviatingWithTildeInPath)
                        .font(.system(size: 11, design: .monospaced))
                }
                Text("Type \(profile.label) to confirm.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                TextField(profile.label, text: $store.purgeConfirm)
                    .textFieldStyle(.roundedBorder)
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.red.opacity(0.08)))
    }
}

// MARK: - Output

struct OutputView: View {
    @EnvironmentObject var store: ProfileStore
    let title: String
    let text: String

    var body: some View {
        VStack(spacing: 0) {
            PageHeader(title: title)
            PageBody {
                Card {
                    HStack(alignment: .top) {
                        Text(text)
                            .font(.system(size: 11, design: .monospaced))
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 4)
                        IconButton(symbol: "doc.on.doc", help: "Copy") { store.copy(text) }
                    }
                }
            }
        }
    }
}
