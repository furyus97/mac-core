import SwiftUI
import AppKit

// MARK: - Model

/// One read-only check of a built-in macOS protection.
struct ProtectionCheck: Identifiable, Sendable, Hashable {
    enum State: String, Sendable, Hashable { case on, off, unknown }

    let id: String
    /// Localization key of the check's title.
    let titleKey: String
    /// Localized one-line explanation of the current state.
    let detail: String
    let state: State
    /// Contribution to the score; 0 = informational only.
    let weight: Int
    let settingsURL: URL?

    var title: String { tr(titleKey) }
    var isInformational: Bool { weight == 0 }
}

struct ProtectionReport: Sendable {
    /// 0...100 weighted share of `.on` among checks whose state is known.
    let score: Int
    let checks: [ProtectionCheck]
    var checkedAt = Date()

    /// Scored checks (weight > 0).
    var scoredChecks: [ProtectionCheck] { checks.filter { !$0.isInformational } }
    var onCount: Int { scoredChecks.filter { $0.state == .on }.count }
    var offCount: Int { scoredChecks.filter { $0.state == .off }.count }
    var knownCount: Int { scoredChecks.filter { $0.state != .unknown }.count }
    /// False when nothing could be read (score is meaningless).
    var hasKnownChecks: Bool { knownCount > 0 }
}

// MARK: - Service

enum ProtectionService {
    enum Settings {
        static let privacySecurity = URL(string: "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension")!
        static let fileVault = URL(string: "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?FileVault")!
        static let firewall = URL(string: "x-apple.systempreferences:com.apple.Network-Settings.extension?Firewall")!
        static let softwareUpdate = URL(string: "x-apple.systempreferences:com.apple.Software-Update-Settings.extension")!
        static let lockScreen = URL(string: "x-apple.systempreferences:com.apple.Lock-Screen-Settings.extension")!
    }

    static let xprotectInfoPlist = URL(fileURLWithPath: "/Library/Apple/System/Library/CoreServices/XProtect.bundle/Contents/Info.plist")

    /// Runs every check concurrently (read-only, no admin). Failures become `.unknown`.
    static func evaluate() async -> ProtectionReport {
        async let fileVault = CommandRunner.run("/usr/bin/fdesetup", ["status"])
        async let firewall = CommandRunner.run("/usr/libexec/ApplicationFirewall/socketfilterfw", ["--getglobalstate"])
        async let gatekeeper = CommandRunner.run("/usr/sbin/spctl", ["--status"])
        async let sip = CommandRunner.run("/usr/bin/csrutil", ["status"])
        async let screenLock = CommandRunner.run("/usr/sbin/sysadminctl", ["-screenLock", "status"])

        var checks: [ProtectionCheck] = [
            fileVaultCheck(parseFileVault(await fileVault)),
            firewallCheck(parseFirewall(await firewall)),
            gatekeeperCheck(parseGatekeeper(await gatekeeper)),
            sipCheck(parseSIP(await sip)),
            updatesCheck(updatesState(automaticCheck: softwareUpdateBool("AutomaticCheckEnabled"),
                                      automaticDownload: softwareUpdateBool("AutomaticDownload"),
                                      automaticallyInstallMacOS: softwareUpdateBool("AutomaticallyInstallMacOSUpdates"))),
        ]
        if let lock = parseScreenLock(await screenLock) {
            checks.append(screenLockCheck(lock))
        }
        checks.append(xprotectCheck(version: xprotectVersion()))
        return ProtectionReport(score: score(of: checks), checks: checks)
    }

    // MARK: Score

    /// Weighted share of `.on` among scored checks with a known state, 0...100.
    /// Returns 0 when no scored check is known.
    static func score(of checks: [ProtectionCheck]) -> Int {
        let known = checks.filter { $0.weight > 0 && $0.state != .unknown }
        let total = known.reduce(0) { $0 + $1.weight }
        guard total > 0 else { return 0 }
        let on = known.filter { $0.state == .on }.reduce(0) { $0 + $1.weight }
        return min(100, max(0, Int((Double(on) * 100 / Double(total)).rounded())))
    }

    // MARK: Parsers (pure, testable)

    private static func text(_ result: CommandRunner.Result?) -> String? {
        guard let result, !result.timedOut else { return nil }
        return result.output.lowercased()
    }

