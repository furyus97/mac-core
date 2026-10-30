import SwiftUI
import AppKit

// MARK: - View model

@MainActor
final class DuplicatesViewModel: ObservableObject {
    @Published var roots: [URL]
    @Published private(set) var isScanning = false
    @Published private(set) var progress = DuplicateScanProgress.idle
    @Published private(set) var groups: [DuplicateGroup] = []
    @Published private(set) var hasScanned = false
    @Published private(set) var truncated = false
    @Published private(set) var finishedAt: Date?
    @Published private(set) var wasCancelled = false
    /// Group id → URL of the copy that will be kept.
    @Published private(set) var keepers: [String: URL] = [:]
    @Published private(set) var selection: Set<URL> = []
    @Published var visibleGroupCount = 60

    // Review / removal
    @Published var showReview = false
    @Published private(set) var pending: [DuplicateFile] = []
    @Published private(set) var isTrashing = false
    @Published private(set) var lastOutcome: CleanOutcome?

    private let services: AppServices
    private let home: URL
    private var removable: [URL: Bool] = [:]
    private var scanTask: Task<Void, Never>?
    private var generation = UUID()

    init(services: AppServices? = nil, home: URL = FileManager.default.homeDirectoryForCurrentUser) {
        self.services = services ?? .shared
        self.home = home
        self.roots = Self.existing(DuplicateFinder.defaultRoots(home: home))
    }

    private static func existing(_ urls: [URL]) -> [URL] {
        urls.filter { FileManager.default.fileExists(atPath: $0.path(percentEncoded: false)) }
    }

    // MARK: Derived

    var wastedBytes: Int64 { groups.reduce(0) { $0 + $1.wastedBytes } }
    var extraCopies: Int { groups.reduce(0) { $0 + $1.files.count - 1 } }
    var selectedFiles: [DuplicateFile] {
        groups.flatMap { $0.files }.filter { selection.contains($0.url) }
    }
    var selectedBytes: Int64 { selectedFiles.reduce(0) { $0 + $1.size } }

    func keeper(of group: DuplicateGroup) -> URL { keepers[group.id] ?? group.suggestedKeeper.url }
    func isKeeper(_ file: DuplicateFile, in group: DuplicateGroup) -> Bool { keeper(of: group) == file.url }
    func canTrash(_ file: DuplicateFile) -> Bool { removable[file.url] ?? false }

    /// Group files with the chosen keeper first.
    func orderedFiles(_ group: DuplicateGroup) -> [DuplicateFile] {
        let keep = keeper(of: group)
        return group.files.filter { $0.url == keep } + group.files.filter { $0.url != keep }
    }

    // MARK: Roots

