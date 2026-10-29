import SwiftUI

/// App preferences screen. Uses a native grouped `Form` so it reads like a
/// standard macOS settings pane. Reads and writes `SettingsStore` directly via
/// the environment, and surfaces folder-permission status from `PermissionManager`.
struct SettingsView: View {

    @EnvironmentObject var settings: SettingsStore
    @EnvironmentObject var permissions: PermissionManager
    @EnvironmentObject var localization: LocalizationManager

    var body: some View {
        Form {
            Section(tr("set.langSection")) {
                Picker(tr("set.language"), selection: $localization.language) {
                    ForEach(AppLanguage.allCases) { language in
                        Text(language.displayName).tag(language)
                    }
                }
                .pickerStyle(.menu)
            }

            Section(tr("set.displaySection")) {
                Picker(tr("set.appearance"), selection: $settings.appearance) {
                    ForEach(AppearanceMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
            }

            MenuBarPreferences(settings: settings)

            Section(tr("set.tempSection")) {
                Picker(tr("set.tempSource"), selection: $settings.temperatureSource) {
                    ForEach(TemperatureSource.allCases) { source in
                        Text(tr(source.titleKey)).tag(source)
                    }
                }
                Text(tr("set.tempSourceCaption"))
                    .font(.mcCaption)
                    .foregroundStyle(AppColor.secondaryText)
            }

            Section(tr("set.scanSection")) {
                Toggle(tr("set.autoScanOnLaunch"), isOn: $settings.autoScanOnLaunch)

                Stepper(
                    value: $settings.downloadsThresholdMB,
                    in: 10...5000,
                    step: 10
                ) {
                    Text(tr("set.largeFileThreshold", settings.downloadsThresholdMB))
                }

            }

            Section(tr("set.deletionSafetySection")) {
                Label(tr("set.alwaysConfirm"), systemImage: "checkmark.shield.fill")
                    .foregroundStyle(AppColor.success)

                Picker(tr("set.defaultRemovalMode"), selection: $settings.removalMode) {
                    Text(RemovalMode.trash.title).tag(RemovalMode.trash)
                    if settings.advancedMode {
                        Text(RemovalMode.permanentDelete.title).tag(RemovalMode.permanentDelete)
                    }
                }

                Toggle(tr("set.showRiskyItems"), isOn: $settings.showRiskyItems)

                Toggle(tr("set.advancedMode"), isOn: $settings.advancedMode)
                    .onChange(of: settings.advancedMode) { _, enabled in
                        if !enabled { settings.removalMode = .trash }
                    }

                Text(tr("set.advancedModeCaption"))
                    .font(.mcCaption)
                    .foregroundStyle(AppColor.secondaryText)
            }

            Section(tr("set.folderPermissionsSection")) {
                permissionRow(tr("set.downloads"), permissions.downloads)
                permissionRow(tr("set.desktop"), permissions.desktop)
                permissionRow(tr("set.documents"), permissions.documents)

                HStack(spacing: Theme.Spacing.md) {
                    Button(tr("set.openPermissionSettings")) {
                        permissions.openPrivacySettings()
                    }
                    Button(tr("common.refresh")) {
                        permissions.refresh()
                    }
                }
            }

            Section(tr("set.safetyPolicySection")) {
                Label(tr("set.policyNoUnauthorizedDeletion"), systemImage: "checkmark.shield.fill")
                Label(tr("set.policyExcludeSystemFolders"), systemImage: "lock.shield.fill")
                Label(tr("set.policyTrashByDefault"), systemImage: "trash.fill")
                Label(tr("set.policyAllowedLocationsOnly"), systemImage: "folder.fill.badge.gearshape")

                LabeledContent(tr("set.version"), value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")
                LabeledContent(tr("set.app"), value: "Mac Core")
            }
        }
        .formStyle(.grouped)
        .navigationTitle(tr("nav.settings"))
    }

    // MARK: - 폴더 권한 행

    private func permissionRow(_ name: String, _ access: PermissionManager.Access) -> some View {
        LabeledContent(name) {
            Text(accessLabel(for: access))
                .font(.mcBodyMedium)
                .foregroundStyle(accessTint(for: access))
        }
    }

    private func accessLabel(for access: PermissionManager.Access) -> String {
        switch access {
        case .granted: return tr("set.accessGranted")
        case .denied: return tr("set.accessDenied")
        case .unknown: return tr("set.accessUnknown")
        }
    }

    private func accessTint(for access: PermissionManager.Access) -> Color {
        switch access {
        case .granted: return AppColor.success
        case .denied: return AppColor.danger
        case .unknown: return AppColor.secondaryText
        }
    }
}

#Preview {
    SettingsView()
        .environmentObject(AppServices.shared.settings)
        .environmentObject(AppServices.shared.permissions)
        .environmentObject(LocalizationManager.shared)
        .frame(width: 700, height: 800)
}
