import SwiftUI

// MARK: - Packing

/// A placed circle in view coordinates.
struct PackedCircle: Equatable, Sendable {
    var center: CGPoint
    var radius: CGFloat
}

/// Deterministic circle packing: circle *area* is proportional to its weight
/// (with a small visibility floor for tiny items). Circles are placed largest
/// first; each next circle goes to the tangent position that keeps the layout
/// as large as possible inside the container (then closest to its middle).
/// The result never overlaps and always fits inside `size` minus `inset`.
enum BubblePacker {
    static func pack(
        weights: [Double],
        in size: CGSize,
        inset: CGFloat = 6,
        minRadiusFraction: Double = 0.12
    ) -> [PackedCircle] {
        let width = Double(size.width - inset * 2), height = Double(size.height - inset * 2)
        guard !weights.isEmpty, width > 1, height > 1 else { return [] }

        // Radii in abstract units (area ∝ weight).
        var radii = weights.map { sqrt(max($0.isFinite ? $0 : 0, 0)) }
        let largest = radii.max() ?? 0
        if largest <= 0 { radii = radii.map { _ in 1 } }
        let maxR = radii.max() ?? 1
        radii = radii.map { max($0, maxR * minRadiusFraction) }
        let gap = maxR * 0.05

        let order = radii.indices.sorted { radii[$0] != radii[$1] ? radii[$0] > radii[$1] : $0 < $1 }
        var centers = [CGPoint?](repeating: nil, count: radii.count)
        var placed: [(c: CGPoint, r: Double)] = []
        var box = (minX: 0.0, maxX: 0.0, minY: 0.0, maxY: 0.0)

        for index in order {
            let r = radii[index]
            if placed.isEmpty {
                centers[index] = .zero
                placed.append((.zero, r))
                box = (-r, r, -r, r)
                continue
            }

            var candidates: [CGPoint] = []
            // Tangent to one placed circle, at 16 fixed angles.
            for p in placed {
                let d = p.r + r + gap
                for step in 0..<16 {
                    let a = Double(step) * .pi / 8
                    candidates.append(CGPoint(x: p.c.x + d * cos(a), y: p.c.y + d * sin(a)))
                }
            }
            // Tangent to two placed circles.
            for i in placed.indices {
                for j in placed.indices where j > i {
                    candidates.append(contentsOf: tangentPoints(placed[i], placed[j], r: r, gap: gap))
                }
            }

            var best: CGPoint?
            var bestScore = Double.infinity
            let midX = (box.minX + box.maxX) / 2, midY = (box.minY + box.maxY) / 2
            for c in candidates {
                let overlaps = placed.contains { p in
                    hypot(c.x - p.c.x, c.y - p.c.y) < p.r + r + gap - 1e-7
                }
                if overlaps { continue }
                let bw = max(box.maxX, c.x + r) - min(box.minX, c.x - r)
                let bh = max(box.maxY, c.y + r) - min(box.minY, c.y - r)
                // Primary: how much the layout must shrink to fit. Secondary: compactness.
                let fit = max(bw / width, bh / height)
                let score = fit * 1_000 + hypot((c.x - midX) / width, (c.y - midY) / height)
                if score < bestScore - 1e-9 { bestScore = score; best = c }
            }
            // Fallback (should not happen): park it to the right of everything.
            let point = best ?? CGPoint(x: box.maxX + r + gap, y: 0)
            centers[index] = point
            placed.append((point, r))
            box = (min(box.minX, point.x - r), max(box.maxX, point.x + r),
                   min(box.minY, point.y - r), max(box.maxY, point.y + r))
        }

        let bw = box.maxX - box.minX, bh = box.maxY - box.minY
        let scale = min(width / bw, height / bh)
        let offsetX = Double(inset) + (width - bw * scale) / 2 - box.minX * scale
        let offsetY = Double(inset) + (height - bh * scale) / 2 - box.minY * scale
        return radii.indices.map { i in
            let c = centers[i] ?? .zero
            return PackedCircle(
                center: CGPoint(x: c.x * scale + offsetX, y: c.y * scale + offsetY),
                radius: CGFloat(radii[i] * scale)
            )
        }
    }

    /// Centers of a circle of radius `r` tangent (with `gap`) to both `a` and `b`.
    private static func tangentPoints(_ a: (c: CGPoint, r: Double), _ b: (c: CGPoint, r: Double), r: Double, gap: Double) -> [CGPoint] {
        let ra = a.r + r + gap, rb = b.r + r + gap
        let dx = b.c.x - a.c.x, dy = b.c.y - a.c.y
        let d = hypot(dx, dy)
        guard d > 1e-9, d <= ra + rb, d >= abs(ra - rb) else { return [] }
        let along = (ra * ra - rb * rb + d * d) / (2 * d)
        let h = sqrt(max(0, ra * ra - along * along))
        let mx = a.c.x + along * dx / d, my = a.c.y + along * dy / d
        return [
            CGPoint(x: mx + h * dy / d, y: my - h * dx / d),
            CGPoint(x: mx - h * dy / d, y: my + h * dx / d),
        ]
    }
}

