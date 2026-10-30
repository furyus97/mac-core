import SwiftUI
import AppKit
import Darwin

// MARK: - Command runner

/// Runs a system tool by absolute path (never through a shell) with `LC_ALL=C`
/// and a hard timeout. stdout and stderr are merged. Returns nil when the tool
/// is missing or could not be launched.
enum CommandRunner {
    struct Result: Sendable {
        let status: Int32
        let output: String
        let timedOut: Bool
        var succeeded: Bool { status == 0 && !timedOut }
    }

    static func run(_ path: String, _ arguments: [String], timeout: TimeInterval = 5) async -> Result? {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(returning: runSync(path, arguments, timeout: timeout))
            }
        }
    }

    private final class DataBox: @unchecked Sendable {
        private let lock = NSLock()
        private var data = Data()
        func set(_ value: Data) { lock.lock(); data = value; lock.unlock() }
        func get() -> Data { lock.lock(); defer { lock.unlock() }; return data }
    }

    static func runSync(_ path: String, _ arguments: [String], timeout: TimeInterval = 5) -> Result? {
        guard path.hasPrefix("/"), FileManager.default.isExecutableFile(atPath: path) else { return nil }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        var environment = ProcessInfo.processInfo.environment
        environment["LC_ALL"] = "C"
        process.environment = environment
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        process.standardInput = FileHandle.nullDevice

        let finished = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in finished.signal() }
        do { try process.run() } catch { return nil }

        let box = DataBox()
        let reader = DispatchGroup()
        reader.enter()
        let handle = pipe.fileHandleForReading
        DispatchQueue.global(qos: .utility).async {
            box.set(handle.readDataToEndOfFile())
            reader.leave()
        }

        var timedOut = false
        if finished.wait(timeout: .now() + timeout) == .timedOut {
            timedOut = true
            process.terminate()
            if finished.wait(timeout: .now() + 1) == .timedOut {
                kill(process.processIdentifier, SIGKILL)
                _ = finished.wait(timeout: .now() + 1)
            }
        }
        _ = reader.wait(timeout: .now() + 1)
        let output = String(decoding: box.get(), as: UTF8.self)
        let status = process.isRunning ? -1 : process.terminationStatus
        return Result(status: status, output: output, timedOut: timedOut)
    }
}

// MARK: - Model

/// A launchd job found in one of the LaunchAgents / LaunchDaemons folders.
struct StartupItem: Identifiable, Sendable, Hashable {
    enum Scope: String, Sendable, CaseIterable, Hashable {
        case userAgent, globalAgent, globalDaemon

        var directory: URL {
            switch self {
            case .userAgent:
                return FileManager.default.homeDirectoryForCurrentUser.appending(path: "Library/LaunchAgents", directoryHint: .isDirectory)
            case .globalAgent: return URL(fileURLWithPath: "/Library/LaunchAgents", isDirectory: true)
            case .globalDaemon: return URL(fileURLWithPath: "/Library/LaunchDaemons", isDirectory: true)
            }
        }
    }

    /// launchd label (e.g. `com.google.keystone.agent`).
    let label: String
    /// Best human-readable name (app name, executable name, or label).
    let displayName: String
    let plistURL: URL
    /// `Program` or `ProgramArguments[0]`, when the plist could be read.
    let programPath: String?
    let scope: Scope
    var isEnabled: Bool
    /// Only known for agents in the current user's GUI domain.
    var isRunning: Bool?
    /// Vendor guess from the app bundle / associated bundle id / label.
    let vendor: String?
    /// True when the plist is a symlink to a file outside its folder; it was not
    /// read, so the item is shown read-only.
    var isLinkedOutside: Bool = false

    var id: String { "\(scope.rawValue):\(plistURL.path)" }
    var isApple: Bool { label.hasPrefix("com.apple.") }
    /// Only the user's own, non-Apple, directly-readable agents can be switched.
    var canToggle: Bool { StartupItemsService.toggleRefusal(for: self) == nil }
}

enum StartupToggleError: Error, Equatable, Sendable {
    case appleItem
    case notUserScope
    case linkedOutside
    case invalidLabel
    case commandFailed(String)

