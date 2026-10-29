import SwiftUI

/// A small colored pill that communicates an item's safety level (안전/주의/위험).
struct SafetyBadge: View {
    let level: SafetyLevel
    var compact: Bool = false

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: level.systemImage)
                .font(.mcMicro)
            if !compact {
                Text(level.title)
                    .font(.mcMicro.weight(.semibold))
            }
        }
        .padding(.horizontal, compact ? 5 : 8)
        .padding(.vertical, 3)
        .foregroundStyle(level.tint)
        .background(
            Capsule().fill(level.tint.opacity(0.15))
        )
        .help(level.explanation)
    }
}

#Preview {
    HStack {
        SafetyBadge(level: .safe)
        SafetyBadge(level: .caution)
        SafetyBadge(level: .risky)
        SafetyBadge(level: .risky, compact: true)
    }
    .padding()
}