// MARK: - Icon style

/// Glyph + gradient for a Space Map item, based on well-known folder names and
/// common file types. Shared by the bubble chart and the side list.
enum SpaceNodeStyle {
    static func icon(for node: SpaceNode) -> (symbol: String, colors: [Color]) {
        switch node.url.lastPathComponent {
        case "Downloads": return ("arrow.down.circle.fill", TileColor.apps)
        case "Documents": return ("doc.text.fill", TileColor.protection)
        case "Desktop": return ("menubar.dock.rectangle", TileColor.system)
        case "Library": return ("books.vertical.fill", TileColor.files)
        case "Movies": return ("film.fill", TileColor.cleanup)
        case "Music": return ("music.note", [Color(hex: "E26BB4"), Color(hex: "A23D7C")])
        case "Pictures": return ("photo.fill", TileColor.speed)
        case "Developer": return ("hammer.fill", [Color(hex: "8B5CF6"), Color(hex: "5B2BC4")])
        case "Applications": return ("square.grid.2x2.fill", TileColor.apps)
        case "Public": return ("person.2.fill", TileColor.system)
        case ".Trash": return ("trash.fill", TileColor.cleanup)
        case "Caches": return ("archivebox.fill", TileColor.files)
        case "Mobile Documents", "iCloud Drive": return ("icloud.fill", TileColor.apps)
        case "Containers", "Group Containers": return ("shippingbox.fill", TileColor.protection)
        case "Application Support": return ("gearshape.2.fill", [Color(hex: "7D7A92"), Color(hex: "4E4B63")])
        case "Mail": return ("envelope.fill", TileColor.apps)
        case "Messages": return ("message.fill", TileColor.speed)
        case "Photos Library.photoslibrary": return ("photo.on.rectangle.angled", TileColor.speed)
        default: break
        }
        let ext = node.url.pathExtension.lowercased()
        switch ext {
        case "app": return ("app.fill", TileColor.apps)
        case "photoslibrary": return ("photo.on.rectangle.angled", TileColor.speed)
        case "mov", "mp4", "m4v", "mkv", "avi": return ("film.fill", TileColor.cleanup)
        case "jpg", "jpeg", "png", "heic", "gif", "tiff", "raw", "dng": return ("photo.fill", TileColor.speed)
        case "mp3", "m4a", "aac", "wav", "flac", "aiff": return ("music.note", [Color(hex: "E26BB4"), Color(hex: "A23D7C")])
        case "zip", "dmg", "pkg", "tar", "gz", "7z", "rar", "xip", "iso": return ("archivebox.fill", TileColor.files)
        case "pdf": return ("doc.richtext.fill", TileColor.cleanup)
        default: break
        }
        if node.isDirectory { return ("folder.fill", [Color(hex: "7B6CF6"), Color(hex: "A06BF0")]) }
        return ("doc.fill", [Color(hex: "9A97AE"), Color(hex: "66637A")])
    }

    /// Coral gradient for "reclaimable" badges.
    static let coral = LinearGradient(colors: [Color(hex: "FF8A6B"), Color(hex: "F2557A")],
                                      startPoint: .topLeading, endPoint: .bottomTrailing)
}

// MARK: - Chart

/// Packed-bubble disk-usage chart. Self-contained: give it nodes, optionally a
/// tap handler. Works from small dashboard cards (~360×300) to full screen.
struct SpaceBubbleChart: View {
    let nodes: [SpaceNode]
    var onSelect: ((SpaceNode) -> Void)?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(nodes: [SpaceNode], onSelect: ((SpaceNode) -> Void)? = nil) {
        self.nodes = nodes
        self.onSelect = onSelect
    }

