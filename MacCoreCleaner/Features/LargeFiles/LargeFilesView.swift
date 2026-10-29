import SwiftUI

/// The Large Files screen: scans the user's media/document folders for big files,
/// shows them in a reviewable list (with a "1GB+" badge on the largest ones and a
/// last-accessed hint), and moves the selected files to the Trash after an explicit
/// confirmation. A sticky bottom bar summarizes the current selection.
struct LargeFilesView: View {
    @StateObject private var vm = LargeFilesViewModel()

    /// Files at or above this size are flagged with the "1GB+" badge / red size.
    private static let bigFileThreshold: Int64 = 1_000_000_000

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                hero

                InfoBanner(kind: .info, message: tr("large.subtitle"))

                if let outcome = vm.lastOutcome {
                    CleanOutcomeBanner(outcome: outcome)
                }

                if !vm.hasScanned {
                    EmptyStateView(
                        systemImage: "doc.text.magnifyingglass",
                        title: tr("large.empty.title"),
                        message: tr("large.empty.message")
                    )
                } else if !vm.files.isEmpty {
                    fileList
                } else if !vm.isScanning {
                    EmptyStateView(
                        systemImage: "checkmark.circle",
                        title: tr("large.empty.title"),
                        message: tr("large.empty.message")
                    )
                }
            }
            .padding(Theme.Spacing.outer)
        }
        .screenBackground()
        .navigationTitle(tr("nav.largeFiles"))
        .toolbar {
            ToolbarItem(placement: .primaryAction) { scanButton }
        }
        .safeAreaInset(edge: .bottom) { bottomBar }
        .task { if !vm.hasScanned { vm.scan() } }
        .onDisappear { if vm.isScanning { vm.cancelScan() } }
        .sheet(isPresented: $vm.showConfirm) {
            ConfirmCleanSheet(
                items: vm.pendingItems,
                mode: $vm.mode,
                allowPermanent: AppServices.shared.settings.advancedMode,
                onConfirm: { Task { await vm.performClean() } },
                onCancel: { vm.cancelClean() }
            )
        }
    }

    // MARK: Toolbar

    private var scanButton: some View {
        Group {
            if vm.isScanning {
                Button(role: .cancel) { vm.cancelScan() } label: {
                    Label(tr("common.stop"), systemImage: "stop.fill")
                }
            } else {
                Button { vm.scan() } label: {
                    Label(tr("common.scan"), systemImage: "arrow.clockwise")
                }
            }
        }
    }

    // MARK: Hero

    private var hero: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text(tr("nav.largeFiles"))
                .font(.mcCaption)
                .foregroundStyle(AppColor.secondaryText)
            Text(ByteFormat.string(fromBytes: vm.totalBytes))
                .font(.mcMetric(56))
                .foregroundStyle(AppColor.primaryText)
                .contentTransition(.numericText())

            if vm.isScanning {
                HStack(spacing: Theme.Spacing.sm) {
                    ProgressView(value: vm.scanProgress.fractionCompleted)
                        .frame(maxWidth: 280)
                    Text(
                        vm.scanProgress.phase.isEmpty
                            ? tr("common.scanning")
                            : tr("large.scanningRoot", vm.scanProgress.phase)
                    )
                    .font(.mcCaption)
                    .foregroundStyle(AppColor.secondaryText)
                }
            } else {
                Text(tr("large.found", vm.totalCount, ByteFormat.string(fromBytes: vm.totalBytes)))
                    .font(.mcCaption)
                    .foregroundStyle(AppColor.secondaryText)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(padding: Theme.Spacing.outer, elevated: true)
    }

    // MARK: File list

    private var fileList: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            SectionTitle(tr("large.found", vm.totalCount, ByteFormat.string(fromBytes: vm.totalBytes)))
            VStack(spacing: 0) {
                ForEach($vm.files) { $item in
                    VStack(alignment: .leading, spacing: 2) {
                        CleanableItemRow(item: $item)
                        HStack(spacing: Theme.Spacing.sm) {
                            if item.sizeBytes >= Self.bigFileThreshold {
                                Text(tr("large.bigBadge"))
                                    .font(.mcMicro.weight(.semibold))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(
                                        Capsule().fill(AppColor.danger.opacity(0.15))
                                    )
                                    .foregroundStyle(AppColor.danger)
                            }
                            Text(tr("large.accessed", DateFormat.relativeString(item.accessedDate)))
                                .font(.mcMicro)
                                .foregroundStyle(AppColor.secondaryText)
                        }
                        .padding(.leading, 48)
                    }
                    .padding(.vertical, 2)

                    if item.id != vm.files.last?.id {
                        Divider().opacity(0.4)
                    }
                }
            }
            .card()
        }
    }

    // MARK: Bottom bar

    @ViewBuilder
    private var bottomBar: some View {
        if vm.hasScanned && !vm.files.isEmpty {
            HStack(spacing: Theme.Spacing.md) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(tr("large.found", vm.selectedCount, ByteFormat.string(fromBytes: vm.selectedBytes)))
                        .font(.mcBody.weight(.medium))
                        .foregroundStyle(AppColor.primaryText)
                }
                Spacer(minLength: Theme.Spacing.md)
                Button { vm.startClean() } label: {
                    Label(tr("common.clean"), systemImage: "trash")
                }
                .buttonStyle(.primaryGradient)
                .tint(AppColor.primary)
                .disabled(vm.selectedCount == 0)
                .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, Theme.Spacing.outer)
            .padding(.vertical, Theme.Spacing.md)
            .background(.bar)
        }
    }
}

#Preview {
    LargeFilesView()
        .frame(width: 1024, height: 800)
}
