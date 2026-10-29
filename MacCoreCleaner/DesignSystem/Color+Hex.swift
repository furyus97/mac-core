import SwiftUI
import AppKit

/// Hex + dynamic light/dark color support so the palette can use the exact spec
/// values while still adapting automatically to appearance (HIG-compliant).
extension NSColor {
    convenience init(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if s.hasPrefix("#") { s.removeFirst() }
        var rgb: UInt64 = 0
        Scanner(string: s).scanHexInt64(&rgb)
        let r, g, b, a: CGFloat
        if s.count == 8 {
            r = CGFloat((rgb & 0xFF00_0000) >> 24) / 255
            g = CGFloat((rgb & 0x00FF_0000) >> 16) / 255
            b = CGFloat((rgb & 0x0000_FF00) >> 8) / 255
            a = CGFloat(rgb & 0x0000_00FF) / 255
        } else {
            r = CGFloat((rgb & 0xFF0000) >> 16) / 255
            g = CGFloat((rgb & 0x00FF00) >> 8) / 255
            b = CGFloat(rgb & 0x0000FF) / 255
            a = 1
        }
        self.init(srgbRed: r, green: g, blue: b, alpha: a)
    }
}

extension Color {
    init(hex: String) {
        self.init(nsColor: NSColor(hex: hex))
    }

    /// A color that resolves to `lightHex` in light appearance and `darkHex` in dark.
    init(lightHex: String, darkHex: String) {
        self.init(nsColor: NSColor(name: nil, dynamicProvider: { appearance in
            let match = appearance.bestMatch(from: [.aqua, .darkAqua])
            return NSColor(hex: match == .darkAqua ? darkHex : lightHex)
        }))
    }
}
