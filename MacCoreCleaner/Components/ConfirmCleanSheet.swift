import SwiftUI

/// The pre-deletion confirmation modal (core principle #2 & #5).
///
/// Shows the total count and size, the highest safety level among the selected
/// items, a scrollable preview of exactly what will be removed, and the removal
/// mode. Permanent deletion requires an extra explicit acknowledgement.
struct ConfirmCleanSheet: View {
    let items: [CleanableItem]
    @Binding var mode: RemovalMode
    /// Whether permanent deletion is even offered (gated by advanced mode).
    let allowPermanent: Bool
    /// Trash contents cannot be moved to Trash again; this locks the sheet to
    /// permanent deletion while retaining the explicit acknowledgement.
    var forcePermanent: Bool = false
    let onConfirm: () -> Void
    let onCancel: () -> Void

    @State private var acknowledgedPermanent = false

    private var totalBytes: Int64 { items.reduce(0) { $0 + $1.sizeBytes } }
    private var highestSafety: SafetyLevel { items.map(\.safety).max() ?? .safe }
    private var isPermanent: Bool { mode == .permanentDelete }
    private var confirmEnabled: Bool {
        !items.isEmpty && (!forcePermanent || isPermanent)
            && (!isPermanent || ((allowPermanent || forcePermanent) && acknowledgedPermanent))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            header

            // Removal mode
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                if forcePermanent {
                    Label(RemovalMode.permanentDelete.title, systemImage: "trash.slash.fill")
                        .font(.mcBodyMedium)
                        .foregroundStyle(AppColor.danger)
                } else {
                    Picker(tr("comp.confirm.removalMode"), selection: $mode) {
                        Text(RemovalMode.trash.title).tag(RemovalMode.trash)
                        if allowPermanent {
                            Text(RemovalMode.permanentDelete.title).tag(RemovalMode.permanentDelete)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }
                Text(mode.explanation)
                    .font(.mcCaption)
                    .foregroundStyle(.secondary)
            }

            if highestSafety >= .caution {
                InfoBanner(
                    kind: highestSafety == .risky ? .danger : .warning,
                    message: highestSafety == .risky
                        ? tr("comp.confirm.riskyBanner")
                        : tr("comp.confirm.cautionBanner")
                )
            }

            // Preview list
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text(tr("comp.confirm.itemsToDelete")).font(.subheadline.weight(.semibold))
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 6) {
                        ForEach(items) { item in
                            HStack(spacing: Theme.Spacing.sm) {
                                SafetyBadge(level: item.safety, compact: true)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(item.displayName).font(.caption).lineLimit(1)
                                    Text(item.path).font(.caption2).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                                }
                                Spacer()
                                Text(item.formattedSize).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
                .frame(height: 180)
                .background(
                    RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                        .fill(Color.secondary.opacity(0.06))
                )
            }

            if isPermanent {
                Toggle(isOn: $acknowledgedPermanent) {
                    Text(tr("comp.confirm.acknowledge"))
                        .font(.callout)
                }
                .toggleStyle(.checkbox)
            }

            footer
        }
        .padding(Theme.Spacing.xl)
        .frame(width: 560)
        .background(AppColor.background)
        .onAppear {
            if forcePermanent { mode = .permanentDelete }
            else if !allowPermanent { mode = .trash }
        }
        .onChange(of: mode) { oldMode, newMode in
            if oldMode == .permanentDelete && newMode != .permanentDelete {
                acknowledgedPermanent = false
            }
        }
    }

    private var header: some View {
        HStack(spacing: Theme.Spacing.md) {
            Image(systemName: isPermanent ? "trash.slash.fill" : "trash.fill")
                .font(.largeTitle)
                .foregroundStyle(isPermanent ? Theme.Palette.risky : Theme.Palette.accent)
            VStack(alignment: .leading, spacing: 2) {
                Text(tr("comp.confirm.title")).font(.title2.bold())
                Text(tr("comp.confirm.summary", items.count, ByteFormat.string(fromBytes: totalBytes)))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var footer: some View {
        HStack {
            Spacer()
            Button(tr("common.cancel"), role: .cancel, action: onCancel)
                .keyboardShortcut(.cancelAction)
            Button(isPermanent ? tr("comp.confirm.permanentDelete") : tr("common.moveToTrash"), role: isPermanent ? .destructive : nil, action: onConfirm)
                .keyboardShortcut(.defaultAction)
                .buttonStyle(PrimaryGradientButtonStyle(tint: isPermanent ? AppColor.danger : nil))
                .disabled(!confirmEnabled)
        }
    }
}
