import SwiftUI

// MARK: - View model

/// Drives the read-only Space Map: measures the current folder's direct
/// children, keeps a breadcrumb stack for drill-down, and caches complete
/// listings so going back is instant.
@MainActor
final class SpaceMapViewModel: ObservableObject {
    @Published private(set) var path: [URL]
    @Published private(set) var listing: SpaceListing = .empty
    @Published private(set) var isLoading = false
    @Published private(set) var measured = 0
    @Published private(set) var total = 0
    @Published private(set) var volume: VolumeSummary?
    @Published private(set) var lastMeasured: Date?

    let root: URL
    let limit: Int
    private var cache: [URL: (SpaceListing, Date)] = [:]
    private var task: Task<Void, Never>?
    private var generation = UUID()

    init(root: URL = SpaceMapService.defaultRoot, limit: Int = 12) {
        self.root = root.standardizedFileURL
        self.limit = limit
        self.path = [root.standardizedFileURL]
    }

    var current: URL { path.last ?? root }
    var canGoUp: Bool { path.count > 1 }

    func start() {
        volume = SpaceMapService.volumeSummary()
        if listing.nodes.isEmpty && !isLoading { load() }
    }

    func open(_ node: SpaceNode) {
        guard node.isDirectory else { return }
        path.append(node.url.standardizedFileURL)
        load()
    }

    func goUp() {
        guard canGoUp else { return }
        path.removeLast()
        load()
    }

    func jump(to index: Int) {
        guard path.indices.contains(index), index != path.count - 1 else { return }
        path = Array(path.prefix(index + 1))
        load()
    }

    func refresh() {
        cache[current] = nil
        volume = SpaceMapService.volumeSummary()
        load()
    }

    func cancel() {
        generation = UUID()
        task?.cancel()
        isLoading = false
        listing.isPartial = true
    }

    private func load() {
        task?.cancel()
        let target = current
        let gen = UUID()
        generation = gen
        if let entry = cache[target] {
            listing = entry.0
            lastMeasured = entry.1
            isLoading = false
            return
        }
        listing = .empty
        measured = 0
        total = 0
        isLoading = true
        let limit = self.limit
        let report: @Sendable (SpaceMapProgress) -> Void = { [weak self] progress in
            Task { @MainActor in
                guard let self, self.generation == gen else { return }
                self.measured = progress.measuredChildren
                self.total = progress.totalChildren
                self.listing = progress.partial
            }
        }
        task = Task { [weak self] in
            let result = await SpaceMapService.listing(of: target, limit: limit, progress: report)
            guard let self, self.generation == gen, !Task.isCancelled else { return }
            self.listing = result
            self.isLoading = false
            let now = Date()
            self.lastMeasured = now
            if !result.isPartial { self.cache[target] = (result, now) }
        }
    }

    func title(for url: URL) -> String {
        url.standardizedFileURL.path == root.path
            ? tr("spacemap.home")
            : SpaceMapService.name(of: url)
    }
}

// MARK: - Screen

/// Space Map: a read-only, drillable bubble map of what fills the disk.
struct SpaceMapView: View {
    @StateObject private var vm: SpaceMapViewModel