    var message: String {
        switch self {
        case .appleItem: return tr("speed.error.apple")
        case .notUserScope: return tr("speed.adminNote")
        case .linkedOutside: return tr("speed.help.linked")
        case .invalidLabel: return tr("speed.error.label")
        case .commandFailed(let detail):
            return detail.isEmpty ? tr("speed.error.command") : detail
        }
    }
}

// MARK: - Service

enum StartupItemsService {
    static let launchctlPath = "/bin/launchctl"
    static let loginItemsSettingsURL = URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension")!

    static var guiDomain: String { "gui/\(getuid())" }

    /// Reads every LaunchAgent/LaunchDaemon plist (read-only), plus enabled and
    /// running state from launchctl. Unreadable files are skipped.
    static func list() async -> [StartupItem] {
        async let guiDisabled = CommandRunner.run(launchctlPath, ["print-disabled", guiDomain])
        async let systemDisabled = CommandRunner.run(launchctlPath, ["print-disabled", "system"])
        async let loaded = CommandRunner.run(launchctlPath, ["list"])
        let guiOverrides = parseDisabledOverrides((await guiDisabled)?.output ?? "")
        let systemOverrides = parseDisabledOverrides((await systemDisabled)?.output ?? "")
        let running = parseLaunchctlList((await loaded)?.output ?? "")

        var items: [StartupItem] = []
        for scope in StartupItem.Scope.allCases {
            let overrides = scope == .globalDaemon ? systemOverrides : guiOverrides
            items += scan(directory: scope.directory, scope: scope, overrides: overrides,
                          running: scope == .globalDaemon ? [:] : running)
        }
        return items
    }

    /// Scans one folder (non-recursive). Symlinks are only followed when their
    /// target stays inside `directory`; otherwise the item is listed read-only
    /// from its file name without reading the target.
    static func scan(directory: URL, scope: StartupItem.Scope,
                     overrides: [String: Bool], running: [String: Bool]) -> [StartupItem] {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(at: directory,
                                                       includingPropertiesForKeys: [.isSymbolicLinkKey, .isRegularFileKey],
                                                       options: [.skipsHiddenFiles]) else { return [] }
        let root = directory.resolvingSymlinksInPath().standardizedFileURL.path
        var items: [StartupItem] = []
        for url in entries where url.pathExtension.lowercased() == "plist" {
            let values = try? url.resourceValues(forKeys: [.isSymbolicLinkKey, .isRegularFileKey])
            var readURL = url
            if values?.isSymbolicLink == true {
                let target = url.resolvingSymlinksInPath().standardizedFileURL
                if target.path.hasPrefix(root + "/") {
                    readURL = target
                } else {
                    let label = url.deletingPathExtension().lastPathComponent
                    guard isValidLabel(label) else { continue }
                    let enabled = overrides[label] ?? true
                    items.append(StartupItem(label: label, displayName: label, plistURL: url, programPath: nil,
                                             scope: scope, isEnabled: enabled, isRunning: running[label],
                                             vendor: vendorGuess(label: label, programPath: nil, bundleIDs: []),
                                             isLinkedOutside: true))
                    continue
                }
            } else if values?.isRegularFile != true {
                continue
            }
            if let item = parse(plistAt: readURL, listedAt: url, scope: scope, overrides: overrides, running: running) {
                items.append(item)
            }
        }
        return items.sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }

    /// Parses a launchd plist. Returns nil for unreadable / invalid files.
    static func parse(plistAt url: URL, listedAt listedURL: URL? = nil, scope: StartupItem.Scope,
                      overrides: [String: Bool] = [:], running: [String: Bool] = [:]) -> StartupItem? {
        guard let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize, size < 1_000_000,
              let data = try? Data(contentsOf: url),
              let plist = (try? PropertyListSerialization.propertyList(from: data, options: [], format: nil)) as? [String: Any],
              let label = plist["Label"] as? String, isValidLabel(label) else { return nil }

        let program = (plist["Program"] as? String)
            ?? (plist["ProgramArguments"] as? [String])?.first
            ?? (plist["BundleProgram"] as? String)
        let bundleIDs = plist["AssociatedBundleIdentifiers"] as? [String]
            ?? (plist["AssociatedBundleIdentifiers"] as? String).map { [$0] } ?? []
        let disabledInPlist = plist["Disabled"] as? Bool ?? false
        let enabled = overrides[label] ?? !disabledInPlist

        return StartupItem(label: label,
                           displayName: displayName(label: label, programPath: program),
                           plistURL: listedURL ?? url,
                           programPath: program,
                           scope: scope,
                           isEnabled: enabled,
                           isRunning: running[label],
                           vendor: vendorGuess(label: label, programPath: program, bundleIDs: bundleIDs))
    }

