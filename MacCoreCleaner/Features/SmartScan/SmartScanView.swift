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
                ScanOrb(fraction: vm.scanFraction)
                    .frame(width: 190, height: 190)
                Text(vm.scanPhase).font(.mcCaption).foregroundStyle(AppColor.secondaryText).lineLimit(1)
                Button(tr("common.stop")) { vm.cancelScan() }.buttonStyle(.softCapsule)
            } else if vm.hasScanned {
                StatusEyebrow(text: tr("smart.recoverable"), color: AppColor.success)
                Text(ByteFormat.string(fromBytes: vm.totalFound))
                    .font(.mcHero(60))
                    .foregroundStyle(AppGradient.brandDiagonal)
                    .contentTransition(.numericText())
                Text(tr("smart.selectedSummary", vm.selectedCount, ByteFormat.string(fromBytes: vm.selectedBytes)))
                    .font(.mcCaption).foregroundStyle(AppColor.secondaryText)
                if !vm.groups.isEmpty { categoryChips }
                HStack(spacing: Theme.Spacing.md) {
                    Button { vm.startClean() } label: {
                        Label(tr("common.clean"), systemImage: "sparkles")
                    }
                    .buttonStyle(.primaryGradient)
                    .disabled(vm.selectedCount == 0 || vm.isCleaning)
                    Button { vm.scan() } label: { Label(tr("smart.rescan"), systemImage: "arrow.clockwise") }
                        .buttonStyle(.softCapsule)
                        .disabled(vm.isCleaning)
                }
            } else {
                ScanOrb(fraction: nil).frame(width: 150, height: 150)
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
        .padding(.vertical, Theme.Spacing.md)
        .card(padding: Theme.Spacing.outer, elevated: true)
    }

    private var categoryChips: some View {
        HStack(spacing: 8) {
            ForEach(vm.groups.prefix(5)) { group in
                HStack(spacing: 6) {
                    Image(systemName: group.icon).font(.system(size: 10, weight: .bold)).foregroundStyle(group.tint)
                    Text(tr(group.titleKey)).font(.system(size: 11, weight: .medium)).lineLimit(1)
                    Text(ByteFormat.string(fromBytes: group.totalBytes)).font(.mcMono(10)).foregroundStyle(AppColor.secondaryText)
                }
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(Capsule().fill(group.tint.opacity(0.10)))
            }
        }
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

/// Soft gradient orb: a progress ring while scanning, an idle glow otherwise.
private struct ScanOrb: View {
    let fraction: Double?
    @State private var spin = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Circle().fill(AppGradient.brandDiagonal).opacity(0.16).blur(radius: 18)
            Circle().fill(AppColor.card).shadow(color: Color(hex: "6D5DF6").opacity(0.18), radius: 16, y: 6)
            Circle().stroke(AppColor.divider.opacity(0.6), lineWidth: 10).padding(14)
            if let fraction {
                Circle().trim(from: 0, to: max(0.02, fraction))
                    .stroke(AppGradient.brandDiagonal, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                    .rotationEffect(.degrees(-90)).padding(14)
                    .animation(.easeOut(duration: 0.3), value: fraction)
                Text(ByteFormat.percent(fraction)).font(.mcHero(34)).foregroundStyle(AppGradient.brandDiagonal)
            } else {
                Circle().trim(from: 0, to: 0.28)
                    .stroke(AppGradient.brandDiagonal, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                    .rotationEffect(.degrees(spin ? 360 : 0)).padding(14)
                    .animation(.linear(duration: 6).repeatForever(autoreverses: false), value: spin)
                Image(systemName: "sparkles").font(.system(size: 34, weight: .semibold)).foregroundStyle(AppGradient.brandDiagonal)
            }
        }
        .onAppear { spin = !reduceMotion }
        .accessibilityHidden(true)
    }
}

#Preview {
    SmartScanView().frame(width: 1024, height: 800)
}