    init(root: URL = SpaceMapService.defaultRoot) {
        _vm = StateObject(wrappedValue: SpaceMapViewModel(root: root))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.gridGap) {
            volumeCard
            HStack(alignment: .top, spacing: Theme.Spacing.gridGap) {
                chartCard
                listCard.frame(width: 300)
            }
            .frame(maxHeight: .infinity)
        }
        .padding(Theme.Spacing.outer)
        .screenBackground()
        .navigationTitle(tr("nav.spaceMap"))
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                if vm.isLoading {
                    Button(role: .cancel) { vm.cancel() } label: { Label(tr("common.stop"), systemImage: "stop.fill") }
                } else {
                    Button { vm.refresh() } label: { Label(tr("common.refresh"), systemImage: "arrow.clockwise") }
                }
            }
        }
        .task { vm.start() }
        .onDisappear { if vm.isLoading { vm.cancel() } }
    }

    // MARK: Volume

    @ViewBuilder
    private var volumeCard: some View {
        HStack(spacing: Theme.Spacing.lg) {
            IconTile(systemName: "internaldrive.fill", size: 40, colors: TileColor.system)
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    Text(tr("spacemap.startupDisk")).eyebrow()
                    if let volume = vm.volume {
                        Text(volume.name).font(.mcBodyMedium).foregroundStyle(AppColor.primaryText)
                    }
                    Spacer(minLength: Theme.Spacing.md)
                    if let volume = vm.volume {
                        Text(tr("spacemap.volumeUsage",
                                ByteFormat.string(fromBytes: volume.usedBytes),
                                ByteFormat.string(fromBytes: volume.availableBytes),
                                ByteFormat.string(fromBytes: volume.totalBytes)))
                            .font(.mcMono(12, weight: .medium))
                            .foregroundStyle(AppColor.secondaryText)
                    }
                }
                usageBar(fraction: vm.volume?.usedFraction ?? 0)
            }
        }
        .card(padding: Theme.Spacing.lg)
    }

    private func usageBar(fraction: Double) -> some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(AppColor.primary.opacity(0.10))
                Capsule().fill(AppGradient.brand)
                    .frame(width: max(6, geo.size.width * min(max(fraction, 0), 1)))
            }
        }
        .frame(height: 8)
        .accessibilityElement()
        .accessibilityLabel(tr("spacemap.startupDisk"))
        .accessibilityValue(ByteFormat.percent(fraction))
    }

    // MARK: Chart

    private var chartCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            HStack(alignment: .center, spacing: Theme.Spacing.sm) {
                Button { vm.goUp() } label: {
                    Image(systemName: "chevron.left").font(.system(size: 13, weight: .semibold))
                        .frame(width: 28, height: 28)
                        .background(Circle().fill(AppColor.primary.opacity(vm.canGoUp ? 0.10 : 0.04)))
                        .foregroundStyle(vm.canGoUp ? AppColor.primary : AppColor.secondaryText)
                }
                .buttonStyle(.plain)
                .disabled(!vm.canGoUp)
                .help(tr("spacemap.up"))
                .accessibilityLabel(tr("spacemap.up"))
                .keyboardShortcut(.upArrow, modifiers: .command)
                breadcrumb
                Spacer(minLength: Theme.Spacing.md)
                Text(ByteFormat.string(fromBytes: vm.listing.totalBytes))
                    .font(.mcMetric(28))
                    .foregroundStyle(AppGradient.brand)
                    .contentTransition(.numericText())
            }
            status
            ZStack {
                if vm.listing.nodes.isEmpty && !vm.isLoading {
                    EmptyStateView(systemImage: "folder", title: tr("spacemap.empty.title"),
                                   message: tr("spacemap.empty.message"))
                } else if vm.listing.nodes.isEmpty {
                    ProgressView().controlSize(.large)
                } else {
                    SpaceBubbleChart(nodes: vm.listing.nodes) { node in
                        if node.isDirectory { vm.open(node) } else { FinderHelper.reveal(node.url) }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .frame(minHeight: 300)
            Label(tr("spacemap.hint"), systemImage: "hand.tap")
                .font(.mcCaption)
                .foregroundStyle(AppColor.secondaryText)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .card(elevated: true)
    }

    private var breadcrumb: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(Array(vm.path.enumerated()), id: \.offset) { index, url in
                        if index > 0 {
                            Image(systemName: "chevron.right").font(.system(size: 9, weight: .bold))
                                .foregroundStyle(AppColor.secondaryText.opacity(0.7))
                        }
                        let isLast = index == vm.path.count - 1
                        Button { vm.jump(to: index) } label: {
                            HStack(spacing: 4) {
                                if index == 0 { Image(systemName: "house.fill").font(.system(size: 11)) }
                                Text(vm.title(for: url)).lineLimit(1)
                            }
                            .font(.system(size: 13, weight: isLast ? .semibold : .medium))
                            .foregroundStyle(isLast ? AppColor.primaryText : AppColor.primary)
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .background(Capsule().fill(isLast ? AppColor.primary.opacity(0.10) : .clear))
                        }
                        .buttonStyle(.plain)
                        .disabled(isLast)
                        .id(index)
                    }
                }
            }
            .onChange(of: vm.path) { _, path in
                proxy.scrollTo(path.count - 1, anchor: .trailing)
            }
        }
    }

    @ViewBuilder
    private var status: some View {
        if vm.isLoading {
            HStack(spacing: Theme.Spacing.sm) {
                ProgressView(value: vm.total > 0 ? Double(vm.measured) / Double(vm.total) : 0)
                    .frame(maxWidth: 200)
                Text(tr("spacemap.measuring", vm.measured, vm.total))
                    .font(.mcCaption)
                    .foregroundStyle(AppColor.secondaryText)
            }
        } else if vm.listing.isPartial {
            StatusEyebrow(text: tr("spacemap.partial"), color: AppColor.warning)
        } else if let date = vm.lastMeasured {
            StatusEyebrow(text: tr("spacemap.measured", DateFormat.time(date)))
        }
    }

    // MARK: Side list

    private var listCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Text(tr("spacemap.largest")).font(.mcCardTitle)
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(vm.listing.nodes) { node in
                        SpaceListRow(node: node, total: max(vm.listing.totalBytes, 1)) { vm.open(node) }
                    }
                    if vm.listing.remainderCount > 0 {
                        Text(tr("spacemap.more", vm.listing.remainderCount,
                                ByteFormat.string(fromBytes: vm.listing.remainderBytes)))
                            .font(.mcCaption)
                            .foregroundStyle(AppColor.secondaryText)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 8).padding(.top, 8)
                    }
                }
            }
            Label(tr("spacemap.readOnly"), systemImage: "lock.shield")
                .font(.mcMicro)
                .foregroundStyle(AppColor.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .card(padding: Theme.Spacing.lg)
    }
}

