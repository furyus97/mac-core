import SwiftUI

/// The Dashboard: Mac Health Score hero, live system metric cards (storage,
/// memory, CPU, battery, network, temperature), and top processes.
@MainActor
struct DashboardView: View {
    @StateObject private var vm: DashboardViewModel
    private let automaticallyRefresh: Bool

    init(vm: DashboardViewModel? = nil, automaticallyRefresh: Bool = true) {
        _vm = StateObject(wrappedValue: vm ?? DashboardViewModel())
        self.automaticallyRefresh = automaticallyRefresh
    }
    @EnvironmentObject private var settings: SettingsStore
    @EnvironmentObject private var nav: NavigationModel
    @State private var detailMetric: DashboardMetric?

    private let columns = [GridItem(.adaptive(minimum: 250), spacing: Theme.Spacing.gridGap)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: Theme.Spacing.gridGap) { hero; spaceCard.frame(width: 380) }
                    VStack(spacing: Theme.Spacing.gridGap) { hero; spaceCard }
                }
                glanceTiles
                SectionTitle(tr("dash.systemSection"))
                LazyVGrid(columns: columns, spacing: Theme.Spacing.gridGap) {
                    metricCards
                }
                topProcesses
                if let outcome = vm.lastOutcome {
                    CleanOutcomeBanner(outcome: outcome)
                }
            }
            .padding(Theme.Spacing.outer)
        }
        .screenBackground()
        .navigationTitle(tr("nav.dashboard"))
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { Task { await vm.quickScan() } } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .help(tr("common.refresh"))
                .disabled(vm.isLoading)
            }
        }
        .task {
            guard automaticallyRefresh else { return }
            if settings.autoScanOnLaunch {
                await vm.quickScan()
            } else {
                await vm.refresh()
            }
            Task { await vm.loadOverview() }
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                guard !Task.isCancelled else { break }
                await vm.refreshLive()
            }
        }
        .sheet(isPresented: $vm.showConfirm) {
            ConfirmCleanSheet(
                items: vm.pendingItems,
                mode: $vm.mode,
                allowPermanent: false,
                onConfirm: { Task { await vm.confirmClean() } },
                onCancel: { vm.cancelClean() }
            )
        }
        .sheet(item: $detailMetric) { metric in
            MetricDetailSheet(
                metric: metric,
                vm: vm,
                onOpenScreen: { nav.selection = $0; detailMetric = nil },
                onClose: { detailMetric = nil }
            )
        }
    }

    // MARK: Hero

    private var hero: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                StatusEyebrow(text: vm.lastScan.map { tr("home.scanComplete", DateFormat.time($0)) } ?? tr("home.notScanned"),
                              color: vm.lastScan == nil ? AppColor.warning : AppColor.success)
                Spacer()
                if !vm.health.components.isEmpty {
                    Label(tr("home.health", vm.health.score), systemImage: "heart.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(StatusColor.forScore(vm.health.score))
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(Capsule().fill(StatusColor.forScore(vm.health.score).opacity(0.12)))
                }
            }
            VStack(alignment: .leading, spacing: 2) {
                if vm.lastScan != nil {
                    Text(tr("home.ready")).font(.system(size: 22, weight: .semibold, design: .rounded)).foregroundStyle(AppColor.primaryText)
                }
                reclaimableValue
            }
            Text(tr("home.readyBody")).font(.mcBody).foregroundStyle(AppColor.secondaryText)
                .fixedSize(horizontal: false, vertical: true).frame(maxWidth: 420, alignment: .leading)
            Spacer(minLength: 0)
            scanActions
        }
        .frame(maxWidth: .infinity, minHeight: 300, alignment: .topLeading)
        .card(padding: 28, elevated: true)
        .background(alignment: .bottomTrailing) {
            Circle().fill(Color(hex: "F7B6D2").opacity(0.35)).frame(width: 260).blur(radius: 70).offset(x: 40, y: 60)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card)).allowsHitTesting(false)
        }
    }

    @ViewBuilder
    private var reclaimableValue: some View {
        if vm.isEstimating {
            HStack(spacing: 12) { ProgressView().controlSize(.small); Text(tr("common.scanning")).font(.mcCaption) }.frame(height: 80)
        } else if vm.lastScan == nil {
            Text(tr("home.scanPrompt"))
                .font(.mcHero(46)).foregroundStyle(AppGradient.brand)
                .lineLimit(2).minimumScaleFactor(0.6)
        } else {
            let parts = ByteFormat.string(fromBytes: vm.reclaimable).split(separator: " ", maxSplits: 1).map(String.init)
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(parts.first ?? "0").font(.mcHero(72)).foregroundStyle(AppGradient.brand)
                Text(parts.count > 1 ? parts[1] : "").font(.system(size: 26, weight: .bold, design: .rounded)).foregroundStyle(AppColor.primary)
            }
            .lineLimit(1).minimumScaleFactor(0.5)
            .accessibilityElement(children: .combine)
        }
    }

    @ViewBuilder
    private var scanActions: some View {
        if vm.lastScan == nil && !vm.isEstimating {
            Button { Task { await vm.quickScan(); await vm.loadOverview(force: true) } } label: {
                Label(tr("home.scanNow"), systemImage: "sparkle.magnifyingglass")
            }
            .buttonStyle(.primaryGradient)
            .disabled(vm.isLoading || vm.isCleaning)
        } else {
            cleanActions
        }
    }

    private var cleanActions: some View {
        HStack(spacing: 14) {
            Button { Task { await vm.safeClean() } } label: {
                HStack(spacing: 10) {
                    Image(systemName: "sparkles").font(.system(size: 13, weight: .bold))
                    VStack(alignment: .leading, spacing: 0) {
                        Text(tr("home.clean"))
                        Text(ByteFormat.string(fromBytes: vm.reclaimable)).font(.mcMono(10)).opacity(0.85)
                    }
                }
            }
            .buttonStyle(.primaryGradient)
            .disabled(vm.isLoading || vm.isPreparingClean || vm.isCleaning)
            Button { nav.selection = .smartScan } label: {
                Label(tr("home.review"), systemImage: "arrow.right").labelStyle(TrailingIconLabelStyle())
            }
            .buttonStyle(.plain).font(.system(size: 13, weight: .semibold)).foregroundStyle(AppColor.primary)
            Spacer(minLength: 8)
            Button { Task { await vm.quickScan(); await vm.loadOverview(force: true) } } label: {
                Label(tr("home.scanAgain"), systemImage: "arrow.clockwise")
            }
            .buttonStyle(.softCapsule)
            .disabled(vm.isLoading || vm.isEstimating || vm.isPreparingClean || vm.isCleaning)
        }
    }

    private var spaceCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(tr("home.spaceMap")).font(.mcCardTitle)
                Spacer()
                Button(tr("home.open") + " ›") { nav.selection = .spaceMap }.buttonStyle(.plain)
                    .font(.system(size: 12, weight: .semibold)).foregroundStyle(AppColor.primary)
            }
            if vm.spaceNodes.isEmpty {
                VStack(spacing: 10) { ProgressView().controlSize(.small); Text(tr("common.scanning")).font(.mcCaption).foregroundStyle(AppColor.secondaryText) }
                    .frame(maxWidth: .infinity, minHeight: 240)
            } else {
                SpaceBubbleChart(nodes: vm.spaceNodes, onSelect: { _ in nav.selection = .spaceMap })
                    .frame(minHeight: 240)
            }
            Text(tr("home.diskSummary", ByteFormat.string(fromBytes: vm.disk.freeBytes), ByteFormat.string(fromBytes: vm.disk.totalBytes)))
                .font(.mcMono(10)).foregroundStyle(AppColor.secondaryText)
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .card(padding: 22, elevated: true)
    }

    // MARK: At a glance

    private var glanceTiles: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: Theme.Spacing.gridGap) { tiles.frame(minWidth: 190) }
            Grid(horizontalSpacing: Theme.Spacing.gridGap, verticalSpacing: Theme.Spacing.gridGap) {
                GridRow { cleanupTile; speedTile }
                GridRow { protectionTile; appsTile }
            }
        }
    }

    @ViewBuilder private var tiles: some View { cleanupTile; speedTile; protectionTile; appsTile }

    private var cleanupTile: some View {
        let parts = ByteFormat.string(fromBytes: vm.reclaimable).split(separator: " ", maxSplits: 1).map(String.init)
        let scanned = vm.lastScan != nil
        return GlanceTile(title: tr("tile.cleanup.title"), icon: "trash.fill", colors: TileColor.cleanup,
                          value: scanned ? (parts.first ?? "—") : "—", unit: scanned && parts.count > 1 ? parts[1] : nil,
                          caption: tr("tile.cleanup.caption"), action: tr("tile.cleanup.action")) { nav.selection = .storage }
    }
    private var speedTile: some View {
        GlanceTile(title: tr("tile.speed.title"), icon: "bolt.fill", colors: TileColor.speed,
                   value: vm.startupCount.map(String.init) ?? "—", unit: tr("tile.speed.unit"),
                   caption: tr("tile.speed.caption"), action: tr("tile.speed.action")) { nav.selection = .speed }
    }
    private var protectionTile: some View {
        GlanceTile(title: tr("tile.protection.title"), icon: "checkmark.shield.fill", colors: TileColor.protection,
                   value: vm.protectionScore.map(String.init) ?? "—", unit: "/ 100",
                   caption: tr("tile.protection.caption"), action: tr("tile.protection.action")) { nav.selection = .protection }
    }
    private var appsTile: some View {
        GlanceTile(title: tr("tile.apps.title"), icon: "square.grid.2x2.fill", colors: TileColor.apps,
                   value: vm.appCount.map(String.init) ?? "—", unit: tr("tile.apps.unit"),
                   caption: tr("tile.apps.caption", vm.unusedAppCount), action: tr("tile.apps.action")) { nav.selection = .applications }
    }

    // MARK: Metric cards

    @ViewBuilder
    private var metricCards: some View {
        // Storage
        MetricCard(
            title: tr("dash.card.storage"), icon: "externaldrive.fill", tint: .blue,
            value: ByteFormat.string(fromBytes: vm.disk.freeBytes), unit: tr("dash.unit.free"),
            progress: vm.disk.usedFraction,
            statusText: tr("dash.storage.usedStatus", ByteFormat.percent(vm.disk.usedFraction)),
            statusColor: StatusColor.forUsage(vm.disk.usedFraction),
            action: { detailMetric = .storage }
        )
        // Memory
        MetricCard(
            title: tr("dash.card.memory"), icon: "memorychip.fill", tint: .purple,
            value: ByteFormat.string(fromBytes: vm.memory.usedBytes), unit: tr("dash.unit.used"),
            progress: vm.memory.usedFraction,
            samples: vm.memHistory,
            statusText: tr("dash.memory.pressure", vm.memory.pressure.title),
            statusColor: vm.memory.pressure.tint,
            action: { detailMetric = .memory }
        )
        // CPU
        MetricCard(
            title: tr("dash.card.cpu"), icon: "cpu.fill", tint: .orange,
            value: ByteFormat.percent(vm.cpu.totalUsage), unit: nil,
            progress: vm.cpu.totalUsage,
            samples: vm.cpuHistory,
            statusText: tr("dash.cpu.coresUser", vm.cpu.coreCount, ByteFormat.percent(vm.cpu.userUsage)),
            statusColor: StatusColor.forUsage(vm.cpu.totalUsage),
            action: { detailMetric = .cpu }
        )
        // Battery
        batteryCard
        // Network
        MetricCard(
            title: tr("dash.card.network"), icon: "network", tint: .teal,
            value: ByteFormat.networkBytes(vm.network.downBytesPerSec), unit: "/s ↓",
            caption: tr("dash.network.upCaption", ByteFormat.networkBytes(vm.network.upBytesPerSec), vm.network.primaryInterface),
            samples: vm.netHistory,
            action: { detailMetric = .network }
        )
        // Temperature (real sensor via IOKit; honest fallback if unreadable)
        temperatureCard
    }

    @ViewBuilder
    private var temperatureCard: some View {
        let source = settings.temperatureSource
        if let value = vm.temperature.value(for: source) {
            MetricCard(
                title: tr("dash.card.temperature"),
                icon: "thermometer.medium",
                tint: temperatureTint(value),
                value: ByteFormat.temperature(value),
                caption: tr(source.titleKey),
                action: { detailMetric = .temperature }
            )
        } else {
            MetricCard(
                title: tr("dash.card.temperature"), icon: "thermometer.medium", tint: .gray,
                value: tr("dash.temp.unavailable"),
                caption: tr(vm.temperature.isAvailable ? "sensor.sourceUnavailable" : "dash.temp.unsupported"),
                action: { detailMetric = .temperature }
            )
        }
    }

    private func temperatureTint(_ celsius: Double) -> Color {
        switch celsius {
        case ..<60: return AppColor.success
        case ..<80: return AppColor.warning
        default:    return AppColor.danger
        }
    }

    @ViewBuilder
    private var batteryCard: some View {
        if vm.battery.isPresent {
            MetricCard(
                title: tr("dash.card.battery"), icon: vm.battery.isCharging ? "battery.100.bolt" : "battery.75",
                tint: .green,
                value: "\(vm.battery.percentage)", unit: "%",
                progress: Double(vm.battery.percentage) / 100,
                statusText: vm.battery.isCharging ? tr("dash.battery.charging") : (vm.battery.isPluggedIn ? tr("dash.battery.pluggedIn") : tr("dash.battery.onBattery")),
                statusColor: vm.battery.percentage < 20 ? AppColor.danger : AppColor.success,
                action: { detailMetric = .battery }
            )
        } else {
            MetricCard(
                title: tr("dash.card.battery"), icon: "powerplug.fill", tint: .gray,
                value: "AC", caption: tr("dash.battery.noBattery"),
                action: { detailMetric = .battery }
            )
        }
    }

    // MARK: Top processes

    private var topProcesses: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            SectionTitle(tr("dash.topProcesses"))
            VStack(spacing: 0) {
                if vm.topProcesses.isEmpty {
                    Text(tr("dash.measuring")).font(.mcCaption).foregroundStyle(AppColor.secondaryText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    ForEach(vm.topProcesses) { p in
                        ProcessRow(process: p, metric: .cpu)
                        if p.id != vm.topProcesses.last?.id { Divider().opacity(0.4) }
                    }
                }
            }
            .card()
        }
    }
}

#Preview {
    DashboardView()
        .environmentObject(AppServices.shared.settings)
        .frame(width: 1024, height: 800)
}
