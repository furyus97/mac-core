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
        #if DEBUG
        .onAppear {
            // Debug builds accept `-MCWindowSize 1440x900` for reproducible screenshots.
            guard let raw = UserDefaults.standard.string(forKey: "MCWindowSize") else { return }
            let parts = raw.split(separator: "x").compactMap { Double($0) }
            guard parts.count == 2 else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                guard let window = NSApp.windows.first(where: { $0.isVisible && $0.styleMask.contains(.titled) }) else { return }
                window.setFrame(NSRect(x: 80, y: 80, width: parts[0], height: parts[1]), display: true)
            }
        }
        #endif
    }

    // MARK: Sidebar

    private var sidebar: some View {
        VStack(spacing: 0) {
            brandHeader
            List {
                Section {
                    ForEach([NavItem.dashboard, .smartScan]) { item in sidebarRow(item) }
                }
                sidebarSection("sidebar.section.clean", [.storage, .developer, .browser, .applications])
                sidebarSection("sidebar.section.performance", [.speed, .memory, .cpu])
                sidebarSection("sidebar.section.files", [.spaceMap, .largeFiles, .duplicates])
                sidebarSection("sidebar.section.health", [.protection, .temperature, .battery, .network])
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
            .clipped()
            VStack(spacing: 8) {
                SidebarDiskCard()
                sidebarRow(.settings)
                SidebarStatusBar()
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)
            .padding(.bottom, 8)
            .overlay(alignment: .top) { Rectangle().fill(AppColor.divider.opacity(0.5)).frame(height: 0.5) }
        }
        .background(AppColor.sidebar.opacity(0.92))
        .navigationSplitViewColumnWidth(min: 230, ideal: 244, max: 320)
    }

    private func sidebarSection(_ key: String, _ items: [NavItem]) -> some View {
        Section {
            ForEach(items) { item in sidebarRow(item) }
        } header: {
            Text(tr(key).uppercased())
                .font(.mcMono(10, weight: .semibold)).tracking(1.0)
                .foregroundStyle(AppColor.secondaryText.opacity(0.8))
        }
    }

    private var brandHeader: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous).fill(AppGradient.brandDiagonal)
                Image(systemName: "sparkle").font(.system(size: 15, weight: .bold)).foregroundStyle(.white)
            }
            .frame(width: 32, height: 32)
            .shadow(color: Color(hex: "6D5DF6").opacity(0.35), radius: 8, y: 4)
            VStack(alignment: .leading, spacing: 1) {
                Text("MAC CORE").font(.system(size: 15, weight: .heavy, design: .rounded)).tracking(0.5).foregroundStyle(AppColor.primaryText)
                HStack(spacing: 5) {
                    Circle().fill(AppColor.success).frame(width: 5, height: 5)
                    Text(tr("sidebar.localMode")).font(.mcMono(9, weight: .medium)).tracking(0.4).foregroundStyle(AppColor.secondaryText)
                }
                .lineLimit(1).minimumScaleFactor(0.7)
            }
            Spacer()
        }
        .padding(.horizontal, 18)
        .padding(.top, 14).padding(.bottom, 10)
    }

    private func sidebarRow(_ item: NavItem) -> some View {
        let selected = (nav.selection ?? .dashboard) == item
        return Button { nav.selection = item } label: {
            HStack(spacing: 10) {
                Image(systemName: item.systemImage)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(selected ? AppColor.primary : AppColor.secondaryText)
                    .frame(width: 20)
                Text(item.title)
                    .font(.system(size: 13, weight: selected ? .semibold : .medium))
                    .foregroundStyle(AppColor.primaryText)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .contentShape(Rectangle())
            .background {
                if selected {
                    RoundedRectangle(cornerRadius: 10, style: .continuous).fill(AppColor.card)
                        .shadow(color: Color(hex: "3B2F8F").opacity(0.10), radius: 6, y: 2)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .listRowInsets(EdgeInsets(top: 1, leading: 0, bottom: 1, trailing: 0))
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
        case .speed: SpeedView()
        case .protection: ProtectionView()
        case .spaceMap: SpaceMapView()
        case .duplicates: DuplicatesView()
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