    func addFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        panel.directoryURL = home
        panel.prompt = tr("dup.choose")
        panel.message = tr("dup.panel.message")
        guard panel.runModal() == .OK else { return }
        for url in panel.urls.map(\.standardizedFileURL) where !roots.contains(url) {
            roots.append(url)
        }
    }

    func removeRoot(_ url: URL) { roots.removeAll { $0 == url } }
    func resetRoots() { roots = Self.existing(DuplicateFinder.defaultRoots(home: home)) }

    // MARK: Scan

    func scan() {
        guard !isTrashing, !roots.isEmpty else { return }
        scanTask?.cancel()
        let gen = UUID()
        generation = gen
        isScanning = true
        hasScanned = true
        wasCancelled = false
        progress = .idle
        groups = []
        selection = []
        keepers = [:]
        lastOutcome = nil
        visibleGroupCount = 60
        let roots = self.roots, home = self.home
        let safety = services.safety

        let report: @Sendable (DuplicateScanProgress) -> Void = { [weak self] value in
            Task { @MainActor in
                guard let self, self.generation == gen else { return }
                self.progress = value
            }
        }
        scanTask = Task { [weak self] in
            let result = await DuplicateFinder.scan(roots: roots, home: home, progress: report)
            // Precompute which files the safety policy lets us trash (off the main thread).
            let allowed: [URL: Bool] = await Task.detached(priority: .userInitiated) {
                var map: [URL: Bool] = [:]
                for file in result.groups.flatMap(\.files) {
                    map[file.url] = safety.isRemovable(file.url, scope: .userFiles)
                }
                return map
            }.value
            guard let self, self.generation == gen else { return }
            self.removable = allowed
            self.groups = result.groups
            self.truncated = result.truncated
            self.wasCancelled = result.cancelled
            self.finishedAt = Date()
            self.isScanning = false
        }
    }

    func cancelScan() {
        generation = UUID()
        scanTask?.cancel()
        isScanning = false
        wasCancelled = true
        finishedAt = Date()
    }

    // MARK: Selection

    /// Select every copy except each group's keeper (only files we may trash).
    func selectDuplicates() {
        var next = Set<URL>()
        for group in groups {
            let keep = keeper(of: group)
            for file in group.files where file.url != keep && canTrash(file) { next.insert(file.url) }
        }
        selection = next
    }

    func clearSelection() { selection = [] }

    func toggle(_ file: DuplicateFile, in group: DuplicateGroup) {
        guard !isKeeper(file, in: group), canTrash(file) else { return }
        if selection.contains(file.url) { selection.remove(file.url) } else { selection.insert(file.url) }
    }

    func setKeeper(_ file: DuplicateFile, in group: DuplicateGroup) {
        keepers[group.id] = file.url
        selection.remove(file.url)
    }

    // MARK: Removal

    func review() {
        let files = selectedFiles
        guard !files.isEmpty, !isScanning, !isTrashing else { return }
        pending = files
        showReview = true
    }

    func cancelReview() {
        showReview = false
        pending = []
    }

    func confirmTrash() async {
        let files = pending
        guard !files.isEmpty, !isTrashing else { return }
        isTrashing = true
        showReview = false
        defer { isTrashing = false }

        let outcome = await DuplicateFinder.trash(files, in: groups, cleaner: services.cleaner)
        lastOutcome = outcome
        let failed = Set(outcome.failures.map(\.url))
        let trashed = Set(files.map(\.url)).subtracting(failed)
        groups = groups.compactMap { group in
            let remaining = group.files.filter { !trashed.contains($0.url) }
            return remaining.count > 1 ? DuplicateGroup(id: group.id, size: group.size, files: remaining) : nil
        }
        selection.subtract(trashed)
        selection = selection.intersection(Set(groups.flatMap { $0.files.map(\.url) }))
        pending = []
    }
}

// MARK: - Screen

/// Duplicates: finds byte-identical files, lets the user choose which copies
/// to drop, and moves them to the Trash after an explicit review.
struct DuplicatesView: View {
    @StateObject private var vm: DuplicatesViewModel