    /// `launchctl print-disabled` → label: isEnabled.
    static func parseDisabledOverrides(_ output: String) -> [String: Bool] {
        var result: [String: Bool] = [:]
        for line in output.split(separator: "\n") {
            let parts = line.components(separatedBy: "=>")
            guard parts.count == 2 else { continue }
            let label = parts[0].trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            let state = parts[1].trimmingCharacters(in: .whitespaces).lowercased()
            guard !label.isEmpty else { continue }
            if state.hasPrefix("disabled") || state.hasPrefix("true") { result[label] = false }
            else if state.hasPrefix("enabled") || state.hasPrefix("false") { result[label] = true }
        }
        return result
    }

    /// `launchctl list` → label: isRunning (has a PID).
    static func parseLaunchctlList(_ output: String) -> [String: Bool] {
        var result: [String: Bool] = [:]
        for line in output.split(separator: "\n") {
            let fields = line.split(separator: "\t", omittingEmptySubsequences: false)
            guard fields.count >= 3 else { continue }
            let pid = fields[0].trimmingCharacters(in: .whitespaces)
            if pid == "PID" { continue }
            result[String(fields[2])] = Int(pid) != nil
        }
        return result
    }

    static func isValidLabel(_ label: String) -> Bool {
        !label.isEmpty && label.count <= 255 && !label.hasPrefix("-")
            && label.unicodeScalars.allSatisfy { CharacterSet.alphanumerics.contains($0) || "._-".unicodeScalars.contains($0) }
    }

    static func displayName(label: String, programPath: String?) -> String {
        if let program = programPath {
            let components = program.split(separator: "/")
            if let app = components.first(where: { $0.hasSuffix(".app") }) {
                return String(app.dropLast(4))
            }
            if let last = components.last, !last.isEmpty { return String(last) }
        }
        return label
    }

    private static let genericPrefixes: Set<String> = ["com", "org", "net", "io", "dev", "sh", "co", "app", "me", "de", "kr", "jp", "uk", "fr", "us", "info", "biz", "application"]

    static func vendorGuess(label: String, programPath: String?, bundleIDs: [String]) -> String? {
        if let program = programPath,
           let app = program.split(separator: "/").first(where: { $0.hasSuffix(".app") }) {
            return String(app.dropLast(4))
        }
        let source = bundleIDs.first ?? label
        let parts = source.split(separator: ".").map(String.init)
        guard let vendor = parts.first(where: { !genericPrefixes.contains($0.lowercased()) }) else { return nil }
        return vendor.prefix(1).uppercased() + vendor.dropFirst()
    }

    /// Why this item cannot be switched here, or nil when it can.
    static func toggleRefusal(for item: StartupItem) -> StartupToggleError? {
        if item.isApple { return .appleItem }
        guard item.scope == .userAgent else { return .notUserScope }
        if item.isLinkedOutside { return .linkedOutside }
        guard isValidLabel(item.label) else { return .invalidLabel }
        let folder = item.plistURL.deletingLastPathComponent().standardizedFileURL.path
        guard folder == StartupItem.Scope.userAgent.directory.standardizedFileURL.path else { return .notUserScope }
        return nil
    }

