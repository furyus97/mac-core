import SwiftUI

/// A native macOS `Table` of processes (Activity-Monitor style). Used by the
/// Memory and CPU screens. Columns are fixed for a stable, native layout;
/// callers pre-sort `processes` for the relevant metric.
struct ProcessTable: View {
    let processes: [ProcessSample]
    var height: CGFloat = 320
    var onTerminate: ((ProcessSample) -> Void)? = nil

    var body: some View {
        Table(processes) {
            TableColumn(tr("comp.procTable.process")) { p in
                HStack(spacing: Theme.Spacing.sm) {
                    Image(systemName: "app.dashed")
                        .foregroundStyle(AppColor.secondaryText)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(p.name).lineLimit(1).truncationMode(.middle)
                        Text("PID \(p.pid)\(p.isOwnedByCurrentUser ? "" : tr("comp.procRow.systemTag"))")
                            .font(.mcMicro)
                            .foregroundStyle(AppColor.secondaryText)
                    }
                }
            }
            .width(min: 180, ideal: 240)

            TableColumn("CPU") { p in
                Text(ByteFormat.processPercent(p.cpuPercent))
                    .monospacedDigit()
                    .foregroundStyle(p.cpuPercent > 80 ? AppColor.danger : AppColor.primaryText)
            }
            .width(min: 60, ideal: 70)

            TableColumn(tr("comp.procTable.memory")) { p in
                Text(p.formattedMemory).monospacedDigit()
            }
            .width(min: 70, ideal: 90)

            TableColumn(tr("comp.procTable.threads")) { p in
                Text(p.threadCount > 0 ? "\(p.threadCount)" : "—")
                    .monospacedDigit()
                    .foregroundStyle(AppColor.secondaryText)
            }
            .width(min: 50, ideal: 60)

            TableColumn("") { p in
                if let onTerminate, p.canRequestTermination {
                    Button(role: .destructive) { onTerminate(p) } label: {
                        Image(systemName: "xmark.circle")
                    }
                    .buttonStyle(.borderless)
                    .help(tr("comp.procTable.terminateHelp", p.name))
                    .accessibilityLabel(tr("comp.procTable.terminateLabel", p.name))
                }
            }
            .width(40)
        }
        .tableStyle(.inset)
        .frame(height: height)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous))
    }
}
