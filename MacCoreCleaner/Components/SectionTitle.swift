import SwiftUI

/// A 22pt section header with an optional trailing accessory.
struct SectionTitle<Trailing: View>: View {
    let text: String
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(text).font(.mcSectionTitle)
            Spacer(minLength: Theme.Spacing.md)
            trailing()
        }
    }
}

extension SectionTitle where Trailing == EmptyView {
    init(_ text: String) {
        self.init(text: text, trailing: { EmptyView() })
    }
}

/// Spec risk pill: Safe / Warning / Advanced.
struct RiskBadge: View {
    let level: SafetyLevel

    var body: some View {
        HStack(spacing: 5) {
            Circle().fill(level.tint).frame(width: 6, height: 6)
            Text(level.riskLabel).font(.mcMicro)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .foregroundStyle(level.tint)
        .background(Capsule().fill(level.tint.opacity(0.14)))
        .help(level.explanation)
    }
}

/// A small up/down trend chip ("최근 변화").
struct TrendChip: View {
    let up: Bool
    let text: String
    /// For most metrics, "down" (less usage) is good. Override when up is good.
    var positiveWhenDown: Bool = true

    private var good: Bool { positiveWhenDown ? !up : up }

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: up ? "arrow.up.right" : "arrow.down.right")
            Text(text)
        }
        .font(.mcMicro)
        .foregroundStyle(good ? AppColor.success : AppColor.secondaryText)
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(Capsule().fill((good ? AppColor.success : AppColor.secondaryText).opacity(0.12)))
    }
}
