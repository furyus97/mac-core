import SwiftUI

/// Developer page tool card: size, last modified, "Safe to Clean" indicator and
/// a Review action. Docker is presented as display-only (no clean action), per
/// the safety policy.
struct DeveloperToolCard: View {
    let icon: String
    let title: String
    let subtitle: String
    let sizeBytes: Int64
    var lastModified: Date? = nil
    let level: SafetyLevel
    var isScanning: Bool = false
    /// Display-only tools (Docker) show info but no clean button.
    var displayOnly: Bool = false
    var onReview: (() -> Void)? = nil

    private var tint: Color { CleanGroup.developer.tint }

    private var safeToClean: Bool { level == .safe && !displayOnly }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            HStack(spacing: Theme.Spacing.md) {
                IconTile(systemName: icon, tint: tint, size: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.mcCardTitle)
                    Text(subtitle)
                        .font(.mcCaption)
                        .foregroundStyle(AppColor.secondaryText)
                        .lineLimit(1)
                }
                Spacer()
            }

            HStack(alignment: .firstTextBaseline) {
                if isScanning {
                    ProgressView().controlSize(.small)
                    Text(tr("common.scanning")).font(.mcCaption).foregroundStyle(AppColor.secondaryText)
                } else {
                    Text(ByteFormat.string(fromBytes: sizeBytes))
                        .font(.mcMetric(26))
                        .foregroundStyle(AppColor.primaryText)
                        .contentTransition(.numericText())
                }
                Spacer()
            }

            Divider()

            HStack {
                Label {
                    Text(displayOnly ? tr("comp.devCard.displayOnly") : (safeToClean ? tr("comp.devCard.safeToClean") : tr("comp.devCard.needsReview")))
                        .font(.mcCaption)
                } icon: {
                    Image(systemName: displayOnly ? "eye" : (safeToClean ? "checkmark.shield.fill" : "exclamationmark.triangle.fill"))
                }
                .foregroundStyle(displayOnly ? AppColor.secondaryText : (safeToClean ? AppColor.success : AppColor.warning))

                Spacer()

                if let lastModified {
                    Text(DateFormat.relativeString(lastModified))
                        .font(.mcMicro)
                        .foregroundStyle(AppColor.secondaryText)
                }
            }

            if displayOnly {
                Text(tr("comp.devCard.dockerNote"))
                    .font(.mcMicro)
                    .foregroundStyle(AppColor.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            } else if let onReview {
                Button(action: onReview) {
                    Text(tr("common.review")).frame(maxWidth: .infinity)
                }
                .controlSize(.large)
                .disabled(isScanning || sizeBytes == 0)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
        .hoverLift()
    }
}