    static func parseFileVault(_ result: CommandRunner.Result?) -> ProtectionCheck.State {
        guard let out = text(result) else { return .unknown }
        if out.contains("filevault is on") { return .on }
        if out.contains("filevault is off") { return .off }
        return .unknown
    }

    static func parseFirewall(_ result: CommandRunner.Result?) -> ProtectionCheck.State {
        guard let out = text(result) else { return .unknown }
        if out.contains("state = 1") || out.contains("state = 2") || out.contains("is enabled") { return .on }
        if out.contains("state = 0") || out.contains("is disabled") { return .off }
        return .unknown
    }

    static func parseGatekeeper(_ result: CommandRunner.Result?) -> ProtectionCheck.State {
        guard let out = text(result) else { return .unknown }
        if out.contains("assessments enabled") { return .on }
        if out.contains("assessments disabled") { return .off }
        return .unknown
    }

    static func parseSIP(_ result: CommandRunner.Result?) -> ProtectionCheck.State {
        guard let out = text(result) else { return .unknown }
        // A custom configuration reports "unknown (Custom Configuration)" → unknown.
        if out.contains("status: enabled") { return .on }
        if out.contains("status: disabled") { return .off }
        return .unknown
    }

    /// nil = not readable (the check is skipped).
    static func parseScreenLock(_ result: CommandRunner.Result?) -> ProtectionCheck.State? {
        guard let out = text(result), result?.succeeded == true || out.contains("screenlock") else { return nil }
        if out.contains("screenlock is off") || out.contains("screenlock delay is off") || out.contains("disabled") { return .off }
        if out.contains("screenlock delay is") || out.contains("screenlock is on") { return .on }
        return nil
    }

    static func updatesState(automaticCheck: Bool?, automaticDownload: Bool?, automaticallyInstallMacOS: Bool?) -> ProtectionCheck.State {
        if let automaticCheck { return automaticCheck ? .on : .off }
        // Missing key = macOS default; only call it on when another auto-update
        // preference proves the updater is active.
        if automaticDownload == true || automaticallyInstallMacOS == true { return .on }
        return .unknown
    }

    private static func softwareUpdateBool(_ key: String) -> Bool? {
        let value = CFPreferencesCopyValue(key as CFString, "com.apple.SoftwareUpdate" as CFString,
                                           kCFPreferencesAnyUser, kCFPreferencesCurrentHost)
            ?? CFPreferencesCopyValue(key as CFString, "com.apple.SoftwareUpdate" as CFString,
                                      kCFPreferencesAnyUser, kCFPreferencesAnyHost)
        if let number = value as? NSNumber { return number.boolValue }
        if let string = value as? String { return ["1", "true", "yes"].contains(string.lowercased()) }
        return nil
    }

    static func xprotectVersion(at url: URL = xprotectInfoPlist) -> String? {
        guard let data = try? Data(contentsOf: url),
              let plist = (try? PropertyListSerialization.propertyList(from: data, options: [], format: nil)) as? [String: Any]
        else { return nil }
        return (plist["CFBundleShortVersionString"] as? String) ?? (plist["CFBundleVersion"] as? String)
    }

    // MARK: Check builders

    private static func detail(_ prefix: String, _ state: ProtectionCheck.State) -> String {
        switch state {
        case .on: return tr("\(prefix).on")
        case .off: return tr("\(prefix).off")
        case .unknown: return tr("protect.check.unknown")
        }
    }

