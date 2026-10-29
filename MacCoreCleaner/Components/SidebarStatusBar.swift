import SwiftUI

/// A compact, always-on live monitor pinned to the bottom of the sidebar
/// (CPU / RAM / temperature). A subtle "technical" signature.
///
/// Uses its OWN `ProcessMonitorService` instance so its delta-based CPU sampling
/// never contends with the active detail screen's shared sampler.
@MainActor
final class SidebarStatusViewModel: ObservableObject {
    private let monitor = ProcessMonitorService()
    private let services: AppServices

    @Published var cpu: Double = 0
    @Published var memFraction: Double = 0
    @Published var tempText: String?

    init(services: AppServices? = nil) {
        self.services = services ?? .shared
    }

    func tick() async {
        cpu = (await monitor.sampleCPU()).totalUsage
        memFraction = (await monitor.sampleMemory()).usedFraction
        let temperatureMonitor = services.temperature
        let snap = await Task.detached(priority: .utility) { temperatureMonitor.sample() }.value
        guard !Task.isCancelled else { return }
        if let v = snap.value(for: services.settings.temperatureSource) {
            tempText = ByteFormat.temperature(v)
        } else {
            tempText = nil
        }
    }
}

struct SidebarStatusBar: View {
    @StateObject private var vm = SidebarStatusViewModel()

    var body: some View {
        HStack(spacing: Theme.Spacing.md) {
            miniStat(icon: "cpu", label: "CPU", fraction: vm.cpu, text: ByteFormat.percent(vm.cpu))
            Divider().frame(height: 22)
            miniStat(icon: "memorychip", label: "RAM", fraction: vm.memFraction, text: ByteFormat.percent(vm.memFraction))
            if let t = vm.tempText {
                Divider().frame(height: 22)
                VStack(spacing: 3) {
                    HStack(spacing: 3) {
                        Image(systemName: "thermometer.medium").font(.system(size: 9))
                        Text(t).font(.mcMono(11, weight: .medium))
                    }
                    .foregroundStyle(AppColor.secondaryText)
                    Text(tr("menubar.metric.temperature")).eyebrow().font(.system(size: 8, weight: .semibold))
                        .lineLimit(1).minimumScaleFactor(0.6)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, Theme.Spacing.sm)
        .background(AppColor.sidebar)
        .overlay(alignment: .top) { Divider() }
        .task {
            while !Task.isCancelled {
                await vm.tick()
                try? await Task.sleep(nanoseconds: 2_500_000_000)
            }
        }
    }

    private func miniStat(icon: String, label: String, fraction: Double, text: String) -> some View {
        VStack(spacing: 3) {
            HStack(spacing: 4) {
                Image(systemName: icon).font(.system(size: 9))
                Text(text).font(.mcMono(11, weight: .medium))
            }
            .foregroundStyle(usageTint(for: fraction))
            UsageBar(fraction: fraction, height: 3)
            Text(label).eyebrow().font(.system(size: 8, weight: .semibold))
        }
        .frame(maxWidth: .infinity)
    }
}
