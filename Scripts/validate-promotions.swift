import Foundation
import ImageIO
import CryptoKit

// Read-only image validation; emits a manifest to stdout.
let root = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "프로모션 이미지", isDirectory: true)
let folders = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isDirectoryKey])
    .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true && !$0.lastPathComponent.hasPrefix("_") }
let expected = ["01-overview.png", "02-storage.png", "03-temperature.png", "04-battery-power.png", "05-menu-bar.png"]
precondition(folders.count == 10, "Expected ten locale directories")
var entries: [[String: Any]] = []
for folder in folders.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
    let pngs = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil).filter { $0.pathExtension == "png" }
    precondition(Set(pngs.map(\.lastPathComponent)) == Set(expected), "Unexpected image set: \(folder.path)")
    for name in expected {
        let url = folder.appending(path: name)
        let data = try Data(contentsOf: url)
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else {
            fatalError("Unreadable PNG: \(url.path)")
        }
        precondition(properties[kCGImagePropertyPixelWidth] as? Int == 2880)
        precondition(properties[kCGImagePropertyPixelHeight] as? Int == 1800)
        precondition(properties[kCGImagePropertyHasAlpha] as? Bool != true)
        let profile = properties[kCGImagePropertyProfileName] as? String ?? ""
        precondition(profile.lowercased().contains("srgb"), "Missing sRGB profile")
        precondition(data.count > 100_000, "Suspicious empty image")
        entries.append(["file": folder.lastPathComponent + "/" + name, "width": 2880, "height": 1800,
                        "alpha": false, "profile": profile, "bytes": data.count,
                        "sha256": SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()])
    }
}
precondition(entries.count == 50)
let manifest: [String: Any] = ["count": entries.count, "locales": folders.count, "validated": true, "images": entries]
let json = try JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
FileHandle.standardOutput.write(json)
