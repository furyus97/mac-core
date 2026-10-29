import SwiftUI
import AppKit

/// The Applications (uninstaller) screen: a searchable list of installed apps,
/// each with an "uninstall" action that opens a review of the app plus its
/// leftover support files before moving everything to the Trash.
struct ApplicationsView: View {
    @StateObject private var vm = ApplicationsViewModel()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                header

                if let outcome = vm.lastOutcome {
                    CleanOutcomeBanner(outcome: outcome)
                }

                searchField

                content
            }
            .padding(Theme.Spacing.outer)
        }
        .screenBackground()
        .navigationTitle(tr("nav.applications"))
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { Task { await vm.load() } } label: {
                    Label(tr("common.refresh"), systemImage: "arrow.clockwise")
                }
                .disabled(vm.isLoading || vm.isCleaning)
            }
        }
        .task { if vm.apps.isEmpty { await vm.load() } }
        .sheet(item: $vm.reviewing) { app in
            reviewSheet(for: app)
        }
        .sheet(isPresented: $vm.showConfirm) {
            ConfirmCleanSheet(
                items: vm.pendingItems,
                mode: $vm.mode,
                allowPermanent: false,
                onConfirm: { Task { await vm.performUninstall() } },
                onCancel: { vm.cancelUninstall() }
            )
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text(tr("apps.subtitle"))
                .font(.mcBody)
                .foregroundStyle(AppColor.secondaryText)
            if !vm.apps.isEmpty {
                Text(tr("apps.count", vm.apps.count))
                    .font(.mcCaption)
                    .foregroundStyle(AppColor.secondaryText)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var searchField: some View {
        HStack(spacing: Theme.Spacing.sm) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(AppColor.secondaryText)
            TextField(tr("apps.searchPlaceholder"), text: $vm.searchText)
                .textFieldStyle(.roundedBorder)
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if vm.isLoading && vm.apps.isEmpty {
            VStack(spacing: Theme.Spacing.md) {
                ProgressView()
                Text(tr("common.scanning"))
                    .font(.mcBody)
                    .foregroundStyle(AppColor.secondaryText)
            }
            .frame(maxWidth: .infinity, minHeight: 240)
        } else if vm.filteredApps.isEmpty {
            EmptyStateView(
                systemImage: "app.dashed",
                title: tr("apps.empty.title"),
                message: tr("apps.empty.message")
            )
        } else {
            VStack(spacing: Theme.Spacing.sm) {
                ForEach(vm.filteredApps) { app in
                    appRow(app)
                }
            }
            .card(padding: Theme.Spacing.md)
        }
    }

    private func appRow(_ app: InstalledApp) -> some View {
        HStack(spacing: Theme.Spacing.md) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: app.bundleURL.path(percentEncoded: false)))
                .resizable()
                .frame(width: 40, height: 40)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: Theme.Spacing.sm) {
                    Text(app.name)
                        .font(.mcCardTitle)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if app.isSystem {
                        Text(tr("apps.systemTag"))
                            .font(.mcMicro)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .foregroundStyle(AppColor.secondaryText)
                            .background(Capsule().fill(AppColor.secondaryText.opacity(0.14)))
                    } else if vm.isRunning(app) {
                        Text(tr("apps.runningTag"))
                            .font(.mcMicro)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .foregroundStyle(AppColor.warning)
                            .background(Capsule().fill(AppColor.warning.opacity(0.14)))
                    }
                }
                Text(tr("apps.version", app.version))
                    .font(.mcCaption)
                    .foregroundStyle(AppColor.secondaryText)
                    .lineLimit(1)
            }

            Spacer(minLength: Theme.Spacing.sm)

            VStack(alignment: .trailing, spacing: 2) {
                Text(app.formattedSize)
                    .font(.mcBody.monospacedDigit())
                Text(tr("apps.installed", DateFormat.string(app.installDate)))
                    .font(.mcMicro)
                    .foregroundStyle(AppColor.secondaryText)
            }
            .frame(width: 160, alignment: .trailing)

            Button(role: .destructive) {
                vm.openReview(app)
            } label: {
                Text(tr("apps.uninstall"))
            }
            .buttonStyle(.bordered)
            .tint(AppColor.danger)
            .disabled(app.isSystem || vm.isRunning(app) || vm.isCleaning)
            .help(vm.isRunning(app) ? tr("apps.quitBeforeUninstall") : "")
        }
        .padding(.vertical, Theme.Spacing.xs)
        .padding(.horizontal, Theme.Spacing.sm)
    }

    // MARK: - Review sheet

    private func reviewSheet(for app: InstalledApp) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            HStack(spacing: Theme.Spacing.md) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: app.bundleURL.path(percentEncoded: false)))
                    .resizable()
                    .frame(width: 48, height: 48)
                VStack(alignment: .leading, spacing: 2) {
                    Text(app.name).font(.title2.bold())
                    Text(tr("apps.version", app.version))
                        .font(.mcCaption)
                        .foregroundStyle(AppColor.secondaryText)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(app.formattedSize).font(.mcMetric(22))
                    Text(tr("apps.appBundle"))
                        .font(.mcMicro)
                        .foregroundStyle(AppColor.secondaryText)
                }
            }

            InfoBanner(kind: .warning, message: tr("apps.relatedFilesInfo"))

            SectionTitle(tr("apps.relatedFiles"))

            if vm.leftovers.isEmpty {
                Text(tr("apps.noRelatedFiles"))
                    .font(.mcBody)
                    .foregroundStyle(AppColor.secondaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, Theme.Spacing.md)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(vm.leftovers.indices, id: \.self) { index in
                            CleanableItemRow(item: vm.leftoverBinding(index))
                            if index < vm.leftovers.count - 1 {
                                Divider()
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
                .frame(maxHeight: 280)
                .background(
                    RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                        .fill(Color.secondary.opacity(0.06))
                )

                Text(tr("apps.selectedTotal", ByteFormat.string(fromBytes: vm.selectedLeftoverBytes)))
                    .font(.mcCaption)
                    .foregroundStyle(AppColor.secondaryText)
            }

            HStack {
                Spacer()
                Button(tr("common.close"), role: .cancel) { vm.reviewing = nil }
                    .keyboardShortcut(.cancelAction)
                Button(tr("common.moveToTrash"), role: .destructive) { vm.startUninstall() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(PrimaryGradientButtonStyle(tint: AppColor.danger))
            }
        }
        .padding(Theme.Spacing.xl)
        .frame(width: 620)
    }
}

#Preview {
    ApplicationsView()
        .frame(width: 1024, height: 800)
}
