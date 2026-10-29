import SwiftUI
import AppKit
import Combine

/// Owns the live menu-bar status item (NSStatusItem) + its popover. Using AppKit
/// directly (instead of SwiftUI `MenuBarExtra`) reliably claims menu-bar space on
/// crowded menu bars and gives full control over the live title.
@MainActor
final class MenuBarController: NSObject {
    private let vm: MenuBarMonitorViewModel
    private let settings: SettingsStore
    private var statusItem: NSStatusItem?
    private let popover = NSPopover()
    private var cancellables = Set<AnyCancellable>()

    init(vm: MenuBarMonitorViewModel, settings: SettingsStore) {
        self.vm = vm
        self.settings = settings
        super.init()
    }

    func show() {
        guard statusItem == nil else { return }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            button.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
            button.target = self
            button.action = #selector(togglePopover(_:))
        }
        popover.behavior = .transient
        let host = NSHostingController(rootView: MenuBarPanel(
            vm: vm,
            settings: settings,
            localization: .shared
        ))
        host.sizingOptions = .preferredContentSize
        popover.contentViewController = host
        statusItem = item

        vm.startIfNeeded()
        // Refresh the title whenever the monitor publishes new readings.
        vm.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] in
                DispatchQueue.main.async { self?.updateTitle() }
            }
            .store(in: &cancellables)

        settings.$menuBarMetrics
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                DispatchQueue.main.async {
                    self?.applyConfiguration()
                    self?.vm.restart()
                }
            }
            .store(in: &cancellables)
        settings.$menuBarDisplayStyle
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in DispatchQueue.main.async { self?.applyConfiguration() } }
            .store(in: &cancellables)
        settings.$menuBarShowIcon
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in DispatchQueue.main.async { self?.applyConfiguration() } }
            .store(in: &cancellables)
        settings.$menuBarRefreshRate
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak vm] _ in vm?.restart() }
            .store(in: &cancellables)
        settings.$temperatureSource
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak vm] _ in vm?.restart() }
            .store(in: &cancellables)

        settings.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                DispatchQueue.main.async { self?.applyConfiguration() }
            }.store(in: &cancellables)
        settings.$menuBarSensorID.dropFirst().receive(on: RunLoop.main)
            .sink { [weak vm] _ in vm?.restart() }.store(in: &cancellables)

        applyConfiguration()
    }

    func hide() {
        cancellables.removeAll()
        popover.performClose(nil)
        vm.stop()
        if let item = statusItem {
            NSStatusBar.system.removeStatusItem(item)
            statusItem = nil
        }
    }

    private func applyConfiguration() {
        guard let button = statusItem?.button else { return }
        button.font = .monospacedDigitSystemFont(ofSize: min(13, max(11, settings.menuBarFontSize)), weight: .medium)
        if settings.menuBarShowIcon {
            let image = NSImage(
                systemSymbolName: "gauge.with.dots.needle.bottom.50percent",
                accessibilityDescription: "Mac Core"
            )
            image?.isTemplate = true
            button.image = image
            button.imagePosition = .imageLeading
        } else {
            button.image = nil
            button.imagePosition = .noImage
        }
        updateTitle()
    }

    private func updateTitle() {
        guard let button = statusItem?.button else { return }
        let title = MenuBarTitleFormatter.title(snapshot: vm.snapshot, settings: settings)
        button.title = settings.menuBarShowIcon ? " " + title : title
        button.toolTip = "Mac Core · " + title
    }

    @objc private func togglePopover(_ sender: NSStatusBarButton) {
        if popover.isShown {
            popover.performClose(sender)
        } else {
            popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }
}

/// App delegate that wires the menu-bar monitor to the `menuBarMonitor` setting.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var controller: MenuBarController?
    private var cancellable: AnyCancellable?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let settings = AppServices.shared.settings
        controller = MenuBarController(vm: MenuBarMonitorViewModel(), settings: settings)
        apply(settings.menuBarMonitor)
        cancellable = settings.$menuBarMonitor
            .receive(on: RunLoop.main)
            .sink { [weak self] enabled in self?.apply(enabled) }
    }

    private func apply(_ enabled: Bool) {
        enabled ? controller?.show() : controller?.hide()
    }

    /// Closing the dashboard is not quitting the app. The app-owned status item
    /// and sampling task continue until the user explicitly chooses Quit (⌘Q).
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldHandleReopen(
        _ sender: NSApplication,
        hasVisibleWindows flag: Bool
    ) -> Bool {
        if !flag, let window = sender.windows.first(where: \.canBecomeMain) {
            window.deminiaturize(nil)
            window.makeKeyAndOrderFront(nil)
        }
        return true
    }
}