    static func fileVaultCheck(_ state: ProtectionCheck.State) -> ProtectionCheck {
        ProtectionCheck(id: "filevault", titleKey: "protect.check.filevault.title",
                        detail: detail("protect.check.filevault", state), state: state, weight: 25, settingsURL: Settings.fileVault)
    }
    static func firewallCheck(_ state: ProtectionCheck.State) -> ProtectionCheck {
        ProtectionCheck(id: "firewall", titleKey: "protect.check.firewall.title",
                        detail: detail("protect.check.firewall", state), state: state, weight: 20, settingsURL: Settings.firewall)
    }
    static func gatekeeperCheck(_ state: ProtectionCheck.State) -> ProtectionCheck {
        ProtectionCheck(id: "gatekeeper", titleKey: "protect.check.gatekeeper.title",
                        detail: detail("protect.check.gatekeeper", state), state: state, weight: 20, settingsURL: Settings.privacySecurity)
    }
    static func sipCheck(_ state: ProtectionCheck.State) -> ProtectionCheck {
        ProtectionCheck(id: "sip", titleKey: "protect.check.sip.title",
                        detail: detail("protect.check.sip", state), state: state, weight: 20, settingsURL: nil)
    }
    static func updatesCheck(_ state: ProtectionCheck.State) -> ProtectionCheck {
        ProtectionCheck(id: "updates", titleKey: "protect.check.updates.title",
                        detail: detail("protect.check.updates", state), state: state, weight: 15, settingsURL: Settings.softwareUpdate)
    }
    static func screenLockCheck(_ state: ProtectionCheck.State) -> ProtectionCheck {
        ProtectionCheck(id: "screenlock", titleKey: "protect.check.screenlock.title",
                        detail: detail("protect.check.screenlock", state), state: state, weight: 10, settingsURL: Settings.lockScreen)
    }
    static func xprotectCheck(version: String?) -> ProtectionCheck {
        ProtectionCheck(id: "xprotect", titleKey: "protect.check.xprotect.title",
                        detail: version.map { tr("protect.check.xprotect.version", $0) } ?? tr("protect.check.unknown"),
                        state: version == nil ? .unknown : .on, weight: 0, settingsURL: nil)
    }
}

// MARK: - View model

@MainActor
final class ProtectionViewModel: ObservableObject {
    @Published private(set) var report: ProtectionReport?
    @Published private(set) var isLoading = false

    func refresh() async {
        guard !isLoading else { return }
        isLoading = true
        report = await ProtectionService.evaluate()
        isLoading = false
    }
}

// MARK: - View

struct ProtectionView: View {
    @StateObject private var vm = ProtectionViewModel()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                scoreCard
                checksSection
            }
            .padding(Theme.Spacing.outer)
        }
        .screenBackground()
        .navigationTitle(tr("nav.protection"))
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { Task { await vm.refresh() } } label: {
                    Label(tr("common.refresh"), systemImage: "arrow.clockwise")
                }
                .disabled(vm.isLoading)
            }
        }
        .task { if vm.report == nil { await vm.refresh() } }
    }

    // MARK: Score

    private var scoreCard: some View {
        HStack(alignment: .center, spacing: Theme.Spacing.xxl) {
            ScoreDial(score: vm.report?.hasKnownChecks == true ? vm.report?.score : nil, loading: vm.isLoading && vm.report == nil)
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                StatusEyebrow(text: tr("protect.eyebrow"), color: verdictColor)
                Text(verdict).font(.mcCardTitle)
                if let report = vm.report, report.hasKnownChecks {
                    Text(tr("protect.score.caption", report.onCount, report.scoredChecks.count))
                        .font(.mcBody)
                        .foregroundStyle(AppColor.secondaryText)
                }
                Label(tr("protect.note"), systemImage: "info.circle")
                    .font(.mcCaption)
                    .foregroundStyle(AppColor.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: Theme.Spacing.sm) {
                    Button {
                        Task { await vm.refresh() }
                    } label: {
                        Label(vm.isLoading ? tr("protect.checking") : tr("protect.recheck"), systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.primaryGradient)
                    .disabled(vm.isLoading)
                    if let report = vm.report {
                        Text(tr("protect.lastChecked", DateFormat.time(report.checkedAt)))
                            .font(.mcMono(11))
                            .foregroundStyle(AppColor.secondaryText)
                    }
                }
                .padding(.top, Theme.Spacing.xs)
            }
            Spacer(minLength: 0)
        }
        .card(elevated: true)
    }

    private var verdict: String {
        guard let report = vm.report else { return tr("protect.checking") }
        guard report.hasKnownChecks else { return tr("protect.verdict.unknown") }
        if report.offCount == 0 { return tr("protect.verdict.good") }
        return report.score >= 70 ? tr("protect.verdict.fair") : tr("protect.verdict.poor")
    }

    private var verdictColor: Color {
        guard let report = vm.report, report.hasKnownChecks else { return AppColor.secondaryText }
        return report.offCount == 0 ? AppColor.success : StatusColor.forScore(report.score)
    }

    // MARK: Checks

    @ViewBuilder
    private var checksSection: some View {
        if let report = vm.report {
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                SectionTitle(tr("protect.checks.title"))
                VStack(spacing: 0) {
                    ForEach(Array(report.checks.enumerated()), id: \.element.id) { index, check in
                        checkRow(check)
                        if index < report.checks.count - 1 { Divider().padding(.leading, 52) }
                    }
                }
                .card(padding: Theme.Spacing.md)
            }
        } else if vm.isLoading {
            VStack(spacing: Theme.Spacing.md) {
                ProgressView()
                Text(tr("protect.checking")).font(.mcBody).foregroundStyle(AppColor.secondaryText)
            }
            .frame(maxWidth: .infinity, minHeight: 200)
        }
    }

    private func icon(for check: ProtectionCheck) -> String {
        switch check.id {
        case "filevault": return "lock.doc.fill"
        case "firewall": return "flame.fill"
        case "gatekeeper": return "checkmark.seal.fill"
        case "sip": return "cpu.fill"
        case "updates": return "arrow.triangle.2.circlepath"
        case "screenlock": return "lock.display"
        case "xprotect": return "shield.lefthalf.filled"
        default: return "shield.fill"
        }
    }

    private func checkRow(_ check: ProtectionCheck) -> some View {
        HStack(spacing: Theme.Spacing.md) {
            if check.state == .off {
                IconTile(systemName: icon(for: check), tint: AppColor.danger, size: 36)
            } else if check.state == .unknown {
                IconTile(systemName: icon(for: check), tint: AppColor.secondaryText, size: 36)
            } else {
                IconTile(systemName: icon(for: check), size: 36, colors: TileColor.protection)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(check.title).font(.mcBodyMedium)
                Text(check.detail)
                    .font(.mcCaption)
                    .foregroundStyle(AppColor.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: Theme.Spacing.sm)
            StateChip(state: check.state, informational: check.isInformational)
            if let url = check.settingsURL {
                Button(tr("protect.openSettings")) { NSWorkspace.shared.open(url) }
                    .buttonStyle(.softCapsule)
                    .frame(minWidth: 120, alignment: .trailing)
            } else {
                Color.clear.frame(width: 120, height: 1)
            }
        }
        .padding(.vertical, Theme.Spacing.sm)
        .padding(.horizontal, Theme.Spacing.xs)
    }
}

