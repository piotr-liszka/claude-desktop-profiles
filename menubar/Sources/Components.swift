import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct Card<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            content
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.primary.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.07))
        )
    }
}

struct SectionTitle: View {
    let text: String
    var count: Int?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 3) {
            Text(text)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
            if let count {
                Text("\(count)")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .baselineOffset(5)
            }
        }
    }
}

// The icon Finder shows for a bundle, so a changed profile icon shows up here too.
struct BundleIcon: View {
    let path: String
    var size: CGFloat = 36

    var body: some View {
        Image(nsImage: NSWorkspace.shared.icon(forFile: path))
            .resizable()
            .interpolation(.high)
            .frame(width: size, height: size)
    }
}

struct ProfileIcon: View {
    let profile: Profile
    var size: CGFloat = 36

    var body: some View {
        BundleIcon(path: profile.path, size: size)
            .overlay(alignment: .bottomTrailing) {
                if profile.running {
                    Circle()
                        .fill(Color.green)
                        .frame(width: size * 0.26, height: size * 0.26)
                        .overlay(Circle().strokeBorder(Color(nsColor: .windowBackgroundColor), lineWidth: 2))
                        .help("Running")
                }
            }
    }
}

struct PageHeader: View {
    @EnvironmentObject var store: ProfileStore
    let title: String
    var back: Page = .home

    var body: some View {
        HStack(spacing: 8) {
            Button {
                store.page = back
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Text(title)
                .font(.system(size: 15, weight: .semibold))
                .lineLimit(1)
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
    }
}

struct BannerView: View {
    @EnvironmentObject var store: ProfileStore
    let banner: Banner

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: banner.isError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                .foregroundStyle(banner.isError ? Color.orange : Color.green)
            Text(banner.text)
                .font(.system(size: 12))
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Button {
                store.banner = nil
            } label: {
                Image(systemName: "xmark").font(.system(size: 10, weight: .bold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill((banner.isError ? Color.orange : Color.green).opacity(0.12))
        )
    }
}

// A path with buttons to show it in Finder and copy it.
struct InfoRow: View {
    @EnvironmentObject var store: ProfileStore
    let title: String
    let value: String
    var note: String?
    var revealable = true

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            HStack(spacing: 6) {
                Text(value)
                    .font(.system(size: 12, design: .monospaced))
                    .lineLimit(2)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
                Spacer(minLength: 4)
                if revealable && ProfileStore.exists(value) {
                    IconButton(symbol: "folder", help: "Show in Finder") { store.reveal(value) }
                }
                IconButton(symbol: "doc.on.doc", help: "Copy") { store.copy(value) }
            }
            if let note {
                Text(note)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct IconButton: View {
    let symbol: String
    let help: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11))
                .frame(width: 20, height: 20)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .help(help)
    }
}

// A text field with a Choose... button.
struct PathField: View {
    let title: String
    let placeholder: String
    @Binding var path: String
    var chooseFiles = false
    var chooseFolders = true
    var fileTypes: [String] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            HStack(spacing: 6) {
                TextField(placeholder, text: $path)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12))
                Button("Choose...") { choose() }
                    .controlSize(.small)
            }
        }
    }

    private func choose() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = chooseFiles
        panel.canChooseDirectories = chooseFolders
        panel.canCreateDirectories = chooseFolders
        panel.allowsMultipleSelection = false
        panel.treatsFilePackagesAsDirectories = false
        if !fileTypes.isEmpty { panel.allowedContentTypes = fileTypes.compactMap { UTType(filenameExtension: $0) } }
        NSApp.activate(ignoringOtherApps: true)
        if panel.runModal() == .OK, let url = panel.url {
            path = url.path
        }
    }
}

struct IconPicker: View {
    @Binding var choice: IconChoice
    var kinds: [IconKind] = IconKind.allCases

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("Icon", selection: $choice.kind) {
                ForEach(kinds) { kind in
                    Text(kind.title).tag(kind)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            Text(choice.kind.help)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            switch choice.kind {
            case .color:
                ColorSwatches(color: $choice.color)
            case .file:
                PathField(title: "Image", placeholder: "/path/to/icon.png", path: $choice.file,
                          chooseFiles: true, chooseFolders: false, fileTypes: ["png", "icns", "jpg", "jpeg", "tiff", "heic"])
            case .badge, .appIcon:
                EmptyView()
            }
        }
    }
}

struct ColorSwatches: View {
    @Binding var color: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                ForEach(NamedColor.all) { c in
                    Button {
                        color = c.name
                    } label: {
                        Circle()
                            .fill(Color(hex: c.hex))
                            .frame(width: 22, height: 22)
                            .overlay(
                                Circle()
                                    .strokeBorder(Color.primary.opacity(color == c.name ? 0.9 : 0), lineWidth: 2)
                                    .padding(-3)
                            )
                    }
                    .buttonStyle(.plain)
                    .help(c.name)
                }
            }
            .padding(.leading, 3)
            HStack(spacing: 6) {
                Text("or hex")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                TextField("#3b82f6", text: $color)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12, design: .monospaced))
                    .frame(width: 110)
            }
        }
    }
}

extension Color {
    init(hex: String) {
        let value = UInt32(hex.trimmingCharacters(in: CharacterSet(charactersIn: "#")), radix: 16) ?? 0
        self.init(.sRGB,
                  red: Double((value >> 16) & 0xff) / 255,
                  green: Double((value >> 8) & 0xff) / 255,
                  blue: Double(value & 0xff) / 255,
                  opacity: 1)
    }
}