    /// Reversibly enables / disables a user LaunchAgent. Never deletes or edits
    /// the plist; refuses Apple, global and linked items before running anything.
    static func setEnabled(_ enabled: Bool, for item: StartupItem) async throws {
        if let refusal = toggleRefusal(for: item) { throw refusal }
        let target = "\(guiDomain)/\(item.label)"
        if enabled {
            let result = await CommandRunner.run(launchctlPath, ["enable", target])
            guard let result, result.succeeded else {
                throw StartupToggleError.commandFailed(result?.output.trimmingCharacters(in: .whitespacesAndNewlines) ?? "")
            }
            // Already-loaded jobs make bootstrap fail; the job is enabled either way.
            _ = await CommandRunner.run(launchctlPath, ["bootstrap", guiDomain, item.plistURL.path])
        } else {
            let result = await CommandRunner.run(launchctlPath, ["disable", target])
            guard let result, result.succeeded else {
                throw StartupToggleError.commandFailed(result?.output.trimmingCharacters(in: .whitespacesAndNewlines) ?? "")
            }
            _ = await CommandRunner.run(launchctlPath, ["bootout", target])
        }
    }
}

// MARK: - View model

@MainActor
final class SpeedViewModel: ObservableObject {
    @Published private(set) var items: [StartupItem] = []
    @Published private(set) var isLoading = false
    @Published private(set) var busyIDs: Set<String> = []
    @Published var errorMessage: String?

    var enabledCount: Int { items.filter(\.isEnabled).count }
    var switchableCount: Int { items.filter(\.canToggle).count }

    func items(in scope: StartupItem.Scope) -> [StartupItem] { items.filter { $0.scope == scope } }

    func load() async {
        guard !isLoading else { return }
        isLoading = true
        items = await StartupItemsService.list()
        isLoading = false
    }

    func set(_ item: StartupItem, enabled: Bool) async {
        guard item.canToggle, !busyIDs.contains(item.id) else { return }
        busyIDs.insert(item.id)
        defer { busyIDs.remove(item.id) }
        errorMessage = nil
        do {
            try await StartupItemsService.setEnabled(enabled, for: item)
        } catch let error as StartupToggleError {
            errorMessage = tr("speed.error.toggle", item.displayName, error.message)
        } catch {
            errorMessage = tr("speed.error.toggle", item.displayName, error.localizedDescription)
        }
        await load()
    }
}

// MARK: - View

