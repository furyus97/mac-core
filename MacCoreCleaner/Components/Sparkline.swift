import SwiftUI

/// A tiny inline line+area chart for metric cards (telemetry feel). Lightweight
/// Path drawing — no Charts dependency. Auto-normalizes to its own min/max.
struct Sparkline: View {
    let values: [Double]
    var tint: Color = AppColor.primary
    var lineWidth: CGFloat = 1.5

    var body: some View {
        GeometryReader { geo in
            let pts = points(in: geo.size)
            if pts.count > 1 {
                ZStack {
                    areaPath(pts, height: geo.size.height)
                        .fill(AppGradient.area(tint))
                    linePath(pts)
                        .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
                }
            }
        }
        .accessibilityHidden(true)
    }

    private func points(in size: CGSize) -> [CGPoint] {
        guard values.count > 1, size.width > 0, size.height > 0 else { return [] }
        let lo = values.min() ?? 0
        let hi = values.max() ?? 1
        let span = max(hi - lo, 0.0001)
        let stepX = size.width / CGFloat(values.count - 1)
        // Inset vertically so the line never clips at the edges.
        let inset: CGFloat = lineWidth + 1
        let usable = max(size.height - inset * 2, 1)
        return values.enumerated().map { i, v in
            let norm = (v - lo) / span
            let y = inset + (1 - CGFloat(norm)) * usable
            return CGPoint(x: CGFloat(i) * stepX, y: y)
        }
    }

    private func linePath(_ pts: [CGPoint]) -> Path {
        var p = Path()
        p.move(to: pts[0])
        for pt in pts.dropFirst() { p.addLine(to: pt) }
        return p
    }

    private func areaPath(_ pts: [CGPoint], height: CGFloat) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: pts[0].x, y: height))
        p.addLine(to: pts[0])
        for pt in pts.dropFirst() { p.addLine(to: pt) }
        p.addLine(to: CGPoint(x: pts.last!.x, y: height))
        p.closeSubpath()
        return p
    }
}
