import SwiftUI

/// The Browser screen: per-browser cards listing each data category (cache,
/// cookies, history, …) with a toggle, safety badge and size. A prominent warning
/// explains that clearing cookies/history/login can sign you out — only cache is
/// selected by default. A sticky bottom bar runs the review-then-confirm flow.
struct BrowserView: View {
    @StateObject private var vm = BrowserViewModel()

    var body: some View {
        ZStack(alignment: .bottom) {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                    Text(tr("browser.subtitle"))
                        .font(.mcBody)
                        .foregroundStyle(AppColor.secondaryText)

                    InfoBanner(kind: .warning, message: tr("browser.warning"))

                    if !vm.runningBrowsers.isEmpty {
                        InfoBanner(
                            kind: .warning,
                            message: tr(
                                "browser.running",
                                vm.runningBrowsers.map(\.displayName).sorted().joined(separator: ", ")
                            ),
                            actionTitle: tr("common.refresh"),
                            action: { vm.refreshRunningBrowsers() }
                        )
                    }

                    if let outcome = vm.lastOutcome {
                        CleanOutcomeBanner(outcome: outcome)
                    }

                    content
                }
                .padding(Theme.Spacing.outer)
                // Leave room for the sticky bar so it never covers the last card.
                .padding(.bottom, vm.selected.isEmpty ? 0 : 96)
            }

            if !vm.selected.isEmpty {
                stickyBar
            }
        }
        .screenBackground()
        .navigationTitle(tr("nav.browser"))
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { Task { await vm.load() } } label: {
                    Label(tr("common.refresh"), systemImage: "arrow.clockwise")
                }
                .disabled(vm.isLoading || vm.isCleaning)
            }
        }
        .task { if vm.browsers.isEmpty { await vm.load() } }
        .sheet(isPresented: $vm.showConfirm) {
            ConfirmCleanSheet(
                items: vm.pendingItems,
                mode: $vm.mode,
                allowPermanent: false,
                onConfirm: { Task { await vm.performClean() } },
                onCancel: { vm.cancelClean() }
            )
        }
    }

    // MARK: Content states

    @ViewBuilder
    private var content: some View {
        if vm.isLoading && vm.items.isEmpty {
            HStack(spacing: Theme.Spacing.sm) {
                ProgressView()
                Text(tr("common.scanning")).font(.mcCaption).foregroundStyle(AppColor.secondaryText)
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, Theme.Spacing.xxl)
        } else if vm.items.isEmpty {
            EmptyStateView(
                systemImage: "globe",
                title: tr("browser.empty.title"),
                message: tr("browser.empty.message")
            )
        } else {
            ForEach(vm.browsers) { browser in
                let rows = vm.items(for: browser)
                if !rows.isEmpty {
                    browserCard(browser, rows: rows)
                }
            }
        }
    }

    private func browserCard(_ browser: BrowserKind, rows: [Binding<BrowserDataItem>]) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            HStack(spacing: Theme.Spacing.md) {
                IconTile(systemName: browser.systemImage, tint: AppColor.primary)
                Text(browser.displayName).font(.mcCardTitle)
            }

            VStack(spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.element.wrappedValue.id) { index, row in
                    if index > 0 { Divider() }
                    dataRow(row)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    private func dataRow(_ item: Binding<BrowserDataItem>) -> some View {
        HStack(spacing: Theme.Spacing.md) {
            Toggle(isOn: item.isSelected) { EmptyView() }
                .toggleStyle(.checkbox)
                .labelsHidden()
                .accessibilityLabel(tr(item.wrappedValue.kind.titleKey))

            HStack(spacing: Theme.Spacing.md) {
                Text(tr(item.wrappedValue.kind.titleKey))
                    .font(.mcBody)
                    .foregroundStyle(AppColor.primaryText)

                RiskBadge(level: item.wrappedValue.kind.safety)

                Spacer(minLength: Theme.Spacing.sm)

                Text(item.wrappedValue.formattedSize)
                    .font(.mcBody.monospacedDigit())
                    .foregroundStyle(AppColor.secondaryText)
            }
            .contentShape(Rectangle())
            .onTapGesture { item.wrappedValue.isSelected.toggle() }
        }
        .padding(.vertical, Theme.Spacing.sm)
    }

    // MARK: Sticky bottom bar

    private var stickyBar: some View {
        HStack(spacing: Theme.Spacing.md) {
            VStack(alignment: .leading, spacing: 2) {
                Text(tr("browser.selectedSize")).eyebrow()
                Text(ByteFormat.string(fromBytes: vm.selectedBytes))
                    .font(.mcMetric(22))
                    .foregroundStyle(AppColor.primaryText)
                    .contentTransition(.numericText())
            }
            Spacer()
            Button { vm.startClean() } label: {
                Label(tr("browser.clean"), systemImage: "trash")
            }
            .buttonStyle(.primaryGradient)
            .tint(AppColor.primary)
            .controlSize(.large)
            .disabled(vm.selected.isEmpty || !vm.selectedRunningBrowsers.isEmpty || vm.isCleaning)
        }
        .padding(.horizontal, Theme.Spacing.outer)
        .padding(.vertical, Theme.Spacing.md)
        .glassCard(padding: Theme.Spacing.md)
        .padding(Theme.Spacing.outer)
    }
}

#Preview {
    BrowserView()
        .frame(width: 1024, height: 800)
}