    var body: some View {
        GeometryReader { geo in
            let circles = BubblePacker.pack(weights: nodes.map { Double($0.bytes) }, in: geo.size)
            ZStack(alignment: .topLeading) {
                ForEach(Array(zip(nodes, circles)), id: \.0.id) { pair in
                    let (node, circle) = pair
                    SpaceBubble(node: node, radius: circle.radius, onSelect: onSelect)
                        .frame(width: circle.radius * 2, height: circle.radius * 2)
                        .position(circle.center)
                        .transition(.scale(scale: 0.6).combined(with: .opacity))
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .animation(reduceMotion ? nil : .spring(response: 0.5, dampingFraction: 0.82), value: nodes)
        }
    }
}

/// One glassy bubble.
private struct SpaceBubble: View {
    let node: SpaceNode
    let radius: CGFloat
    let onSelect: ((SpaceNode) -> Void)?
    @State private var hovering = false
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var sizeText: String { ByteFormat.string(fromBytes: node.bytes) }

    var body: some View {
        let style = SpaceNodeStyle.icon(for: node)
        let content = ZStack {
            bubbleSurface(tint: style.colors.first ?? AppColor.primary)
            labels(style)
                .padding(radius * 0.18)
            if let reclaim = node.reclaimableBytes, reclaim > 0, radius >= 26 {
                badge(reclaim)
                    .position(x: radius * 1.62, y: radius * 0.30)
            }
        }
        .scaleEffect(hovering && !reduceMotion ? 1.035 : 1)
        .contentShape(Circle())
        .help("\(node.name) — \(sizeText)")
        .onHover { state in
            if reduceMotion { hovering = state }
            else { withAnimation(.spring(response: 0.28, dampingFraction: 0.75)) { hovering = state } }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(node.name), \(sizeText)")

        if let onSelect {
            Button { onSelect(node) } label: { content }
                .buttonStyle(.plain)
                .accessibilityAddTraits(.isButton)
        } else {
            content
        }
    }

    private func bubbleSurface(tint: Color) -> some View {
        let dark = scheme == .dark
        return Circle()
            .fill(dark ? AppColor.card : Color.white)
            .overlay(
                Circle().fill(RadialGradient(
                    colors: [tint.opacity(dark ? 0.16 : 0.07), .clear],
                    center: UnitPoint(x: 0.5, y: 0.85), startRadius: 0, endRadius: radius * 1.2))
            )
            .overlay(
                Circle().fill(RadialGradient(
                    colors: [Color.white.opacity(dark ? 0.10 : 0.9), Color.white.opacity(0)],
                    center: UnitPoint(x: 0.32, y: 0.22), startRadius: 0, endRadius: radius * 0.9))
            )
            .overlay(
                Circle().strokeBorder(
                    hovering ? AnyShapeStyle(AppColor.primary.opacity(0.45)) : AnyShapeStyle(AppGradient.cardHairline),
                    lineWidth: hovering ? 1.2 : 0.8)
                    .opacity(dark && !hovering ? 0.35 : 1)
            )
            .shadow(color: Color(hex: "3B2F8F").opacity(dark ? 0.35 : (hovering ? 0.16 : 0.10)),
                    radius: max(4, radius * 0.16), x: 0, y: max(2, radius * 0.07))
    }

    @ViewBuilder
    private func labels(_ style: (symbol: String, colors: [Color])) -> some View {
        let iconSize = min(40, max(14, radius * 0.42))
        if radius >= 46 {
            VStack(spacing: max(2, radius * 0.05)) {
                IconTile(systemName: style.symbol, size: iconSize, colors: style.colors)
                Text(node.name)
                    .font(.system(size: min(15, max(10, radius * 0.19)), weight: .semibold))
                    .foregroundStyle(AppColor.primaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(sizeText)
                    .font(.mcMono(min(13, max(9, radius * 0.16)), weight: .medium))
                    .foregroundStyle(AppColor.secondaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        } else if radius >= 30 {
            VStack(spacing: 2) {
                IconTile(systemName: style.symbol, size: min(30, radius * 0.5), colors: style.colors)
                Text(sizeText)
                    .font(.mcMono(9, weight: .medium))
                    .foregroundStyle(AppColor.secondaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
        } else if radius >= 14 {
            IconTile(systemName: style.symbol, size: radius * 0.95, colors: style.colors)
        } else {
            Circle().fill(AppGradient.tile(style.colors)).frame(width: radius * 0.9, height: radius * 0.9)
        }
    }

    private func badge(_ bytes: Int64) -> some View {
        HStack(spacing: 3) {
            Image(systemName: "sparkles").font(.system(size: 8, weight: .bold))
            Text(ByteFormat.string(fromBytes: bytes))
                .font(.system(size: radius >= 50 ? 10 : 9, weight: .bold, design: .rounded).monospacedDigit())
                .lineLimit(1)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 6).padding(.vertical, 3)
        .background(Capsule().fill(SpaceNodeStyle.coral))
        .overlay(Capsule().strokeBorder(Color.white.opacity(0.6), lineWidth: 0.8))
        .shadow(color: Color(hex: "F2557A").opacity(0.35), radius: 4, x: 0, y: 2)
        .fixedSize()
    }
}

#Preview("Space bubbles") {
    let home = URL(fileURLWithPath: "/Users/example")
    let sample: [(String, Int64, Int64?)] = [
        ("Library", 92_000_000_000, nil), ("Developer", 41_000_000_000, nil),
        ("Movies", 28_000_000_000, nil), ("Downloads", 17_000_000_000, nil),
        ("Pictures", 12_000_000_000, nil), ("Documents", 8_000_000_000, nil),
        ("Music", 4_000_000_000, nil), ("Desktop", 1_800_000_000, nil),
        (".Trash", 900_000_000, 900_000_000), ("Applications", 400_000_000, nil),
    ]
    return SpaceBubbleChart(nodes: sample.map {
        SpaceNode(url: home.appending(path: $0.0), bytes: $0.1, isDirectory: true, reclaimableBytes: $0.2)
    })
    .frame(width: 360, height: 300)
    .padding()
}
