import SwiftUI

/// The Developer screen: tool cards (Xcode DerivedData/Archives/Simulator, SPM,
/// Homebrew, Gradle) plus a display-only Docker card. Same review-before-remove
/// flow as Storage.
struct DeveloperCleanerView: View {
    @StateObject private var vm = DeveloperCleanerViewModel()

    private let columns = [GridItem(.adaptive(minimum: 300), spacing: Theme.Spacing.gridGap)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                recoverableHero

                InfoBanner(
                    kind: .info,
                    message: tr("dev.infoBanner")
                )

                if let outcome = vm.lastOutcome {
                    CleanOutcomeBanner(outcome: outcome)
                }

                SectionTitle(tr("dev.tools"))
                LazyVGrid(columns: columns, spacing: Theme.Spacing.gridGap) {
                    ForEach(vm.cleanableCategories) { id in
                        toolCard(for: id)
                    }
                    dockerCard
                }

                if !vm.hasScanned {
                    EmptyStateView(
                        systemImage: "hammer",
                        title: tr("dev.empty.title"),
                        message: tr("dev.empty.message")
                    )
                }
            }
            .padding(Theme.Spacing.outer)
        }
        .screenBackground()
        .navigationTitle(tr("nav.developer"))
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                if vm.isScanning {
                    Button(role: .cancel) { vm.cancelScan() } label: { Label(tr("common.stop"), systemImage: "stop.fill") }
                } else {
                    Button { vm.scan() } label: { Label(tr("common.scan"), systemImage: "arrow.clockwise") }
                }
            }
        }
        .task { if !vm.hasScanned { vm.scan() } }
        .onDisappear { if vm.isScanning { vm.cancelScan() } }
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
                allowPermanent: vm.advancedMode,
                onConfirm: { Task { await vm.performClean() } },
                onCancel: { vm.cancelClean() }
            )
        }
    }

    private var recoverableHero: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text(tr("dev.recoverable")).font(.mcCaption).foregroundStyle(AppColor.secondaryText)
            Text(ByteFormat.string(fromBytes: vm.totalRecoverable))
                .font(.mcMetric(56))
                .foregroundStyle(AppColor.primaryText)
                .contentTransition(.numericText())
            if vm.isScanning {
                HStack(spacing: Theme.Spacing.sm) {
                    ProgressView(value: vm.scanProgress.fractionCompleted).frame(maxWidth: 280)
                    Text(vm.scanProgress.phase).font(.mcCaption).foregroundStyle(AppColor.secondaryText)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(padding: Theme.Spacing.outer, elevated: true)
    }

    @ViewBuilder
    private func toolCard(for id: CleanCategoryID) -> some View {
        let meta = CleanCategory.metadata(for: id)
        let result = vm.result(for: id)
        DeveloperToolCard(
            icon: meta.systemImage,
            title: meta.title,
            subtitle: meta.subtitle,
            sizeBytes: result?.totalBytes ?? 0,
            lastModified: vm.lastModified(for: id),
            level: meta.defaultSafety,
            isScanning: vm.isScanning && result == nil,
            displayOnly: false,
            onReview: { vm.openReview(id) }
        )
    }

    private var dockerCard: some View {
        let meta = CleanCategory.metadata(for: .dockerData)
        return DeveloperToolCard(
            icon: meta.systemImage,
            title: meta.title,
            subtitle: meta.subtitle,
            sizeBytes: vm.dockerSize,
            lastModified: nil,
            level: .risky,
            isScanning: vm.isScanning,
            displayOnly: true,
            onReview: nil
        )
    }
}

#Preview {
    DeveloperCleanerView()
        .frame(width: 1024, height: 800)
}
