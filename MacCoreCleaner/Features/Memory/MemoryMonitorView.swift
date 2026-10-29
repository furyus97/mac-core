import SwiftUI

/// Live memory monitor: a usage ring with key statistics, a non-destructive
/// cleanup suggestion, and the heaviest apps with a confirm-gated terminate action.
struct MemoryMonitorView: View {
    @StateObject private var vm = MemoryMonitorViewModel()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                heroCard

                VStack(spacing: 0) {
                    TelemetryRow(title: tr("detail.total"), value: ByteFormat.string(fromBytes: vm.memory.totalBytes))
                    TelemetryRow(title: tr("detail.app"), value: ByteFormat.string(fromBytes: vm.memory.appBytes))
                    TelemetryRow(title: tr("detail.wired"), value: ByteFormat.string(fromBytes: vm.memory.wiredBytes))
                    TelemetryRow(title: tr("detail.compressed"), value: ByteFormat.string(fromBytes: vm.memory.compressedBytes))
                    TelemetryRow(title: tr("detail.cache"), value: ByteFormat.string(fromBytes: vm.memory.cachedBytes))
                    TelemetryRow(title: tr("detail.free"), value: ByteFormat.string(fromBytes: vm.memory.freeBytes))
                    TelemetryRow(title: tr("detail.swap"), value: ByteFormat.string(fromBytes: vm.memory.swapUsedBytes))
                }.card()

                cleanupCard

                SectionTitle(tr("mem.topApps"))

                ProcessTable(
                    processes: vm.topByMemory,
                    height: 340,
                    onTerminate: { vm.requestTerminate($0) }
                )
                .card(padding: Theme.Spacing.sm)
            }
            .padding(Theme.Spacing.outer)
        }
        .screenBackground()
        .navigationTitle(tr("nav.memory"))
        .task {
            while !Task.isCancelled {
                await vm.refresh()
                try? await Task.sleep(nanoseconds: 2_000_000_000)
            }
        }
        .alert(
            tr("mem.terminateAlert.title"),
            isPresented: Binding(
                get: { vm.terminateTarget != nil },
                set: { if !$0 { vm.cancelTerminate() } }
            )
        ) {
            Button(tr("mem.terminateAlert.confirm"), role: .destructive) { vm.confirmTerminate() }
            Button(tr("common.cancel"), role: .cancel) { vm.cancelTerminate() }
        } message: {
            if let t = vm.terminateTarget {
                Text(tr("mem.terminateAlert.message", t.name, t.pid))
            }
        }
    }

    // MARK: - Hero

    private var heroCard: some View {
        HStack(alignment: .center, spacing: Theme.Spacing.xl) {
            RingGauge(
                fraction: vm.memory.usedFraction,
                caption: tr("mem.inUse"),
                tint: vm.memory.pressure.tint
            )
            .frame(width: 170, height: 170)

            LazyVGrid(
                columns: [GridItem(.flexible()), GridItem(.flexible())],
                spacing: Theme.Spacing.md
            ) {
                StatCard(
                    title: tr("mem.stat.usedTotal"),
                    value: "\(ByteFormat.string(fromBytes: vm.memory.usedBytes)) / \(ByteFormat.string(fromBytes: vm.memory.totalBytes))",
                    subtitle: tr("mem.stat.usedTotal.subtitle"),
                    systemImage: "memorychip",
                    tint: usageTint(for: vm.memory.usedFraction)
                )
                StatCard(
                    title: tr("mem.stat.compressed"),
                    value: ByteFormat.string(fromBytes: vm.memory.compressedBytes),
                    subtitle: tr("mem.stat.compressed.subtitle"),
                    systemImage: "archivebox",
                    tint: AppColor.primary
                )
                StatCard(
                    title: tr("mem.stat.cache"),
                    value: ByteFormat.string(fromBytes: vm.memory.cachedBytes),
                    subtitle: tr("mem.stat.cache.subtitle"),
                    systemImage: "tray.full",
                    tint: AppColor.primary
                )
                StatCard(
                    title: "Swap",
                    value: ByteFormat.string(fromBytes: vm.memory.swapUsedBytes),
                    subtitle: tr("mem.stat.swap.subtitle"),
                    systemImage: "internaldrive",
                    tint: vm.memory.swapUsedBytes > 0 ? AppColor.warning : AppColor.primary
                )
                StatCard(
                    title: tr("mem.stat.pressure"),
                    value: vm.memory.pressure.title,
                    subtitle: tr("mem.stat.pressure.subtitle"),
                    systemImage: "gauge.with.dots.needle.bottom.50percent",
                    tint: vm.memory.pressure.tint
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(elevated: true)
    }

    // MARK: - Cleanup suggestion (non-destructive)

    private var cleanupCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            SectionTitle(tr("mem.cleanup.title"))

            Text(tr("mem.cleanup.body"))
                .font(.mcBody)
                .foregroundStyle(AppColor.secondaryText)
                .fixedSize(horizontal: false, vertical: true)

            if let app = vm.heaviestApp {
                Divider()

                HStack(alignment: .center, spacing: Theme.Spacing.md) {
                    IconTile(systemName: "app.dashed", tint: AppColor.warning)

                    VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                        Text(app.name)
                            .font(.mcCardTitle)
                            .foregroundStyle(AppColor.primaryText)
                        Text(tr("mem.cleanup.appUsage", ByteFormat.string(fromBytes: app.memoryBytes)))
                            .font(.mcCaption)
                            .foregroundStyle(AppColor.secondaryText)
                    }

                    Spacer()

                    Button(tr("mem.cleanup.suggestQuit")) {
                        vm.requestTerminate(app)
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }
}

#Preview {
    MemoryMonitorView()
        .frame(width: 1024, height: 800)
}
