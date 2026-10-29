import SwiftUI

struct MenuBarPreferences: View {
    @ObservedObject var settings: SettingsStore
    @State private var sensors: [TemperatureReading] = []
    @State private var optionsExpanded: Bool

    init(settings: SettingsStore, initiallyExpanded: Bool = false) {
        self.settings = settings
        _optionsExpanded = State(initialValue: initiallyExpanded)
    }

    var body: some View {
        Section(tr("set.monitorSection")) {
            Toggle(tr("set.showMenuBarMonitor"), isOn: $settings.menuBarMonitor)

            VStack(alignment: .leading, spacing: 8) {
                Text(tr("menubar.preview")).font(.mcCaption).foregroundStyle(AppColor.secondaryText)
                ScrollView(.horizontal, showsIndicators: false) {
                    Text(MenuBarTitleFormatter.title(snapshot: MenuBarTitleFormatter.example, settings: settings))
                        .font(.system(size: settings.menuBarFontSize, weight: .medium, design: .monospaced))
                        .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                }.background(AppColor.background, in: RoundedRectangle(cornerRadius: 6))
            }

            Picker(tr("menubar.displayStyle"), selection: $settings.menuBarDisplayStyle) {
                ForEach(MenuBarDisplayStyle.allCases) { style in
                    Text(style.title).tag(style)
                }
            }
            .pickerStyle(.segmented)

            Picker(tr("menubar.refreshRate"), selection: $settings.menuBarRefreshRate) {
                ForEach(MenuBarRefreshRate.allCases) { rate in
                    Text(rate.title).tag(rate)
                }
            }
            .pickerStyle(.segmented)

            Toggle(tr("menubar.showIcon"), isOn: $settings.menuBarShowIcon)

            DisclosureGroup(tr("menubar.formats"), isExpanded: $optionsExpanded) {
                Toggle(tr("menubar.memoryBytes"), isOn: $settings.menuBarMemoryBytes)
                Toggle(tr("menubar.diskPercent"), isOn: $settings.menuBarDiskPercent)
                Toggle(tr("menubar.fahrenheit"), isOn: $settings.menuBarFahrenheit)
                Toggle(tr("menubar.separators"), isOn: $settings.menuBarSeparators)
                Toggle(tr("menubar.expanded"), isOn: $settings.menuBarExpandedDetails)
                Picker(tr("menubar.fontSize"), selection: $settings.menuBarFontSize) {
                    ForEach([11.0, 12.0, 13.0], id: \.self) { size in Text("\(Int(size)) pt").tag(size) }
                }
                Picker(tr("menubar.sensor"), selection: $settings.menuBarSensorID) {
                    Text(tr("menubar.sourceDefault")).tag("")
                    ForEach(sensors.filter(\.canPin)) { sensor in Text(sensor.displayName).tag(sensor.id) }
                    if !settings.menuBarSensorID.isEmpty, !sensors.contains(where: { $0.canPin && $0.id == settings.menuBarSensorID }) {
                        Text(tr("menubar.sensorMissing")).tag(settings.menuBarSensorID)
                    }
                }
                Button(tr("common.refresh")) { Task { await refreshSensors() } }
                Text(tr("menubar.sensorNote")).font(.mcCaption).foregroundStyle(AppColor.secondaryText)
            }

            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                HStack {
                    Text(tr("menubar.visibleMetrics"))
                        .font(.mcBodyMedium)
                    Spacer()
                    Text(tr(
                        "menubar.metricCount",
                        settings.menuBarMetrics.count,
                        SettingsStore.maxMenuBarMetrics
                    ))
                    .font(.mcCaption.monospacedDigit())
                    .foregroundStyle(AppColor.secondaryText)
                }

                ForEach(Array(settings.menuBarMetrics.enumerated()), id: \.element) { index, metric in
                    HStack(spacing: Theme.Spacing.sm) {
                        Label(metric.title, systemImage: metric.systemImage)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        Button {
                            settings.moveMenuBarMetric(metric, offset: -1)
                        } label: {
                            Image(systemName: "chevron.up")
                        }
                        .buttonStyle(.borderless)
                        .disabled(index == settings.menuBarMetrics.startIndex)
                        .help(tr("menubar.moveUp"))

                        Button {
                            settings.moveMenuBarMetric(metric, offset: 1)
                        } label: {
                            Image(systemName: "chevron.down")
                        }
                        .buttonStyle(.borderless)
                        .disabled(index == settings.menuBarMetrics.index(before: settings.menuBarMetrics.endIndex))
                        .help(tr("menubar.moveDown"))

                        Button {
                            settings.setMenuBarMetric(metric, isEnabled: false)
                        } label: {
                            Image(systemName: "minus.circle")
                        }
                        .buttonStyle(.borderless)
                        .foregroundStyle(AppColor.danger)
                        .disabled(settings.menuBarMetrics.count == 1)
                        .help(tr("menubar.removeMetric"))
                    }
                    .padding(.vertical, 2)
                }

                Menu {
                    ForEach(settings.availableMenuBarMetrics) { metric in
                        Button {
                            settings.setMenuBarMetric(metric, isEnabled: true)
                        } label: {
                            Label(metric.title, systemImage: metric.systemImage)
                        }
                    }
                } label: {
                    Label(tr("menubar.addMetric"), systemImage: "plus.circle")
                }
                .disabled(
                    settings.menuBarMetrics.count >= SettingsStore.maxMenuBarMetrics
                        || settings.availableMenuBarMetrics.isEmpty
                )
            }

            Text(tr("set.menuBarCaption"))
                .font(.mcCaption)
                .foregroundStyle(AppColor.secondaryText)
        }
        .task { await refreshSensors() }
    }

    private func refreshSensors() async {
        let result = await Task.detached(priority: .utility) { TemperatureService().sample().readings }.value
        guard !Task.isCancelled else { return }
        sensors = result
    }
}