    init(vm: DuplicatesViewModel? = nil) {
        _vm = StateObject(wrappedValue: vm ?? DuplicatesViewModel())
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                hero
                foldersCard
                if let outcome = vm.lastOutcome { CleanOutcomeBanner(outcome: outcome) }
                content
            }
            .padding(Theme.Spacing.outer)
        }
        .screenBackground()
        .navigationTitle(tr("nav.duplicates"))
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                if vm.isScanning {
                    Button(role: .cancel) { vm.cancelScan() } label: { Label(tr("common.stop"), systemImage: "stop.fill") }
                } else {
                    Button { vm.scan() } label: { Label(tr("common.scan"), systemImage: "arrow.clockwise") }
                        .disabled(vm.roots.isEmpty || vm.isTrashing)
                }
            }
        }
        .safeAreaInset(edge: .bottom) { bottomBar }
        .onDisappear { if vm.isScanning { vm.cancelScan() } }
        .sheet(isPresented: $vm.showReview) {
            DuplicatesReviewSheet(
                files: vm.pending,
                groups: vm.groups,
                keeper: { vm.keeper(of: $0) },
                onConfirm: { Task { await vm.confirmTrash() } },
                onCancel: { vm.cancelReview() }
            )
        }
    }

    // MARK: Hero

    private var hero: some View {
        HStack(alignment: .center, spacing: Theme.Spacing.xl) {
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                statusLine
                if vm.hasScanned || vm.isScanning {
                    Text(tr("dup.hero.label"))
                        .font(.mcCaption)
                        .foregroundStyle(AppColor.secondaryText)
                    Text(ByteFormat.string(fromBytes: vm.wastedBytes))
                        .font(.mcHero(56))
                        .foregroundStyle(AppGradient.brand)
                        .contentTransition(.numericText())
                } else {
                    Text(tr("dup.hero.idle"))
                        .font(.mcHero(34))
                        .foregroundStyle(AppGradient.brand)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if vm.isScanning {
                    scanProgress
                } else if vm.hasScanned {
                    Text(tr("dup.summary", vm.groups.count, vm.extraCopies))
                        .font(.mcCaption)
                        .foregroundStyle(AppColor.secondaryText)
                } else {
                    Button { vm.scan() } label: {
                        Label(tr("dup.start"), systemImage: "magnifyingglass")
                    }
                    .buttonStyle(.primaryGradient)
                    .disabled(vm.roots.isEmpty)
                    .padding(.top, 4)
                }
            }
            Spacer(minLength: 0)
            IconTile(systemName: "square.on.square", size: 72, colors: TileColor.files)
                .shadow(color: Color(hex: "B85A12").opacity(0.25), radius: 14, x: 0, y: 8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(padding: Theme.Spacing.outer, elevated: true)
    }

    @ViewBuilder
    private var statusLine: some View {
        if vm.isScanning {
            StatusEyebrow(text: tr("common.scanning"), color: AppColor.primary)
        } else if vm.wasCancelled {
            StatusEyebrow(text: tr("dup.status.cancelled"), color: AppColor.warning)
        } else if let date = vm.finishedAt {
            StatusEyebrow(text: tr("dup.status.done", DateFormat.time(date)))
        }
    }

    private var scanProgress: some View {
        let p = vm.progress
        let text: String
        switch p.phase {
        case .collecting: text = tr("dup.phase.collecting", p.filesFound)
        case .quickHash: text = tr("dup.phase.quick", p.filesHashed, p.filesToHash)
        case .fullHash, .done:
            text = tr("dup.phase.full", ByteFormat.string(fromBytes: p.bytesHashed), ByteFormat.string(fromBytes: p.bytesToHash))
        }
        return VStack(alignment: .leading, spacing: 6) {
            if p.phase == .collecting {
                ProgressView().progressViewStyle(.linear).frame(maxWidth: 320)
            } else {
                ProgressView(value: p.fraction).frame(maxWidth: 320)
            }
            Text(text).font(.mcMono(11, weight: .medium)).foregroundStyle(AppColor.secondaryText)
        }
    }

    // MARK: Folders

    private var foldersCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            HStack {
                Text(tr("dup.folders")).font(.mcCardTitle)
                Spacer()
                Button(tr("dup.resetFolders")) { vm.resetRoots() }
                    .buttonStyle(.borderless)
                    .foregroundStyle(AppColor.secondaryText)
                    .disabled(vm.isScanning)
                Button { vm.addFolder() } label: { Label(tr("dup.addFolder"), systemImage: "plus") }
                    .buttonStyle(.softCapsule)
                    .disabled(vm.isScanning)
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 170), spacing: Theme.Spacing.sm)],
                      alignment: .leading, spacing: Theme.Spacing.sm) {
                ForEach(vm.roots, id: \.self) { url in
                    HStack(spacing: 6) {
                        Image(systemName: "folder.fill").foregroundStyle(AppColor.primary)
                        Text(SpaceMapService.name(of: url))
                            .font(.system(size: 12, weight: .medium))
                            .lineLimit(1).truncationMode(.middle)
                        Spacer(minLength: 2)
                        Button { vm.removeRoot(url) } label: {
                            Image(systemName: "xmark").font(.system(size: 9, weight: .bold))
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(AppColor.secondaryText)
                        .disabled(vm.isScanning)
                        .help(tr("dup.removeFolder"))
                        .accessibilityLabel(tr("dup.removeFolder"))
                    }
                    .padding(.horizontal, 10).padding(.vertical, 7)
                    .background(Capsule().fill(AppColor.primary.opacity(0.08)))
                    .help(url.path(percentEncoded: false))
                }
            }
            Text(tr("dup.libraryExcluded")).font(.mcCaption).foregroundStyle(AppColor.secondaryText)
        }
        .card()
    }

    // MARK: Results

    @ViewBuilder
    private var content: some View {
        if !vm.hasScanned {
            EmptyStateView(systemImage: "square.on.square", title: tr("dup.idle.title"), message: tr("dup.idle.message"))
        } else if vm.isScanning {
            EmptyView()
        } else if vm.groups.isEmpty {
            if !vm.wasCancelled {
                EmptyStateView(systemImage: "checkmark.circle", title: tr("dup.empty.title"), message: tr("dup.empty.message"))
            }
        } else {
            results
        }
    }

    private var results: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            SectionTitle(text: tr("dup.results", vm.groups.count)) {
                HStack(spacing: Theme.Spacing.sm) {
                    if !vm.selection.isEmpty {
                        Button(tr("dup.clearSelection")) { vm.clearSelection() }
                            .buttonStyle(.borderless)
                            .foregroundStyle(AppColor.secondaryText)
                    }
                    Button { vm.selectDuplicates() } label: {
                        Label(tr("dup.selectDuplicates"), systemImage: "checklist")
                    }
                    .buttonStyle(.softCapsule)
                    .disabled(vm.isTrashing)
                }
            }
            InfoBanner(kind: .info, message: tr("dup.selectionHint"))
            if vm.truncated {
                InfoBanner(kind: .warning, message: tr("dup.truncated", DuplicateFinder.maxFiles))
            }
            LazyVStack(spacing: Theme.Spacing.md) {
                ForEach(vm.groups.prefix(vm.visibleGroupCount)) { group in
                    DuplicateGroupCard(group: group, vm: vm)
                }
            }
            if vm.groups.count > vm.visibleGroupCount {
                Button(tr("dup.showMore")) { vm.visibleGroupCount += 60 }
                    .buttonStyle(.softCapsule)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    // MARK: Bottom bar

    @ViewBuilder
    private var bottomBar: some View {
        if !vm.groups.isEmpty {
            HStack(spacing: Theme.Spacing.md) {
                Text(tr("dup.selected", vm.selection.count, ByteFormat.string(fromBytes: vm.selectedBytes)))
                    .font(.mcBody.weight(.medium))
                    .foregroundStyle(AppColor.primaryText)
                Spacer(minLength: Theme.Spacing.md)
                Button { vm.review() } label: { Label(tr("dup.review"), systemImage: "trash") }
                    .buttonStyle(.primaryGradient)
                    .disabled(vm.selection.isEmpty || vm.isTrashing || vm.isScanning)
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, Theme.Spacing.outer)
            .padding(.vertical, Theme.Spacing.md)
            .background(.bar)
        }
    }
}