/// Green on / red off / gray unknown pill.
private struct StateChip: View {
    let state: ProtectionCheck.State
    var informational = false

    private var color: Color {
        if informational { return state == .unknown ? AppColor.secondaryText : AppColor.primary }
        switch state {
        case .on: return AppColor.success
        case .off: return AppColor.danger
        case .unknown: return AppColor.secondaryText
        }
    }

    private var text: String {
        if informational && state == .on { return tr("protect.state.info") }
        switch state {
        case .on: return tr("protect.state.on")
        case .off: return tr("protect.state.off")
        case .unknown: return tr("protect.state.unknown")
        }
    }

    var body: some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(text).font(.mcMicro)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .foregroundStyle(color)
        .background(Capsule().fill(color.opacity(0.14)))
        .frame(minWidth: 70)
    }
}

/// Large score ring in the brand gradient.
private struct ScoreDial: View {
    let score: Int?
    var loading = false
    var size: CGFloat = 168
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var fraction: Double { Double(score ?? 0) / 100 }

    var body: some View {
        ZStack {
            Circle().stroke(AppColor.primary.opacity(0.10), lineWidth: 14)
            Circle()
                .trim(from: 0, to: fraction)
                .stroke(AngularGradient(colors: [Color(hex: "4F46E5"), Color(hex: "8B5CF6"), Color(hex: "E26BB4"), Color(hex: "4F46E5")],
                                        center: .center),
                        style: StrokeStyle(lineWidth: 14, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(reduceMotion ? nil : .spring(response: 0.8, dampingFraction: 0.85), value: fraction)
            VStack(spacing: 0) {
                if loading {
                    ProgressView()
                } else {
                    Text(score.map(String.init) ?? "–")
                        .font(.mcHero(56))
                        .foregroundStyle(AppGradient.brand)
                        .contentTransition(.numericText())
                    Text(tr("protect.score.label"))
                        .font(.mcMicro)
                        .foregroundStyle(AppColor.secondaryText)
                }
            }
        }
        .frame(width: size, height: size)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(tr("protect.score.label"))
        .accessibilityValue(score.map(String.init) ?? tr("protect.state.unknown"))
    }
}

#Preview {
    ProtectionView().frame(width: 1024, height: 800)
}
