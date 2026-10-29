import SwiftUI

/// The Storage screen: a large "Recoverable Space" headline and category cards.
/// Each category is opened with "Review" before anything is removed.
struct StorageCleanerView: View {
    @StateObject private var vm = StorageCleanerViewModel()
    @EnvironmentObject private var permissions: PermissionManager

    private let columns = [GridItem(.adaptive(minimum: 360), spacing: Theme.Spacing.gridGap)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                recoverableHero

                SystemDataSection(onCleaned: { vm.scan() })
                    .disabled(vm.isCleaning)

                if permissions.downloads == .denied {
                    InfoBanner(
                        kind: .warning,
                        message: tr("stor.permissionBanner"),
                        actionTitle: tr("stor.openPermissionSettings"),
                        action: { permissions.openPrivacySettings() }
                    )
                }

                if let outcome = vm.lastOutcome {
                    CleanOutcomeBanner(outcome: outcome)
                }

                SectionTitle(tr("stor.categories"))
                LazyVGrid(columns: columns, spacing: Theme.Spacing.gridGap) {
                    ForEach(vm.categories) { id in
                        categoryCard(for: id)
                    }
                }

                if !vm.hasScanned {
                    EmptyStateView(
                        systemImage: "magnifyingglass",
                        title: tr("stor.emptyTitle"),
                        message: tr("stor.emptyMessage")
                    )
                }
            }
            .padding(Theme.Spacing.outer)
        }
        .screenBackground()
        .navigationTitle(tr("nav.storage"))
        .toolbar {
            ToolbarItem(placement: .primaryAction) { scanButton }
        }
        .task { if !vm.hasScanned { vm.scan() } }
        .onDisappear { if vm.isScanning { vm.cancelScan() } }
        .onChange(of: vm.isScanning) { wasScanning, isScanning in
            if wasScanning && !isScanning { permissions.refreshDownloads() }
        }
        .sheet(item: $vm.reviewing) { _ in
            if let binding = vm.reviewBinding() {
                CategoryReviewSheet(
                    result: binding,
                    onClean: { vm.startClean() },
                    onClose: { vm.reviewing = nil }
                )
            }
        }
        .sheet(isPresented: $vm.showConfirm) {
            ConfirmCleanSheet(
                items: vm.pendingItems,
                mode: $vm.mode,
                allowPermanent: vm.advancedMode || vm.isEmptyingTrash,
                forcePermanent: vm.isEmptyingTrash,
                onConfirm: { Task { await vm.performClean() } },
                onCancel: { vm.cancelClean() }
            )
        }
    }

    private var scanButton: some View {
        Group {
            if vm.isScanning {
                Button(role: .cancel) { vm.cancelScan() } label: { Label(tr("common.stop"), systemImage: "stop.fill") }
            } else {
                Button { vm.scan() } label: { Label(tr("common.scan"), systemImage: "arrow.clockwise") }
                    .disabled(vm.isCleaning)
            }
        }
    }

    private var recoverableHero: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text(tr("stor.recoverableSpace"))
                .font(.mcCaption)
                .foregroundStyle(AppColor.secondaryText)
            Text(ByteFormat.string(fromBytes: vm.totalRecoverable))
                .font(.mcMetric(56))
                .foregroundStyle(AppColor.primaryText)
                .contentTransition(.numericText())

            if vm.isScanning {
                HStack(spacing: Theme.Spacing.sm) {
                    ProgressView(value: vm.scanProgress.fractionCompleted)
                        .frame(maxWidth: 280)
                    Text(vm.scanProgress.phase)
                        .font(.mcCaption)
                        .foregroundStyle(AppColor.secondaryText)
                }
            } else {
                Text(tr("stor.heroHint"))
                    .font(.mcCaption)
                    .foregroundStyle(AppColor.secondaryText)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(padding: Theme.Spacing.outer, elevated: true)
    }

    @ViewBuilder
    private func categoryCard(for id: CleanCategoryID) -> some View {
        let meta = CleanCategory.metadata(for: id)
        let result = vm.result(for: id)
        StorageCategoryCard(
            icon: meta.systemImage,
            tint: meta.group.tint,
            title: meta.title,
            description: meta.subtitle,
            locationDescription: meta.locationDescription,
            sizeBytes: result?.totalBytes ?? 0,
            level: meta.defaultSafety,
            itemCount: result?.itemCount ?? 0,
            isScanning: vm.isScanning && result == nil,
            onReview: { vm.openReview(id) }
        )
        .disabled(vm.isCleaning)
    }
}

#Preview {
    StorageCleanerView()
        .environmentObject(AppServices.shared.permissions)
        .environmentObject(AppServices.shared.settings)
        .frame(width: 1024, height: 800)
}
