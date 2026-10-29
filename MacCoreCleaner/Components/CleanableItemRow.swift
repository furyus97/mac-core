import SwiftUI

/// One selectable file/folder row: checkbox, name, path, dates, size, safety
/// badge and a "Finder에서 보기" action. Selection is two-way bound so parent
/// totals update live.
struct CleanableItemRow: View {
    @Binding var item: CleanableItem

    var body: some View {
        HStack(spacing: Theme.Spacing.md) {
            Toggle(isOn: $item.isSelected) {
                EmptyView()
            }
            .toggleStyle(.checkbox)
            .labelsHidden()
            .accessibilityLabel(item.displayName)

            Image(systemName: item.isDirectory ? "folder.fill" : "doc.fill")
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.displayName)
                    .font(.callout)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(item.path)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(item.path)
                if let detail = item.detail {
                    Text(detail)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { item.isSelected.toggle() }

            Spacer(minLength: Theme.Spacing.sm)

            VStack(alignment: .trailing, spacing: 2) {
                Text(item.formattedSize)
                    .font(.callout.monospacedDigit())
                Text(tr("comp.itemRow.modified", DateFormat.relativeString(item.modifiedDate)))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(width: 120, alignment: .trailing)

            SafetyBadge(level: item.safety, compact: true)

            Button {
                FinderHelper.reveal(item.url)
            } label: {
                Image(systemName: "magnifyingglass")
            }
            .buttonStyle(.borderless)
            .help(tr("common.showInFinder"))
            .accessibilityLabel(tr("common.showInFinder"))
        }
        .padding(.vertical, 4)
    }
}
