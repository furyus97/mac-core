import SwiftUI

/// Which dashboard metric a detail sheet is showing.
enum DashboardMetric: String, Identifiable {
    case storage, memory, cpu, battery, network, temperature
    var id: String { rawValue }

    var titleKey: String {
        switch self {
        case .storage: return "dash.card.storage"
        case .memory: return "dash.card.memory"
        case .cpu: return "dash.card.cpu"
        case .battery: return "dash.card.battery"
        case .network: return "dash.card.network"
        case .temperature: return "dash.card.temperature"
        }
    }
    var icon: String {
        switch self {
        case .storage: return "externaldrive.fill"
        case .memory: return "memorychip.fill"
        case .cpu: return "cpu.fill"
        case .battery: return "battery.100"
        case .network: return "network"
        case .temperature: return "thermometer.medium"
        }
    }
    var tint: Color {
        switch self {
        case .storage: return .blue
        case .memory: return .purple
        case .cpu: return .orange
        case .battery: return .green
        case .network: return .teal
        case .temperature: return .pink
        }
    }
    /// The full screen this metric maps to, if any.
    var screen: NavItem? {
        switch self {
        case .storage: return .storage
        case .memory: return .memory
        case .cpu: return .cpu
        case .temperature: return .temperature
        case .battery: return .battery
        case .network: return .network
        }
    }
}

/// A focused detail view for a single dashboard metric.
struct MetricDetailSheet: View {
    let metric: DashboardMetric
    @ObservedObject var vm: DashboardViewModel
    var onOpenScreen: (NavItem) -> Void
    var onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                    content
                }
                .padding(Theme.Spacing.xl)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            Divider()
            footer
        }
        .frame(width: 620, height: 650)
        .background(AppColor.background)
    }

    private var header: some View {
        HStack(spacing: Theme.Spacing.md) {
            IconTile(systemName: metric.icon, tint: metric.tint, size: 40)
            Text(tr(metric.titleKey)).font(.mcSectionTitle)
            Spacer()
            Button(action: onClose) { Image(systemName: "xmark.circle.fill").font(.title2).foregroundStyle(.secondary) }
                .buttonStyle(.plain)
        }
        .padding(Theme.Spacing.xl)
    }

    @ViewBuilder
    private var content: some View {
        switch metric {
        case .storage: storageDetail
        case .memory: memoryDetail
        case .cpu: cpuDetail
        case .battery: BatteryInspector(battery: vm.battery)
        case .network: networkDetail
        case .temperature: SensorInspector(snapshot: vm.temperature)
        }
    }

    // MARK: Per-metric content

    private var storageDetail: some View {
        VStack(spacing: Theme.Spacing.lg) {
            RingGauge(fraction: vm.disk.usedFraction, caption: tr("dash.card.storage"), tint: metric.tint)
                .frame(width: 130, height: 130)
            VStack(spacing: 0) {
                row("detail.volume", vm.disk.volumeName)
                row("detail.total", ByteFormat.string(fromBytes: vm.disk.totalBytes))
                row("detail.used", ByteFormat.string(fromBytes: vm.disk.usedBytes))
                row("detail.free", ByteFormat.string(fromBytes: vm.disk.freeBytes))
                row("detail.usage", ByteFormat.percent(vm.disk.usedFraction))
                row("dash.reclaimable", ByteFormat.string(fromBytes: vm.reclaimable), tint: AppColor.success)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var memoryDetail: some View {
        VStack(spacing: Theme.Spacing.lg) {
            RingGauge(fraction: vm.memory.usedFraction, caption: tr("dash.card.memory"), tint: vm.memory.pressure.tint)
                .frame(width: 130, height: 130)
            VStack(spacing: 0) {
                row("detail.used", ByteFormat.string(fromBytes: vm.memory.usedBytes))
                row("detail.total", ByteFormat.string(fromBytes: vm.memory.totalBytes))
                row("detail.free", ByteFormat.string(fromBytes: vm.memory.freeBytes))
                row("detail.app", ByteFormat.string(fromBytes: vm.memory.appBytes))
                row("detail.wired", ByteFormat.string(fromBytes: vm.memory.wiredBytes))
                row("detail.compressed", ByteFormat.string(fromBytes: vm.memory.compressedBytes))
                row("detail.cache", ByteFormat.string(fromBytes: vm.memory.cachedBytes))
                row("detail.swap", ByteFormat.string(fromBytes: vm.memory.swapUsedBytes))
                row("detail.pressure", vm.memory.pressure.title, tint: vm.memory.pressure.tint)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var cpuDetail: some View {
        VStack(spacing: Theme.Spacing.lg) {
            RingGauge(fraction: vm.cpu.totalUsage, caption: tr("dash.card.cpu"), tint: metric.tint)
                .frame(width: 130, height: 130)
            VStack(spacing: 0) {
                row("cpu.user", ByteFormat.percent(vm.cpu.userUsage))
                row("cpu.system", ByteFormat.percent(vm.cpu.systemUsage))
                row("cpu.idle", ByteFormat.percent(vm.cpu.idle))
                row("cpu.cores", "\(vm.cpu.coreCount)")
            }
            if !vm.cpu.coreUsages.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text(tr("cpu.perCore")).eyebrow()
                    ForEach(vm.cpu.coreUsages.indices, id: \.self) { i in
                        HStack(spacing: Theme.Spacing.sm) {
                            Text(tr("cpu.core", i + 1)).font(.mcMono(11)).frame(width: 52, alignment: .leading)
                            UsageBar(fraction: vm.cpu.coreUsages[i], height: 5)
                            Text(ByteFormat.percent(vm.cpu.coreUsages[i])).font(.mcMono(11)).frame(width: 40, alignment: .trailing)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var networkDetail: some View {
        VStack(spacing: 0) {
            row("detail.interface", vm.network.primaryInterface)
            row("detail.downSpeed", ByteFormat.networkRate(vm.network.downBytesPerSec))
            row("detail.upSpeed", ByteFormat.networkRate(vm.network.upBytesPerSec))
            row("detail.totalDown", ByteFormat.networkBytes(Double(vm.network.totalDownBytes)))
            row("detail.totalUp", ByteFormat.networkBytes(Double(vm.network.totalUpBytes)))
        }
    }

    // MARK: Row helper

    private func row(_ labelKey: String, _ value: String, tint: Color? = nil) -> some View {
        VStack(spacing: 0) {
            HStack {
                Text(tr(labelKey)).font(.mcBody).foregroundStyle(AppColor.secondaryText)
                Spacer()
                Text(value).font(.mcMono(14, weight: .medium)).foregroundStyle(tint ?? AppColor.primaryText)
            }
            .padding(.vertical, 7)
            Divider().opacity(0.35)
        }
    }

    private var footer: some View {
        HStack {
            if let screen = metric.screen {
                Button { onOpenScreen(screen) } label: {
                    Label(tr("detail.openFull"), systemImage: "arrow.up.forward.app")
                }
                .buttonStyle(.primaryGradient)
            }
            Spacer()
            Button(tr("common.close"), action: onClose)
                .keyboardShortcut(.cancelAction)
        }
        .padding(Theme.Spacing.xl)
    }
}
