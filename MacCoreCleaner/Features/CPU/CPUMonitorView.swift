import SwiftUI
import Charts

/// The CPU monitor screen. Shows overall usage, a user/system/idle breakdown,
/// a live usage chart, per-core utilization and the processes consuming the
/// most CPU, with a confirm-gated terminate action available only in the
/// danger zone. Refreshes on a live 1.5s loop.
struct CPUMonitorView: View {
    @StateObject private var vm = CPUMonitorViewModel()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                heroCard
                HardwareIdentityView()
                chartCard
                perCoreCard

                SectionTitle(tr("cpu.processes"))
                ProcessTable(processes: vm.topByCPU, height: 300, onTerminate: nil)

                DangerZone(message: tr("cpu.dangerMessage")) {
                    ProcessTable(
                        processes: vm.topByCPU,
                        height: 240,
                        onTerminate: { vm.requestTerminate($0) }
                    )
                }
            }
            .padding(Theme.Spacing.outer)
        }
        .screenBackground()
        .navigationTitle(tr("nav.cpu"))
        // Fast loop: smooth ~1s CPU graph (cheap Mach call).
        .task {
            while !Task.isCancelled {
                await vm.refreshCPU()
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
        }
        // Slow loop: process table (spawns ps) — decoupled so it never stutters the graph.
        .task {
            while !Task.isCancelled {
                await vm.refreshProcesses()
                try? await Task.sleep(nanoseconds: 2_500_000_000)
            }
        }
        .alert(
            tr("cpu.terminateTitle"),
            isPresented: Binding(
                get: { vm.terminateTarget != nil },
                set: { if !$0 { vm.cancelTerminate() } }
            ),
            presenting: vm.terminateTarget
        ) { _ in
            Button(tr("cpu.terminate"), role: .destructive) { vm.confirmTerminate() }
            Button(tr("common.cancel"), role: .cancel) { vm.cancelTerminate() }
        } message: { process in
            Text(tr("cpu.terminateMessage", process.name, process.pid))
        }
    }

    // MARK: - Hero

    private var heroCard: some View {
        HStack(alignment: .center, spacing: Theme.Spacing.xl) {
            RingGauge(fraction: vm.cpu.totalUsage, caption: tr("cpu.total"))
                .frame(width: 170, height: 170)

            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: Theme.Spacing.gridGap),
                    GridItem(.flexible(), spacing: Theme.Spacing.gridGap)
                ],
                spacing: Theme.Spacing.gridGap
            ) {
                StatCard(
                    title: tr("cpu.user"),
                    value: ByteFormat.percent(vm.cpu.userUsage),
                    systemImage: "person.fill",
                    tint: AppColor.primary
                )
                StatCard(
                    title: tr("cpu.system"),
                    value: ByteFormat.percent(vm.cpu.systemUsage),
                    systemImage: "gearshape.fill",
                    tint: AppColor.warning
                )
                StatCard(
                    title: tr("cpu.idle"),
                    value: ByteFormat.percent(vm.cpu.idle),
                    systemImage: "moon.zzz.fill",
                    tint: AppColor.success
                )
                StatCard(
                    title: tr("cpu.cores"),
                    value: "\(vm.cpu.coreCount)",
                    systemImage: "cpu",
                    tint: AppColor.primary
                )
            }
            .frame(maxWidth: .infinity)
        }
        .card(elevated: true)
    }

    // MARK: - Live chart

    private var chartCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Text(tr("cpu.liveUsage"))
                .font(.mcCardTitle)
                .foregroundStyle(AppColor.primaryText)

            Chart(vm.history) { point in
                AreaMark(
                    x: .value("t", point.id),
                    y: .value("usage", point.usage * 100)
                )
                .interpolationMethod(.catmullRom)
                .foregroundStyle(
                    LinearGradient(
                        colors: [AppColor.primary.opacity(0.25), AppColor.primary.opacity(0)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

                LineMark(
                    x: .value("t", point.id),
                    y: .value("usage", point.usage * 100)
                )
                .interpolationMethod(.catmullRom)
                .foregroundStyle(AppColor.primary)
            }
            .chartYScale(domain: 0...100)
            .chartYAxis {
                AxisMarks(values: [0, 50, 100])
            }
            .chartXAxis(.hidden)
            .frame(height: 180)
            .animation(.linear(duration: 1.0), value: vm.history)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    // MARK: - Per-core

    private var perCoreCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Text(tr("cpu.perCore"))
                .font(.mcCardTitle)
                .foregroundStyle(AppColor.primaryText)

            ForEach(vm.cpu.coreUsages.indices, id: \.self) { i in
                HStack(spacing: Theme.Spacing.md) {
                    Text(tr("cpu.core", i + 1))
                        .frame(width: 60, alignment: .leading)
                        .font(.mcCaption)

                    UsageBar(fraction: vm.cpu.coreUsages[i])

                    Text(ByteFormat.percent(vm.cpu.coreUsages[i]))
                        .frame(width: 48, alignment: .trailing)
                        .font(.mcCaption.monospacedDigit())
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }
}

#Preview {
    CPUMonitorView().frame(width: 1024, height: 800)
}
