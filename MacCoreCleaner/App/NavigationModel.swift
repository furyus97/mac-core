import SwiftUI

/// Shared sidebar selection so any screen (e.g. a Dashboard detail sheet) can
/// navigate to another section.
@MainActor
final class NavigationModel: ObservableObject {
    @Published var selection: NavItem? = NavigationModel.initialSelection

    private static var initialSelection: NavItem {
        #if DEBUG
        // Debug builds accept `-MCInitialScreen <item>` so screenshots can open any screen.
        if let raw = UserDefaults.standard.string(forKey: "MCInitialScreen"), let item = NavItem(rawValue: raw) { return item }
        #endif
        return .dashboard
    }
}
