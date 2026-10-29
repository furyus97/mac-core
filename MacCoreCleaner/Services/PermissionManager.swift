import Foundation
import AppKit

/// Tracks access to TCC-protected folders (Downloads / Desktop / Documents) and
/// helps the user grant it. The app is intentionally **not** sandboxed (like
/// other Mac cleaners) and relies on the system's permission prompts; this type
/// surfaces the status so the UI can explain what is happening and never fails
/// silently.
@MainActor
final class PermissionManager: ObservableObject {

    enum Access: String {
        case granted
        case denied
        case unknown

        var isUsable: Bool { self == .granted || self == .unknown }
    }

    @Published private(set) var downloads: Access = .unknown
    @Published private(set) var desktop: Access = .unknown
    @Published private(set) var documents: Access = .unknown

    private let fm = FileManager.default

    /// Re-check all tracked folders. Reading a protected folder triggers the OS
    /// prompt on first use; afterwards a denial returns an error we can detect.
    func refresh() {
        downloads = access(to: URL.downloadsDirectory)
        desktop = access(to: URL.desktopDirectory)
        documents = access(to: URL.documentsDirectory)
    }

    /// Re-check only Downloads after the Storage scan has accessed it. Keeping
    /// this probe narrow avoids prompting for unrelated folders on app launch.
    func refreshDownloads() {
        downloads = access(to: URL.downloadsDirectory)
    }

    /// Probe a single folder's accessibility without modifying anything.
    func access(to url: URL) -> Access {
        do {
            _ = try fm.contentsOfDirectory(at: url, includingPropertiesForKeys: nil, options: [])
            return .granted
        } catch let error as NSError {
            // Cocoa error 257 = "couldn't be opened because you don't have permission".
            if error.domain == NSCocoaErrorDomain && (error.code == 257 || error.code == 256) {
                return .denied
            }
            // Folder may simply not exist or be momentarily unreadable.
            return .unknown
        }
    }

    /// Opens System Settings → Privacy & Security → Files and Folders so the user
    /// can grant access. (We never try to bypass the permission system.)
    func openPrivacySettings() {
        let urlString = "x-apple.systempreferences:com.apple.preference.security?Privacy_FilesAndFolders"
        if let url = URL(string: urlString) {
            NSWorkspace.shared.open(url)
        }
    }
}
