import SwiftUI
import AppKit

/// Root sidebar + detail layout for Mac Core (native `NavigationSplitView`).
struct ContentView: View {
    var dashboardModel: DashboardViewModel? = nil
    var hardwareModel: HardwareMonitorViewModel? = nil
    var automaticallyRefresh = true
    @EnvironmentObject private var nav: NavigationModel
    // Observing the manager re-renders the sidebar on language change; the
    // `.id` rebuilds the detail subtree so every string refreshes live.
    @EnvironmentObject private var localization: LocalizationManager

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detail(for: nav.selection ?? .dashboard)
                .id(localization.language)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .screenBackground()
                .safeAreaInset(edge: .top, spacing: 0) {
                    ScreenHeader(item: nav.selection ?? .dashboard)
                }
        }
        .navigationSplitViewStyle(.balanced)
    }

    // MARK: Sidebar

    private var sidebar: some View {
        List {
            Section {
                ForEach([NavItem.dashboard, .smartScan]) { item in
                    sidebarRow(item)
                }
            } header: {
                Text(tr("sidebar.section.overview")).foregroundStyle(AppColor.secondaryText)
            }
            Section {
                ForEach([NavItem.storage, .memory, .cpu, .temperature, .battery, .network]) { item in
                    sidebarRow(item)
                }
            } header: {
                Text(tr("sidebar.section.insights")).foregroundStyle(AppColor.secondaryText)
            }
            Section {
                ForEach([NavItem.developer, .applications, .largeFiles, .browser]) { item in
                    sidebarRow(item)
                }
            } header: {
                Text(tr("sidebar.section.tools")).foregroundStyle(AppColor.secondaryText)
            }
        }
        .listStyle(.sidebar)
        .navigationSplitViewColumnWidth(min: 240, ideal: 250, max: 320)
        .scrollContentBackground(.hidden)
        .background(AppColor.sidebar)
        .safeAreaInset(edge: .top) { brandHeader }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 0) {
                Divider().opacity(0.5)
                sidebarRow(.settings).padding(.horizontal, 16).padding(.vertical, 6)
                SidebarStatusBar()
            }.background(AppColor.sidebar)
        }
    }

    private var brandHeader: some View {
        HStack(spacing: Theme.Spacing.sm) {
            Image(nsImage: NSApplication.shared.applicationIconImage)
                .resizable()
                .interpolation(.high)
                .frame(width: 38, height: 38)
            VStack(alignment: .leading, spacing: 1) {
                Text("Mac Core").font(.system(size: 16, weight: .bold)).foregroundStyle(AppColor.primaryText)
                HStack(spacing: 5) {
                    Circle().fill(AppColor.success).frame(width: 5, height: 5)
                    Text(tr("sidebar.localMode"))
                        .font(.mcMono(9, weight: .medium))
                        .tracking(0.4)
                        .foregroundStyle(AppColor.secondaryText)
                }
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            Spacer()
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, Theme.Spacing.md)
        .background(AppColor.sidebar)
    }

    private func sidebarRow(_ item: NavItem) -> some View {
        let selected = (nav.selection ?? .dashboard) == item
        return Button { nav.selection = item } label: {
            Label {
                Text(item.title).foregroundStyle(selected ? AppColor.primary : AppColor.primaryText)
            } icon: {
                Image(systemName: item.systemImage)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(selected ? AppColor.primaryText : AppColor.secondaryText)
                    .frame(width: 20)
            }
            .font(.mcBodyMedium)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .contentShape(Rectangle())
            .background(RoundedRectangle(cornerRadius: 10).fill(selected ? AppColor.primary.opacity(0.12) : .clear))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .listRowInsets(EdgeInsets(top: 2, leading: 0, bottom: 2, trailing: 0))
    }

    // MARK: Detail routing

    @ViewBuilder
    private func detail(for item: NavItem) -> some View {
        switch item {
        case .dashboard: DashboardView(vm: dashboardModel, automaticallyRefresh: automaticallyRefresh)
        case .smartScan: SmartScanView()
        case .storage: StorageCleanerView()
        case .memory: MemoryMonitorView()
        case .cpu: CPUMonitorView()
        case .temperature: HardwareMonitorView(metric: .temperature, vm: hardwareModel, automaticallyRefresh: automaticallyRefresh)
        case .battery: HardwareMonitorView(metric: .battery, vm: hardwareModel, automaticallyRefresh: automaticallyRefresh)
        case .network: HardwareMonitorView(metric: .network, vm: hardwareModel, automaticallyRefresh: automaticallyRefresh)
        case .developer: DeveloperCleanerView()
        case .applications: ApplicationsView()
        case .largeFiles: LargeFilesView()
        case .browser: BrowserView()
        case .settings: SettingsView()
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(AppServices.shared.settings)
        .environmentObject(AppServices.shared.permissions)
        .environmentObject(LocalizationManager.shared)
        .environmentObject(NavigationModel())
        .frame(width: 1280, height: 820)
}
