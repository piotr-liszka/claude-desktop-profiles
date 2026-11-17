import AppKit
import Foundation

// What `claude-profiles list --json` prints.
struct Listing: Decodable {
    let tool: String
    let version: String
    let os: String
    let dest: String
    let app: DetectedApp?
    let profiles: [Profile]
}

struct DetectedApp: Decodable {
    let path: String
    let name: String
    let defaultDataDir: String
    let bundle: BundleVersion?
}

struct BundleVersion: Decodable, Equatable {
    let version: String
    let build: String

    var display: String {
        if version.isEmpty { return build.isEmpty ? "unknown" : build }
        return version
    }
}

struct Profile: Decodable, Identifiable, Equatable {
    let label: String
    let path: String
    let mode: String
    let app: String
    let appExists: Bool
    let dataDir: String
    let configDir: String
    let customIcon: Bool
    let running: Bool
    let pid: Int?
    let outdated: Bool
    let bundle: BundleVersion?
    let appBundle: BundleVersion?
    let env: [String]

    var id: String { label }
    var isCopy: Bool { mode == "copy" }
    var name: String { (path as NSString).lastPathComponent.replacingOccurrences(of: ".app", with: "") }
    var appName: String { (app as NSString).lastPathComponent.replacingOccurrences(of: ".app", with: "") }
    var extraEnv: [String] { env.filter { !$0.hasPrefix("CLAUDE_CONFIG_DIR=") } }

    // "1.2 -> 1.3", falling back to build numbers when the versions match.
    var versionChange: (from: String, to: String) {
        let have = bundle, want = appBundle
        if let have, let want, have.version == want.version, have.build != want.build {
            return (have.build, want.build)
        }
        return (have?.display ?? "unknown", want?.display ?? "unknown")
    }
}

// The script that does the real work. The app carries its own copy (see build.sh).
struct ToolResult {
    let status: Int32
    let out: String
    let err: String

    var ok: Bool { status == 0 }

    // The script's own message, without its "claude-profiles: " prefix.
    var message: String {
        let text = err.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? out : err
        let lines = text.split(separator: "\n").suffix(6).map { line -> String in
            let s = String(line)
            return s.hasPrefix("claude-profiles: ") ? String(s.dropFirst("claude-profiles: ".count)) : s
        }
        return lines.joined(separator: "\n")
    }
}

enum Tool {
    static var url: URL? {
        if let custom = UserDefaults.standard.string(forKey: "ToolPath"), !custom.isEmpty {
            return URL(fileURLWithPath: custom)
        }
        return Bundle.main.url(forResource: "claude-profiles", withExtension: nil)
    }

    static var path: String { url?.path ?? "claude-profiles" }

    // Profiles live in ~/Applications unless ProfilesDest says otherwise.
    static var destArgs: [String] {
        if let dest = UserDefaults.standard.string(forKey: "ProfilesDest"), !dest.isEmpty {
            return ["--dest", dest]
        }
        return []
    }

    static func run(_ args: [String]) async -> ToolResult {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(returning: runSync(args))
            }
        }
    }

    private static func runSync(_ args: [String]) -> ToolResult {
        guard let url = url else {
            return ToolResult(status: 127, out: "", err: "claude-profiles was not found inside the app. Build it again with menubar/build.sh.")
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [url.path] + args + destArgs
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = "/usr/bin:/bin:/usr/sbin:/sbin"
        process.environment = env
        process.standardInput = FileHandle.nullDevice
        let outPipe = Pipe(), errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe

        // stderr is read on another thread so neither pipe can fill up and block.
        let errBox = DataBox()
        let group = DispatchGroup()
        group.enter()
        DispatchQueue.global().async {
            errBox.data = errPipe.fileHandleForReading.readDataToEndOfFile()
            group.leave()
        }
        do {
            try process.run()
        } catch {
            try? errPipe.fileHandleForWriting.close()
            group.wait()
            return ToolResult(status: 126, out: "", err: "Could not run claude-profiles: \(error.localizedDescription)")
        }
        let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
        group.wait()
        process.waitUntilExit()
        return ToolResult(status: process.terminationStatus,
                          out: String(decoding: outData, as: UTF8.self),
                          err: String(decoding: errBox.data, as: UTF8.self))
    }
}

private final class DataBox: @unchecked Sendable {
    var data = Data()
}

// Icon choices map one to one onto the script's options.
enum IconKind: String, CaseIterable, Identifiable {
    case badge, color, file, appIcon

    var id: String { rawValue }

    var title: String {
        switch self {
        case .badge: return "Badge"
        case .color: return "Colour"
        case .file: return "Image"
        case .appIcon: return "Original"
        }
    }

    var help: String {
        switch self {
        case .badge: return "The app's icon with a coloured badge showing the label's first letter."
        case .color: return "The whole icon turned to another colour."
        case .file: return "Your own image: .icns, or a square .png (1024 px is best)."
        case .appIcon: return "The app's own icon, unchanged."
        }
    }
}

struct NamedColor: Identifiable {
    let name: String
    let hex: String
    var id: String { name }

    static let all: [NamedColor] = [
        .init(name: "red", hex: "ef4444"), .init(name: "orange", hex: "f97316"),
        .init(name: "yellow", hex: "eab308"), .init(name: "green", hex: "22c55e"),
        .init(name: "teal", hex: "14b8a6"), .init(name: "blue", hex: "3b82f6"),
        .init(name: "purple", hex: "8b5cf6"), .init(name: "pink", hex: "ec4899"),
    ]
}

struct IconChoice: Equatable {
    var kind: IconKind = .badge
    var color = "blue"
    var file = ""

    var isValid: Bool {
        switch kind {
        case .badge, .appIcon: return true
        case .color: return !color.trimmingCharacters(in: .whitespaces).isEmpty
        case .file: return FileManager.default.fileExists(atPath: file)
        }
    }

    // Options for `add`.
    var addArgs: [String] {
        switch kind {
        case .badge: return []
        case .color: return ["--color", color.trimmingCharacters(in: .whitespaces)]
        case .file: return ["--icon", file]
        case .appIcon: return ["--no-badge"]
        }
    }

    // Options for `icon`.
    var iconArgs: [String] {
        kind == .badge ? ["--badge"] : addArgs
    }
}

struct ProfileDraft: Equatable {
    var label = ""
    var icon = IconChoice()
    var sharedApp = false
    var appPath = ""
    var dataDir = ""
    var ownConfigDir = true
    var configDir = ""
    var env = ""

    static func isValidLabel(_ label: String) -> Bool {
        label.range(of: "^[A-Za-z0-9_][A-Za-z0-9_-]{0,31}$", options: .regularExpression) != nil
    }

    var envLines: [String] {
        env.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    var badEnvLine: String? {
        envLines.first { $0.range(of: "^[A-Za-z_][A-Za-z0-9_]*=", options: .regularExpression) == nil }
    }

    var args: [String] {
        var a = ["add", label]
        a += icon.addArgs
        if sharedApp { a.append("--shared-app") }
        if !appPath.isEmpty { a += ["--app", appPath] }
        if !dataDir.isEmpty { a += ["--data-dir", dataDir] }
        if !ownConfigDir {
            a.append("--no-config-dir")
        } else if !configDir.isEmpty {
            a += ["--config-dir", configDir]
        }
        for line in envLines { a += ["--env", line] }
        return a
    }
}

enum Page: Equatable {
    case home
    case detail(String)
    case add
    case icon(String)
    case remove(String)
    case output(title: String, text: String)
}

struct Banner: Equatable {
    let text: String
    let isError: Bool
}
