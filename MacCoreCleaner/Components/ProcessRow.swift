import SwiftUI

/// A single process row for the CPU / Memory monitors. Highlights the relevant
/// metric and offers a confirm-gated terminate action.
struct ProcessRow: View {
    enum Metric { case cpu, memory }

    let process: ProcessSample
    var metric: Metric = .cpu
    var isAbnormal: Bool = false
    var onTerminate: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: Theme.Spacing.md) {
            Image(systemName: isAbnormal ? "exclamationmark.triangle.fill" : "app.dashed")
                .foregroundStyle(isAbnormal ? Theme.Palette.caution : .secondary)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 1) {
                Text(process.name)
                    .font(.callout)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text("PID \(process.pid)\(process.isOwnedByCurrentUser ? "" : tr("comp.procRow.systemTag"))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 1) {
                Text(ByteFormat.processPercent(process.cpuPercent))
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(metric == .cpu ? .primary : .secondary)
                Text(process.formattedMemory)
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(metric == .memory ? .primary : .secondary)
            }
            .frame(width: 90, alignment: .trailing)

            if let onTerminate, process.canRequestTermination {
                Button(role: .destructive, action: onTerminate) {
                    Image(systemName: "stop.circle")
                }
                .buttonStyle(.borderless)
                .help(tr("comp.procRow.terminateHelp"))
                .accessibilityLabel(tr("comp.procRow.terminateLabel", process.name))
            }
        }
        .padding(.vertical, 4)
    }
}
