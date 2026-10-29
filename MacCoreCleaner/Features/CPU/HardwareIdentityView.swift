import SwiftUI
import Darwin

struct HardwareIdentityView: View {
    private let processor: String = {
        var size = 0
        guard sysctlbyname("machdep.cpu.brand_string", nil, &size, nil, 0) == 0, size > 0 else { return "—" }
        var bytes = [CChar](repeating: 0, count: size)
        guard sysctlbyname("machdep.cpu.brand_string", &bytes, &size, nil, 0) == 0 else { return "—" }
        return String(cString: bytes)
    }()
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            TelemetryRow(title: tr("hardware.processor"), value: processor)
            TelemetryRow(title: tr("hardware.os"), value: ProcessInfo.processInfo.operatingSystemVersionString)
            TelemetryRow(title: tr("hardware.uptime"), value: tr("detail.minutes", Int(ProcessInfo.processInfo.systemUptime / 60)))
            TelemetryRow(title: tr("hardware.thermal"), value: thermalState)
        }.card()
    }
    private var thermalState: String {
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: return tr("thermal.nominal")
        case .fair: return tr("thermal.fair")
        case .serious: return tr("thermal.serious")
        case .critical: return tr("thermal.critical")
        @unknown default: return "—"
        }
    }
}