// MARK: - Group card

private struct DuplicateGroupCard: View {
    let group: DuplicateGroup
    @ObservedObject var vm: DuplicatesViewModel

    var body: some View {
        let keeper = group.files.first { vm.isKeeper($0, in: group) } ?? group.suggestedKeeper
        let style = SpaceNodeStyle.icon(for: SpaceNode(url: keeper.url, bytes: keeper.size, isDirectory: false))
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack(spacing: Theme.Spacing.md) {
                IconTile(systemName: style.symbol, size: 34, colors: style.colors)
                VStack(alignment: .leading, spacing: 2) {
                    Text(keeper.name).font(.system(size: 14, weight: .semibold)).lineLimit(1).truncationMode(.middle)
                    Text(tr("dup.copies", group.files.count, ByteFormat.string(fromBytes: group.size)))
                        .font(.mcCaption).foregroundStyle(AppColor.secondaryText)
                }
                Spacer(minLength: Theme.Spacing.md)
                Text(tr("dup.wasted", ByteFormat.string(fromBytes: group.wastedBytes)))
                    .font(.system(size: 12, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(Capsule().fill(SpaceNodeStyle.coral))
            }
            Divider().opacity(0.4)
            ForEach(vm.orderedFiles(group)) { file in
                DuplicateFileRow(file: file, group: group, vm: vm)
            }
        }
        .card(padding: Theme.Spacing.lg)
        .hoverLift()
    }
}

private struct DuplicateFileRow: View {
    let file: DuplicateFile
    let group: DuplicateGroup
    @ObservedObject var vm: DuplicatesViewModel