struct SpeedView: View {
    @StateObject private var vm = SpeedViewModel()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                summaryCard
                InfoBanner(kind: .info, message: tr("speed.reversibleNote"))
                if let message = vm.errorMessage {
                    InfoBanner(kind: .warning, message: message, actionTitle: tr("common.close")) { vm.errorMessage = nil }
                }
                content
            }
            .padding(Theme.Spacing.outer)
        }
        .screenBackground()
        .navigationTitle(tr("nav.speed"))
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { Task { await vm.load() } } label: {
                    Label(tr("common.refresh"), systemImage: "arrow.clockwise")
                }
                .disabled(vm.isLoading)
            }
        }
        .task { if vm.items.isEmpty { await vm.load() } }
    }

    private var summaryCard: some View {
        HStack(alignment: .center, spacing: Theme.Spacing.xl) {
            IconTile(systemName: "bolt.fill", size: 56, colors: TileColor.speed)
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                StatusEyebrow(text: tr("speed.eyebrow"), color: AppColor.success)
                Text(tr("speed.summary.title")).font(.mcCardTitle)
                Text(tr("speed.subtitle"))
                    .font(.mcCaption)
                    .foregroundStyle(AppColor.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                Button {
                    NSWorkspace.shared.open(StartupItemsService.loginItemsSettingsURL)
                } label: {
                    Label(tr("speed.openLoginItems"), systemImage: "arrow.up.forward.app")
                }
                .buttonStyle(.softCapsule)
                .padding(.top, Theme.Spacing.xs)
            }
            Spacer(minLength: Theme.Spacing.md)
            metric(value: vm.enabledCount, label: tr("speed.metric.enabled"))
            metric(value: vm.switchableCount, label: tr("speed.metric.switchable"))
        }
        .card(elevated: true)
    }

    private func metric(value: Int, label: String) -> some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text(vm.items.isEmpty && vm.isLoading ? "–" : "\(value)")
                .font(.mcMetric(40))
                .foregroundStyle(AppGradient.brand)
                .contentTransition(.numericText())
            Text(label).font(.mcMicro).foregroundStyle(AppColor.secondaryText)
        }
        .frame(minWidth: 110, alignment: .trailing)
    }

    @ViewBuilder
    private var content: some View {
        if vm.isLoading && vm.items.isEmpty {
            VStack(spacing: Theme.Spacing.md) {
                ProgressView()
                Text(tr("common.scanning")).font(.mcBody).foregroundStyle(AppColor.secondaryText)
            }
            .frame(maxWidth: .infinity, minHeight: 200)
        } else if vm.items.isEmpty {
            EmptyStateView(systemImage: "bolt.slash", title: tr("speed.empty.title"), message: tr("speed.empty.message"))
        } else {
            ForEach(StartupItem.Scope.allCases, id: \.self) { scope in
                let scoped = vm.items(in: scope)
                if !scoped.isEmpty { section(scope, items: scoped) }
            }
        }
    }

    private func section(_ scope: StartupItem.Scope, items: [StartupItem]) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            SectionTitle(text: title(for: scope)) {
                Text(scope.directory.path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                    .font(.mcMono(11))
                    .foregroundStyle(AppColor.secondaryText)
            }
            if scope != .userAgent {
                Label(tr("speed.adminNote"), systemImage: "lock.fill")
                    .font(.mcCaption)
                    .foregroundStyle(AppColor.secondaryText)
            }
            VStack(spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    row(item)
                    if index < items.count - 1 { Divider().padding(.leading, 52) }
                }
            }
            .card(padding: Theme.Spacing.md)
        }
    }

    private func title(for scope: StartupItem.Scope) -> String {
        switch scope {
        case .userAgent: return tr("speed.scope.userAgent")
        case .globalAgent: return tr("speed.scope.globalAgent")
        case .globalDaemon: return tr("speed.scope.globalDaemon")
        }
    }

    private func icon(for scope: StartupItem.Scope) -> String {
        switch scope {
        case .userAgent: return "person.crop.circle"
        case .globalAgent: return "person.2.fill"
        case .globalDaemon: return "gearshape.2.fill"
        }
    }

    private func row(_ item: StartupItem) -> some View {
        HStack(spacing: Theme.Spacing.md) {
            if item.canToggle {
                IconTile(systemName: icon(for: item.scope), size: 36, colors: item.isEnabled ? TileColor.speed : [AppColor.secondaryText, AppColor.secondaryText.opacity(0.7)])
            } else {
                IconTile(systemName: icon(for: item.scope), tint: AppColor.secondaryText, size: 36)
            }
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: Theme.Spacing.sm) {
                    Text(item.displayName)
                        .font(.mcBodyMedium)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if item.isRunning == true { chip(tr("speed.tag.running"), color: AppColor.success) }
                    if item.isApple { chip(tr("speed.tag.apple"), color: AppColor.secondaryText) }
                    if item.isLinkedOutside { chip(tr("speed.tag.linked"), color: AppColor.secondaryText) }
                }
                Text(item.label)
                    .font(.mcMono(11))
                    .foregroundStyle(AppColor.secondaryText)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
                if let program = item.programPath {
                    Text(program)
                        .font(.mcMono(10))
                        .foregroundStyle(AppColor.secondaryText.opacity(0.8))
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .help(program)
                }
            }
            Spacer(minLength: Theme.Spacing.sm)
            if vm.busyIDs.contains(item.id) {
                ProgressView().controlSize(.small)
            }
            Toggle(item.displayName, isOn: Binding(
                get: { item.isEnabled },
                set: { newValue in Task { await vm.set(item, enabled: newValue) } }
            ))
            .toggleStyle(.switch)
            .labelsHidden()
            .disabled(!item.canToggle || vm.busyIDs.contains(item.id))
            .help(StartupItemsService.toggleRefusal(for: item)?.message ?? "")
        }
        .padding(.vertical, Theme.Spacing.sm)
        .padding(.horizontal, Theme.Spacing.xs)
    }

    private func chip(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.mcMicro)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .foregroundStyle(color)
            .background(Capsule().fill(color.opacity(0.14)))
    }
}

#Preview {
    SpeedView().frame(width: 1024, height: 800)
}
