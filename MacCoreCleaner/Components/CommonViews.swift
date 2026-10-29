import SwiftUI
import AppKit

/// Keep partial success and each failure visible; never silently discard errors.
struct CleanOutcomeBanner: View {
    let outcome: CleanOutcome

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            InfoBanner(kind: outcome.hasFailures ? .warning : .info,
                       message: tr("stor.outcomeSuccess", outcome.formattedProcessed, outcome.removedCount))
            if outcome.hasFailures {
                DisclosureGroup(tr("clean.failures", outcome.failures.count)) {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 12) {
                            ForEach(outcome.failures) { failure in
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(failure.url.path).font(.mcMono(11)).textSelection(.enabled)
                                    Text(failure.reason).font(.mcCaption).foregroundStyle(AppColor.secondaryText)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                        .padding(.top, 8)
                    }
                    .frame(maxHeight: 180)
                }
                .font(.mcBodyMedium)
                .padding(.horizontal, 12)
            }
        }
    }
}

/// Reveal a file or folder in Finder.
enum FinderHelper {
    static func reveal(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
}

/// Centered empty / placeholder state.
struct EmptyStateView: View {
    let systemImage: String
    let title: String
    var message: String? = nil

    var body: some View {
        VStack(spacing: Theme.Spacing.md) {
            Image(systemName: systemImage)
                .font(.system(size: 42))
                .foregroundStyle(.secondary)
            Text(title).font(.mcCardTitle)
            if let message {
                Text(message)
                    .font(.mcBody)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 380)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(Theme.Spacing.xxl)
    }
}

/// An inline informational / warning banner (used for permission prompts and
/// safety notices).
struct InfoBanner: View {
    enum Kind { case info, warning, danger
        var tint: Color {
            switch self { case .info: return .blue; case .warning: return Theme.Palette.caution; case .danger: return Theme.Palette.risky }
        }
        var icon: String {
            switch self { case .info: return "info.circle.fill"; case .warning: return "exclamationmark.triangle.fill"; case .danger: return "xmark.octagon.fill" }
        }
    }

    let kind: Kind
    let message: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.sm) {
            Image(systemName: kind.icon).foregroundStyle(kind.tint)
            Text(message)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.borderless)
                    .foregroundStyle(kind.tint)
            }
        }
        .padding(Theme.Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                .fill(kind.tint.opacity(0.12))
        )
    }
}
