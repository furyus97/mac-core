import SwiftUI

@main
struct MacCoreCleanerApp: App {
    // Shared, app-wide observable objects (same instances as AppServices.shared).
    @StateObject private var settings = AppServices.shared.settings
    @StateObject private var permissions = AppServices.shared.permissions
    @StateObject private var localization = LocalizationManager.shared
    @StateObject private var nav = NavigationModel()
    // Owns the live menu-bar status item (NSStatusItem), gated by the setting.
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Window("Mac Core", id: "main") {
            ContentView()
                .environmentObject(settings)
                .environmentObject(permissions)
                .environmentObject(localization)
                .environmentObject(nav)
                .frame(minWidth: Theme.Sizes.windowMinWidth, minHeight: Theme.Sizes.windowMinHeight)
                .preferredColorScheme(settings.appearance.colorScheme)
                .environment(\.locale, localization.locale)
                .environment(\.layoutDirection, localization.layoutDirection)
        }
        .windowResizability(.contentMinSize)
        .windowToolbarStyle(.unified(showsTitle: true))
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button(tr("menu.about")) {
                    NSApplication.shared.orderFrontStandardAboutPanel(nil)
                }
            }
        }
    }
}
