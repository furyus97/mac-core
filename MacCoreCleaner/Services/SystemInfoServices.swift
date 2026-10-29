import Foundation
import IOKit
import IOKit.ps
import SystemConfiguration

protocol BatteryMonitoring: Sendable {
    func sample() -> BatterySnapshot
}

protocol NetworkMonitoring {
    /// Throughput since the previous call (keeps internal state for deltas).
    func sample() -> NetworkSnapshot
}

/// Reads the internal battery via IOKit power sources + AppleSmartBattery registry.
/// Returns `.none` on desktops (no internal battery).
final class BatteryService: BatteryMonitoring {
    func sample() -> BatterySnapshot {
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef]
        else { return .none }

        for source in sources {
            guard let desc = IOPSGetPowerSourceDescription(blob, source)?.takeUnretainedValue() as? [String: Any],
                  (desc[kIOPSTypeKey] as? String) == kIOPSInternalBatteryType
            else { continue }

            let current = desc[kIOPSCurrentCapacityKey] as? Int ?? 0
            let maxCap = desc[kIOPSMaxCapacityKey] as? Int ?? 100
            let pct = maxCap > 0 ? Int((Double(current) / Double(maxCap)) * 100.0) : current
            let state = desc[kIOPSPowerSourceStateKey] as? String
            let pluggedIn = state == kIOPSACPowerValue
            let charging = desc[kIOPSIsChargingKey] as? Bool ?? false
            let tte = desc[kIOPSTimeToEmptyKey] as? Int

            let properties = Self.registryProperties()
            let adapter = IOPSCopyExternalPowerAdapterDetails()?.takeRetainedValue() as? [String: Any] ?? [:]
            let health = desc[kIOPSBatteryHealthConditionKey] as? String ?? desc[kIOPSBatteryHealthKey] as? String
            var electrical = BatteryElectrical.parse(properties, adapter: adapter, pluggedIn: pluggedIn)
            if electrical.temperature == nil { electrical.temperature = TemperatureService().sample().battery }

            return BatterySnapshot(
                isPresent: true,
                percentage: min(max(pct, 0), 100),
                isCharging: charging,
                isPluggedIn: pluggedIn,
                cycleCount: properties["CycleCount"] as? Int,
                health: health,
                timeToEmptyMinutes: !pluggedIn ? BatteryElectrical.validMinutes(tte) : nil,
                timeToFullMinutes: charging ? BatteryElectrical.validMinutes(desc[kIOPSTimeToFullChargeKey] as? Int) : nil,
                electrical: electrical
            )
        }
        return .none
    }

    /// Read-only, best-effort. No identifiers are persisted or transmitted.
    static func registryProperties() -> [String: Any] {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard service != 0 else { return [:] }
        defer { IOObjectRelease(service) }

        var unmanaged: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(service, &unmanaged, kCFAllocatorDefault, 0) == KERN_SUCCESS,
              let props = unmanaged?.takeRetainedValue() as? [String: Any]
        else { return [:] }
        return props
    }
}

/// Sums 64-bit non-loopback interface counters and derives a rate
/// from the delta between samples.
final class NetworkService: NetworkMonitoring {
    private var previous: [String: NetworkInterfaceSnapshot] = [:]
    private var prevTime: TimeInterval?

    func resetBaseline() {
        previous = [:]
        prevTime = nil
    }

    func sample() -> NetworkSnapshot {
        var interfaces = counters()
        let now = ProcessInfo.processInfo.systemUptime
        if let prevTime, now - prevTime > 0.01 {
            for i in interfaces.indices {
                guard let old = previous[interfaces[i].id] else { continue }
                interfaces[i].downBytesPerSec = max(0, Double(interfaces[i].receivedBytes - old.receivedBytes) / (now - prevTime))
                interfaces[i].upBytesPerSec = max(0, Double(interfaces[i].sentBytes - old.sentBytes) / (now - prevTime))
            }
        }
        previous = Dictionary(uniqueKeysWithValues: interfaces.map { ($0.id, $0) })
        prevTime = now
        return NetworkSnapshot(
            downBytesPerSec: interfaces.reduce(0) { $0 + $1.downBytesPerSec },
            upBytesPerSec: interfaces.reduce(0) { $0 + $1.upBytesPerSec },
            totalDownBytes: interfaces.reduce(0) { $0 + $1.receivedBytes },
            totalUpBytes: interfaces.reduce(0) { $0 + $1.sentBytes },
            primaryInterface: primaryInterface() ?? "—",
            interfaces: interfaces.sorted { $0.id < $1.id }
        )
    }

    private func counters() -> [NetworkInterfaceSnapshot] {
        // getifaddrs exposes the older 32-bit if_data counters, which wrap
        // around after 4 GiB. NET_RT_IFLIST2 provides the 64-bit counters.
        var mib: [Int32] = [CTL_NET, PF_ROUTE, 0, 0, NET_RT_IFLIST2, 0]
        for _ in 0..<3 {
            var size = 0
            guard sysctl(&mib, u_int(mib.count), nil, &size, nil, 0) == 0,
                  size > 0, size < 16_777_216 else { return [] }
            var data = Data(count: size)
            let result = data.withUnsafeMutableBytes { buffer in
                sysctl(&mib, u_int(mib.count), buffer.baseAddress, &size, nil, 0)
            }
            if result == 0 {
                data.count = size
                return Self.decodeInterfaceCounters(data) { index in
                    var name = [CChar](repeating: 0, count: Int(IFNAMSIZ))
                    guard if_indextoname(index, &name) != nil else { return nil }
                    return String(cString: name)
                }
            }
            if errno != ENOMEM { return [] } // interface list grew between calls
        }
        return []
    }

    static func decodeInterfaceCounters(_ data: Data, nameForIndex: (UInt32) -> String?) -> [NetworkInterfaceSnapshot] {
        data.withUnsafeBytes { buffer in
            var offset = 0
            var interfaces: [String: NetworkInterfaceSnapshot] = [:]
            while offset + 4 <= buffer.count {
                let length = Int(buffer.loadUnaligned(fromByteOffset: offset, as: UInt16.self))
                guard length >= 4, length <= buffer.count - offset else { break }
                defer { offset += length }
                guard length >= MemoryLayout<if_msghdr2>.size else { continue }
                let message = buffer.loadUnaligned(fromByteOffset: offset, as: if_msghdr2.self)
                guard message.ifm_type == UInt8(RTM_IFINFO2),
                      message.ifm_flags & IFF_UP != 0, message.ifm_flags & IFF_LOOPBACK == 0,
                      let name = nameForIndex(UInt32(message.ifm_index)) else { continue }
                interfaces[name] = .init(id: name,
                    receivedBytes: Int64(clamping: message.ifm_data.ifi_ibytes),
                    sentBytes: Int64(clamping: message.ifm_data.ifi_obytes))
            }
            return interfaces.values.sorted { $0.id < $1.id }
        }
    }

    private func primaryInterface() -> String? {
        for family in ["IPv4", "IPv6"] {
            let key = "State:/Network/Global/\(family)" as CFString
            if let state = SCDynamicStoreCopyValue(nil, key) as? [String: Any],
               let name = state["PrimaryInterface"] as? String { return name }
        }
        return nil
    }
}