    var body: some View {
        let isKeeper = vm.isKeeper(file, in: group)
        let canTrash = vm.canTrash(file)
        HStack(spacing: Theme.Spacing.sm) {
            Toggle("", isOn: Binding(
                get: { vm.selection.contains(file.url) },
                set: { _ in vm.toggle(file, in: group) }
            ))
            .toggleStyle(.checkbox)
            .labelsHidden()
            .disabled(isKeeper || !canTrash)
            .accessibilityLabel(file.name)

            VStack(alignment: .leading, spacing: 2) {
                Text(file.path)
                    .font(.mcMono(11))
                    .foregroundStyle(AppColor.primaryText)
                    .lineLimit(1).truncationMode(.middle)
                    .help(file.path)
                    .textSelection(.enabled)
                Text(tr("dup.modified", DateFormat.string(file.modified)))
                    .font(.mcMicro).foregroundStyle(AppColor.secondaryText)
            }
            Spacer(minLength: Theme.Spacing.sm)
            if isKeeper {
                Label(tr("dup.keep"), systemImage: "checkmark.seal.fill")
                    .font(.mcMicro.weight(.semibold))
                    .foregroundStyle(AppColor.success)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Capsule().fill(AppColor.success.opacity(0.14)))
            } else {
                if !canTrash {
                    Image(systemName: "lock.fill").font(.system(size: 11))
                        .foregroundStyle(AppColor.secondaryText)
                        .help(tr("dup.viewOnly"))
                        .accessibilityLabel(tr("dup.viewOnly"))
                }
                Button(tr("dup.keepThis")) { vm.setKeeper(file, in: group) }
                    .buttonStyle(.borderless)
                    .font(.mcMicro)
                    .foregroundStyle(AppColor.primary)
            }
            Button { FinderHelper.reveal(file.url) } label: { Image(systemName: "magnifyingglass") }
                .buttonStyle(.borderless)
                .help(tr("common.showInFinder"))
                .accessibilityLabel(tr("common.showInFinder"))
        }
        .padding(.vertical, 2)
        .contextMenu {
            Button(tr("common.showInFinder")) { FinderHelper.reveal(file.url) }
            if !isKeeper { Button(tr("dup.keepThis")) { vm.setKeeper(file, in: group) } }
        }
    }
}

// MARK: - Review sheet

/// Lists every exact path that will move to the Trash (and the copy kept for
/// each group) before anything happens. Trash only — never permanent.
struct DuplicatesReviewSheet: View {
    let files: [DuplicateFile]
    let groups: [DuplicateGroup]
    let keeper: (DuplicateGroup) -> URL
    let onConfirm: () -> Void
    let onCancel: () -> Void

    private var totalBytes: Int64 { files.reduce(0) { $0 + $1.size } }
    private struct ReviewSection: Identifiable {
        let group: DuplicateGroup
        let files: [DuplicateFile]
        var id: String { group.id }
    }

    private var sections: [ReviewSection] {
        let selected = Set(files.map(\.url))
        return groups.compactMap { group in
            let picked = group.files.filter { selected.contains($0.url) }
            return picked.isEmpty ? nil : ReviewSection(group: group, files: picked)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            HStack(spacing: Theme.Spacing.md) {
                IconTile(systemName: "trash.fill", size: 44, colors: TileColor.cleanup)
                VStack(alignment: .leading, spacing: 2) {
                    Text(tr("dup.sheet.title")).font(.title2.bold())
                    Text(tr("dup.sheet.summary", files.count, ByteFormat.string(fromBytes: totalBytes)))
                        .foregroundStyle(.secondary)
                }
            }
            InfoBanner(kind: .info, message: tr("dup.sheet.note"))
            ScrollView {
                LazyVStack(alignment: .leading, spacing: Theme.Spacing.md) {
                    ForEach(sections) { section in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(alignment: .firstTextBaseline, spacing: 6) {
                                Image(systemName: "checkmark.seal.fill").foregroundStyle(AppColor.success)
                                Text(tr("dup.sheet.keeping")).font(.mcMicro.weight(.semibold)).foregroundStyle(AppColor.success)
                                Text(keeper(section.group).path(percentEncoded: false))
                                    .font(.mcMono(11)).foregroundStyle(AppColor.secondaryText)
                                    .textSelection(.enabled)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            ForEach(section.files) { file in
                                HStack(alignment: .firstTextBaseline, spacing: 6) {
                                    Image(systemName: "trash").foregroundStyle(AppColor.danger)
                                    Text(file.path).font(.mcMono(11))
                                        .textSelection(.enabled)
                                        .fixedSize(horizontal: false, vertical: true)
                                    Spacer(minLength: 4)
                                    Text(ByteFormat.string(fromBytes: file.size))
                                        .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                                }
                            }
                        }
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                            .fill(Color.secondary.opacity(0.06)))
                    }
                }
            }
            .frame(minHeight: 160, maxHeight: 340)
            HStack {
                Spacer()
                Button(tr("common.cancel"), role: .cancel, action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button(tr("common.moveToTrash"), action: onConfirm)
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.primaryGradient)
                    .disabled(files.isEmpty)
            }
        }
        .padding(Theme.Spacing.xl)
        .frame(width: 640)
        .background(AppColor.background)
    }
}

#Preview {
    DuplicatesView()
        .frame(width: 1000, height: 800)
}
