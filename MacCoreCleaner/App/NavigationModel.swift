import SwiftUI

/// Shared sidebar selection so any screen (e.g. a Dashboard detail sheet) can
/// navigate to another section.
@MainActor
final class NavigationModel: ObservableObject {
    @Published var selection: NavItem? = .dashboard
}