/// One row of the side list: icon, name, size share bar and Finder action.
private struct SpaceListRow: View {
    let node: SpaceNode
    let total: Int64
    let onOpen: () -> Void
    @State private var hovering = false

    var body: some View {
        let style = SpaceNodeStyle.icon(for: node)
        let fraction = Double(node.bytes) / Double(total)
        HStack(spacing: Theme.Spacing.sm) {
            IconTile(systemName: style.symbol, size: 30, colors: style.colors)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(node.name).font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(AppColor.primaryText)
                        .lineLimit(1).truncationMode(.middle)
                    Spacer(minLength: 4)
                    Text(ByteFormat.string(fromBytes: node.bytes))
                        .font(.mcMono(11, weight: .medium))
                        .foregroundStyle(AppColor.secondaryText)
                }
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(AppColor.primary.opacity(0.08))
                        Capsule().fill(AppGradient.tile(style.colors))
                            .frame(width: max(3, geo.size.width * min(max(fraction, 0), 1)))
                    }
                }
                .frame(height: 4)
                if let reclaim = node.reclaimableBytes, reclaim > 0 {
                    Text(tr("spacemap.reclaimable", ByteFormat.string(fromBytes: reclaim)))
                        .font(.mcMicro)
                        .foregroundStyle(Color(hex: "E5486A"))
                }
            }
            Button { FinderHelper.reveal(node.url) } label: {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11, weight: .semibold))
                    .frame(width: 24, height: 24)
                    .background(Circle().fill(AppColor.primary.opacity(hovering ? 0.12 : 0.06)))
                    .foregroundStyle(AppColor.primary)
            }
            .buttonStyle(.plain)
            .help(tr("common.showInFinder"))
            .accessibilityLabel(tr("common.showInFinder"))
            if node.isDirectory {
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(AppColor.secondaryText.opacity(0.7))
            }
        }
        .padding(.horizontal, 8).padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
            .fill(hovering ? AppColor.primary.opacity(0.06) : .clear))
        .contentShape(Rectangle())
        .onTapGesture { if node.isDirectory { onOpen() } }
        .onHover { hovering = $0 }
        .contextMenu {
            if node.isDirectory { Button(tr("spacemap.open"), action: onOpen) }
            Button(tr("common.showInFinder")) { FinderHelper.reveal(node.url) }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(node.isDirectory ? .isButton : [])
    }
}

#Preview {
    SpaceMapView()
        .frame(width: 1000, height: 760)
}
