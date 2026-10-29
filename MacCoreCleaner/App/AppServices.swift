import Foundation

/// Shared service container (lightweight dependency injection).
///
/// View-models default to `AppServices.shared` but accept an injected instance,
/// which keeps them testable. The same `SettingsStore`/`PermissionManager`
/// instances are also injected into the SwiftUI environment by the app entry
/// point, so settings stay in sync everywhere.
@MainActor
final class AppServices {
    static let shared = AppServices()

    let safety: SafetyGuard
    let settings: SettingsStore
    let permissions: PermissionManager
    let cleaner: CleanerService

    let scanner: Scanning
    let developer: DeveloperCleaning
    let storage: StorageAnalyzing
    let processMonitor: ProcessMonitoring
    let battery: BatteryMonitoring
    let network: NetworkMonitoring
    let temperature: TemperatureMonitoring
    let appInventory: AppInventory
    let largeFiles: LargeFileScanning
    let browser: BrowserCleaning

    init() {
        let safety = SafetyGuard()
        self.safety = safety
        self.settings = SettingsStore()
        self.permissions = PermissionManager()
        self.cleaner = CleanerService(safety: safety)
        self.scanner = ScanService(safety: safety)
        self.developer = DeveloperCleanerService(safety: safety)
        self.storage = StorageAnalyzerService()
        self.processMonitor = ProcessMonitorService()
        self.battery = BatteryService()
        self.network = NetworkService()
        self.temperature = TemperatureService()
        self.appInventory = AppInventoryService()
        self.largeFiles = LargeFileService()
        self.browser = BrowserCleanerService()
    }
}
