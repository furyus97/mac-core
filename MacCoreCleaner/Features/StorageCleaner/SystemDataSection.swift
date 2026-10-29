import SwiftUI
import AppKit

struct SystemDataSection: View {
    @StateObject private var vm: SystemDataViewModel
    @EnvironmentObject private var settings: SettingsStore
    var onCleaned: () -> Void = {}

    init(vm: SystemDataViewModel? = nil, onCleaned: @escaping () -> Void = {}) {
        _vm = StateObject(wrappedValue: vm ?? SystemDataViewModel())
        self.onCleaned = onCleaned
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Label(tr("sd.title"), systemImage: "internaldrive.fill").font(.mcSectionTitle)
                Spacer()
                if vm.isCleaning {
                    ProgressView().controlSize(.small)
                } else if vm.isAnalyzing {
                    Button(tr("common.stop")) { vm.cancelAnalysis() }
                } else {
                    Button(tr("sd.analyze")) { vm.analyze() }
                        .disabled(vm.isCleaning)
                }
            }
            Text(tr("sd.explain")).font(.mcCaption).foregroundStyle(AppColor.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            if vm.isAnalyzing {
                ProgressView(value: vm.progress.fractionCompleted)
                Text(vm.progress.phase).font(.mcCaption).foregroundStyle(AppColor.secondaryText)
            }
            if vm.wasCancelled {
                Text(tr("sd.cancelled")).font(.mcCaption).foregroundStyle(AppColor.secondaryText)
            }
            if let outcome = vm.lastOutcome { CleanOutcomeBanner(outcome: outcome) }
            if let report = vm.report {
                SystemDataResults(report: report, onReview: vm.review)
                    .disabled(vm.isCleaning)
            }
            Text(tr("sd.protected")).font(.mcCaption).foregroundStyle(AppColor.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            Link(tr("sd.appleGuide"), destination: URL(string: "https://support.apple.com/102154")!)
                .font(.mcCaption)
        }
        .card(padding: 24)
        .onDisappear { vm.cancelAnalysis() }
        .onChange(of: vm.isCleaning) { old, new in if old && !new { onCleaned() } }
        .sheet(item: $vm.reviewing) { initial in
            CategoryReviewSheet(result: Binding(
                get: { vm.reviewing ?? initial },
                set: { vm.reviewing = $0 }),
                onClean: { vm.stageClean() }, onClose: { vm.reviewing = nil })
        }
        .sheet(isPresented: $vm.showConfirm) {
            ConfirmCleanSheet(items: vm.pendingItems, mode: $vm.mode,
                allowPermanent: settings.advancedMode,
                onConfirm: { Task { await vm.clean() } }, onCancel: { vm.cancelClean() })
        }
    }
}

struct SystemDataResults: View {
    let report: SystemDataReport
    let onReview: (SystemDataGroup) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 32) {
                summary(tr("sd.found"), report.identifiedBytes, tint: AppColor.primaryText)
                summary(tr("sd.reviewable"), report.reviewableBytes, tint: AppColor.primary)
                Spacer(minLength: 0)
            }
            if report.isPartial { InfoBanner(kind: .warning, message: tr("sd.partial")) }
            ForEach(report.groups) { group in
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(tr(group.titleKey)).font(.mcBodyMedium)
                            Text(group.root.path).font(.mcMono(10)).foregroundStyle(AppColor.secondaryText)
                                .lineLimit(1).truncationMode(.middle)
                                .textSelection(.enabled)
                                .environment(\.layoutDirection, .leftToRight)
                        }
                        Spacer(minLength: 12)
                        VStack(alignment: .trailing, spacing: 4) {
                            Text(ByteFormat.string(fromBytes: group.sizeBytes)).font(.mcMono(13))
                            if group.isPartial {
                                Text(tr("sd.incomplete")).font(.mcMicro).foregroundStyle(AppColor.warning)
                            }
                        }
                        if !group.items.isEmpty {
                            Button(tr("common.review")) { onReview(group) }
                        } else {
                            Text(tr("sd.readonly")).font(.mcMicro).foregroundStyle(AppColor.secondaryText)
                        }
                    }
                    if group.reviewableBytes > 0 {
                        Text(tr("sd.reviewSize", ByteFormat.string(fromBytes: group.reviewableBytes)))
                            .font(.mcCaption).foregroundStyle(AppColor.primary)
                    }
                }
                Divider()
            }
            Text(tr("sd.trashNote")).font(.mcCaption).foregroundStyle(AppColor.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func summary(_ title: String, _ bytes: Int64, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.mcCaption).foregroundStyle(AppColor.secondaryText)
            Text(ByteFormat.string(fromBytes: bytes)).font(.mcMetric(28)).foregroundStyle(tint)
        }
    }
}
