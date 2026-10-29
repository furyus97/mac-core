import SwiftUI

/// The one-click Smart Scan screen — CleanMyMac-style. Scans every cleaner,
/// auto-selects only Safe items, and cleans each group with its safety scope.
struct SmartScanView: View {
    @StateObject private var vm = SmartScanViewModel()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                hero

                if let outcome = vm.lastOutcome {
                    CleanOutcomeBanner(outcome: outcome)
                }

                if vm.hasScanned && !vm.isScanning {
                    if vm.groups.isEmpty {
                        EmptyStateView(systemImage: "checkmark.seal.fill",
                                       title: tr("smart.empty.title"), message: tr("smart.empty.message"))
                    } else {
                        Text(tr("smart.autoNote"))
                            .font(.mcCaption).foregroundStyle(AppColor.secondaryText)
                        ForEach(vm.groups) { group in
                            groupCard(group)
                        }
                    }
                }
            }
            .padding(Theme.Spacing.outer)
        }
        .screenBackground()
        .navigationTitle(tr("nav.smartScan"))
        .task { if !vm.hasScanned { vm.scan() } }
        .onDisappear { if vm.isScanning { vm.cancelScan() } }
        .sheet(isPresented: $vm.showConfirm) {
            ConfirmCleanSheet(items: vm.pendingItems, mode: $vm.mode, allowPermanent: false,
                              onConfirm: { Task { await vm.performClean() } },
                              onCancel: { vm.cancelClean() })
        }
    }

    // MARK: Hero

    private var hero: some View {
        VStack(spacing: Theme.Spacing.lg) {
            if vm.isScanning {
                RingGauge(fraction: vm.scanFraction, label: ByteFormat.percent(vm.scanFraction),
                          caption: tr("nav.smartScan"), tint: AppColor.primary)
                    .frame(width: 160, height: 160)
                Text(vm.scanPhase).font(.mcCaption).foregroundStyle(AppColor.secondaryText)
                Button(tr("common.stop")) { vm.cancelScan() }
            } else if vm.hasScanned {
                Text(tr("smart.recoverable")).eyebrow()
                Text(ByteFormat.string(fromBytes: vm.totalFound))
                    .font(.mcMetric(54)).foregroundStyle(AppColor.primaryText)
                    .contentTransition(.numericText())
                Text(tr("smart.selectedSummary", vm.selectedCount, ByteFormat.string(fromBytes: vm.selectedBytes)))
                    .font(.mcCaption).foregroundStyle(AppColor.secondaryText)
                HStack(spacing: Theme.Spacing.md) {
                    Button { vm.scan() } label: { Label(tr("smart.rescan"), systemImage: "arrow.clockwise") }
                        .controlSize(.large)
                        .disabled(vm.isCleaning)
                    Button { vm.startClean() } label: {
                        Label(tr("common.clean"), systemImage: "sparkles")
                    }
                    .buttonStyle(.primaryGradient)
                    .disabled(vm.selectedCount == 0 || vm.isCleaning)
                }
            } else {
                IconTile(systemName: "sparkles", tint: AppColor.primary, size: 64)
                Text(tr("nav.smartScan")).font(.mcLargeTitle)
                Text(tr("smart.subtitle"))
                    .font(.mcBody).foregroundStyle(AppColor.secondaryText)
                    .multilineTextAlignment(.center).frame(maxWidth: 420)
                Button { vm.scan() } label: { Label(tr("smart.start"), systemImage: "bolt.fill") }
                    .buttonStyle(.primaryGradient)
                    .disabled(vm.isCleaning)
            }
        }
        .frame(maxWidth: .infinity)
        .card(padding: Theme.Spacing.outer, elevated: true)
    }

    // MARK: Group card

    @ViewBuilder
    private func groupCard(_ group: SmartGroup) -> some View {
        if let binding = vm.binding(for: group.id) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: Theme.Spacing.md) {
                    Toggle(isOn: Binding(
                        get: { binding.wrappedValue.allSelected },
                        set: { v in
                            var g = binding.wrappedValue
                            for i in g.entries.indices where g.entries[i].isEnabled {
                                g.entries[i].isSelected = v
                            }
                            binding.wrappedValue = g
                        }
                    )) { EmptyView() }
                    .toggleStyle(.checkbox).labelsHidden()
                    .accessibilityLabel(tr("common.selectAll"))

                    IconTile(systemName: group.icon, tint: group.tint, size: 32)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(tr(group.titleKey)).font(.mcCardTitle)
                        Text(tr("comp.review.selectedCount", group.selectedCount, group.entries.count))
                            .font(.mcMicro).foregroundStyle(AppColor.secondaryText)
                    }
                    Spacer()
                    Text(ByteFormat.string(fromBytes: group.totalBytes))
                        .font(.mcMono(15, weight: .semibold))
                    Button {
                        withAnimation(.easeInOut(duration: 0.18)) { binding.wrappedValue.isExpanded.toggle() }
                    } label: {
                        Image(systemName: group.isExpanded ? "chevron.up" : "chevron.down")
                            .foregroundStyle(AppColor.secondaryText)
                    }
                    .buttonStyle(.borderless)
                }

                if group.isExpanded {
                    Divider().padding(.vertical, Theme.Spacing.sm)
                    LazyVStack(spacing: 0) {
                        ForEach(binding.entries) { $entry in
                            entryRow($entry)
                            if entry.id != group.entries.last?.id { Divider().opacity(0.35) }
                        }
                    }
                }
            }
            .card()
        }
    }

    private func entryRow(_ entry: Binding<SmartEntry>) -> some View {
        HStack(spacing: Theme.Spacing.md) {
            Toggle(isOn: entry.isSelected) { EmptyView() }
                .toggleStyle(.checkbox).labelsHidden()
                .disabled(!entry.wrappedValue.isEnabled)
                .accessibilityLabel(entry.wrappedValue.name)
            VStack(alignment: .leading, spacing: 1) {
                Text(entry.wrappedValue.name).font(.mcBody).lineLimit(1).truncationMode(.middle)
                if let d = entry.wrappedValue.detail {
                    Text(d).font(.mcMicro).foregroundStyle(AppColor.secondaryText)
                }
            }
            Spacer(minLength: Theme.Spacing.sm)
            Text(entry.wrappedValue.formattedSize).font(.mcMono(12)).foregroundStyle(AppColor.secondaryText)
            SafetyBadge(level: entry.wrappedValue.safety, compact: true)
        }
        .padding(.vertical, 5)
        .opacity(entry.wrappedValue.isEnabled ? 1 : 0.55)
    }
}

#Preview {
    SmartScanView().frame(width: 1024, height: 800)
}
