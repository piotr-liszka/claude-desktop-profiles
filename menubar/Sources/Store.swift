import AppKit
import Foundation
import ServiceManagement

// Not isolated as a whole, so views on any SDK can read it; everything that
// changes published state after a run hops to the main actor.
final class ProfileStore: ObservableObject {
    @Published private(set) var listing: Listing?
    @Published private(set) var loadError: String?
    @Published private(set) var busy: [String: String] = [:]   // label -> what is happening
    @Published private(set) var globalBusy: String?
    @Published var banner: Banner?
    @Published var page: Page = .home
    @Published var search = ""
    @Published var addDraft = ProfileDraft()
    @Published var iconDraft = IconChoice()
    @Published var purge = false
    @Published var purgeConfirm = ""

    private var pending: Task<Void, Never>?
    private var timer: Timer?

    init() {
        Task { @MainActor in await refresh() }
        // Updates rarely change; running state is caught by the workspace notifications.
        timer = Timer.scheduledTimer(withTimeInterval: 15 * 60, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.refresh() }
        }
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.refreshSoon() }
            }
        }
    }

    var profiles: [Profile] { listing?.profiles ?? [] }
    var outdated: [Profile] { profiles.filter(\.outdated) }

    var filteredProfiles: [Profile] {
        let q = search.trimmingCharacters(in: .whitespaces)
        if q.isEmpty { return profiles }
        return profiles.filter { $0.label.localizedCaseInsensitiveContains(q) || $0.name.localizedCaseInsensitiveContains(q) }
    }

    func profile(_ label: String) -> Profile? { profiles.first { $0.label == label } }

    var appName: String { listing?.app?.name ?? "Claude" }

    // MARK: - Loading

    @MainActor
    func refresh() async {
        let result = await Tool.run(["list", "--json"])
        guard result.ok else {
            loadError = result.message
            return
        }
        do {
            listing = try JSONDecoder().decode(Listing.self, from: Data(result.out.utf8))
            loadError = nil
        } catch {
            loadError = "Could not read the profile list: \(error.localizedDescription)"
        }
    }

    func refreshSoon() {
        pending?.cancel()
        pending = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 700_000_000)
            if Task.isCancelled { return }
            await refresh()
        }
    }

    // MARK: - Running the script

    @MainActor @discardableResult
    private func perform(_ label: String?, _ status: String, _ args: [String], success: String? = nil) async -> Bool {
        if let label { busy[label] = status } else { globalBusy = status }
        let result = await Tool.run(args)
        if let label { busy[label] = nil } else { globalBusy = nil }
        if result.ok {
            if let success { banner = Banner(text: success, isError: false) }
        } else {
            banner = Banner(text: result.message.isEmpty ? "claude-profiles failed (exit \(result.status))" : result.message, isError: true)
        }
        await refresh()
        return result.ok
    }

    func launch(_ p: Profile) {
        Task { @MainActor in await perform(p.label, p.running ? "Showing..." : "Opening...", ["launch", p.label]) }
    }

    func quit(_ p: Profile) {
        Task { @MainActor in await perform(p.label, "Quitting...", ["quit", p.label]) }
    }

    func update(_ p: Profile) {
        let note = p.running ? "Quitting, rebuilding and reopening..." : "Rebuilding..."
        Task { @MainActor in await perform(p.label, note, ["update", p.label, "--restart"], success: "\(p.name) now runs \(p.versionChange.to).") }
    }

    func updateAll() {
        let labels = outdated.map(\.label)
        for label in labels { busy[label] = "Waiting..." }
        Task { @MainActor in
            let ok = await perform(nil, "Updating \(labels.count) profiles...", ["update", "--outdated", "--restart"], success: "All profiles are up to date.")
            if !ok { for label in labels { busy[label] = nil } }
        }
    }

    func create() {
        let draft = addDraft
        Task { @MainActor in
            let ok = await perform(nil, "Creating \(draft.label)...", draft.args,
                                   success: "Created \(appName) \(draft.label). Open it and sign in to the account you want.")
            if ok {
                addDraft = ProfileDraft()
                page = .detail(draft.label)
            }
        }
    }

    func changeIcon(_ p: Profile) {
        let args = ["icon", p.label] + iconDraft.iconArgs + ["--restart"]
        Task { @MainActor in
            if await perform(p.label, "Rebuilding with the new icon...", args, success: "New icon for \(p.name). The Dock may take a moment to show it.") {
                page = .detail(p.label)
            }
        }
    }

    func remove(_ p: Profile) {
        let purgeIt = purge
        Task { @MainActor in
            if p.running {
                guard await perform(p.label, "Quitting...", ["quit", p.label]) else { return }
            }
            var args = ["remove", p.label]
            if purgeIt { args += ["--purge", "--yes"] }
            let what = purgeIt ? "Removed \(p.name) and deleted its data." : "Removed \(p.name). Its data was kept."
            if await perform(p.label, "Removing...", args, success: what) {
                purge = false
                purgeConfirm = ""
                page = .home
            }
        }
    }

    func showDoctor() {
        Task { @MainActor in
            globalBusy = "Checking..."
            let result = await Tool.run(["doctor"])
            globalBusy = nil
            page = .output(title: "Diagnostics", text: (result.out + result.err).trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }

    func installUpdater() {
        Task { @MainActor in await perform(nil, "Creating the updater app...", ["install-updater"], success: "Created \(appName) Profiles Updater in \(listing?.dest ?? "~/Applications").") }
    }

    func copyEnv(_ p: Profile) {
        copy(terminalCommand(p))
        banner = Banner(text: "Copied. Paste it into a terminal, then run claude.", isError: false)
    }

    func terminalCommand(_ p: Profile) -> String {
        let quoted = "'" + Tool.path.replacingOccurrences(of: "'", with: "'\\''") + "'"
        return "eval \"$(\(quoted) env \(p.label))\""
    }

    // MARK: - Finder and pasteboard

    func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    func reveal(_ path: String) {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }

    func openFolder(_ path: String) {
        NSWorkspace.shared.open(URL(fileURLWithPath: path, isDirectory: true))
    }

    static func exists(_ path: String) -> Bool {
        !path.isEmpty && FileManager.default.fileExists(atPath: path)
    }

    // MARK: - Open at login

    var opensAtLogin: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            do {
                if newValue { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            } catch {
                banner = Banner(text: "Could not change Open at Login: \(error.localizedDescription)", isError: true)
            }
            objectWillChange.send()
        }
    }
}
