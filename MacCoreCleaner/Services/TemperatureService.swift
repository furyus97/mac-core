import Foundation
import IOKit
import Darwin

protocol TemperatureMonitoring: Sendable {
    func sample() -> TemperatureSnapshot
}

/// Reads hardware temperature sensors on Apple Silicon (and Intel) via the
/// IOKit HID event system. Those functions are not in the public SDK headers, so
/// they are resolved at runtime with `dlsym` (no bridging header needed). If the
/// API is unavailable, every read degrades gracefully to `nil`/`.none` — we never
/// fabricate a value.
final class TemperatureService: TemperatureMonitoring {

    // Private IOKit HID function signatures.
    private typealias CreateClient = @convention(c) (CFAllocator?) -> Unmanaged<CFTypeRef>?
    private typealias SetMatching  = @convention(c) (CFTypeRef, CFDictionary) -> Void
    private typealias CopyServices = @convention(c) (CFTypeRef) -> Unmanaged<CFArray>?
    private typealias CopyEvent    = @convention(c) (CFTypeRef, Int64, Int32, Int64) -> Unmanaged<CFTypeRef>?
    private typealias CopyProperty = @convention(c) (CFTypeRef, CFString) -> Unmanaged<CFTypeRef>?
    private typealias GetFloat     = @convention(c) (CFTypeRef, Int32) -> Double
    private typealias GetRegistryID = @convention(c) (CFTypeRef) -> Unmanaged<CFTypeRef>?

    private let createClient: CreateClient?
    private let setMatching: SetMatching?
    private let copyServices: CopyServices?
    private let copyEvent: CopyEvent?
    private let copyProperty: CopyProperty?
    private let getFloat: GetFloat?
    private let getRegistryID: GetRegistryID?
    private static let sessionID = UUID().uuidString

    // kIOHIDEventTypeTemperature = 15; field = type << 16.
    private let temperatureType: Int64 = 15
    private let temperatureField: Int32 = 15 << 16

    init() {
        let handle = dlopen(nil, RTLD_NOW)
        func sym<T>(_ name: String, _ type: T.Type) -> T? {
            guard let p = dlsym(handle, name) else { return nil }
            return unsafeBitCast(p, to: T.self)
        }
        createClient = sym("IOHIDEventSystemClientCreate", CreateClient.self)
        setMatching = sym("IOHIDEventSystemClientSetMatching", SetMatching.self)
        copyServices = sym("IOHIDEventSystemClientCopyServices", CopyServices.self)
        copyEvent = sym("IOHIDServiceClientCopyEvent", CopyEvent.self)
        copyProperty = sym("IOHIDServiceClientCopyProperty", CopyProperty.self)
        getFloat = sym("IOHIDEventGetFloatValue", GetFloat.self)
        getRegistryID = sym("IOHIDServiceClientGetRegistryID", GetRegistryID.self)
    }

    func sample() -> TemperatureSnapshot {
        var readings = readSensors().filter { $0.celsius > 0 && $0.celsius < 130 }
        let battery = readBatteryTemp() ?? readings.first(where: { $0.name.localizedCaseInsensitiveContains("battery") })?.celsius
        if let battery, !readings.contains(where: { $0.name.localizedCaseInsensitiveContains("battery") }) {
            readings.append(TemperatureReading(name: "AppleSmartBattery", celsius: battery, sensorID: "battery:temperature"))
        }

        let values = readings.map(\.celsius).filter { $0 > 0 && $0 < 130 }
        let avg = values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)
        let mx = values.max()

        let cpuVals = readings.filter { isCPU($0.name) }.map(\.celsius).filter { $0 > 0 && $0 < 130 }
        let gpuVals = readings.filter { isGPU($0.name) }.map(\.celsius).filter { $0 > 0 && $0 < 130 }
        let cpu = cpuVals.isEmpty ? nil : cpuVals.reduce(0, +) / Double(cpuVals.count)
        let gpu = gpuVals.isEmpty ? nil : gpuVals.reduce(0, +) / Double(gpuVals.count)

        return TemperatureSnapshot(
            cpu: cpu, gpu: gpu, battery: battery,
            average: avg, maxValue: mx, sensorCount: values.count,
            readings: readings.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        )
    }

    // MARK: Sensor name heuristics (Apple Silicon sensor naming is cryptic)

    private func isCPU(_ name: String) -> Bool {
        let u = name.uppercased()
        return u.hasPrefix("TP") || u.hasPrefix("TC") || u.hasPrefix("TE") || u.contains("CPU") || u.contains("SOC")
    }
    private func isGPU(_ name: String) -> Bool {
        let u = name.uppercased()
        return u.hasPrefix("TG") || u.contains("GPU")
    }

    // MARK: IOHID temperature sensors

    private func readSensors() -> [TemperatureReading] {
        guard let createClient, let setMatching, let copyServices, let copyEvent, let getFloat,
              let clientRef = createClient(kCFAllocatorDefault)
        else { return [] }
        let client = clientRef.takeRetainedValue()

        let matching = ["PrimaryUsagePage": 0xff00, "PrimaryUsage": 0x0005] as CFDictionary
        setMatching(client, matching)

        guard let servicesRef = copyServices(client) else { return [] }
        let services = servicesRef.takeRetainedValue()
        let count = CFArrayGetCount(services)

        var out: [TemperatureReading] = []
        var occurrences: [String: Int] = [:]
        out.reserveCapacity(count)
        for i in 0..<count {
            guard let raw = CFArrayGetValueAtIndex(services, i) else { continue }
            let svc = unsafeBitCast(raw, to: CFTypeRef.self)
            var name = "HID \(i + 1)"
            if let copyProperty, let nameRef = copyProperty(svc, "Product" as CFString),
               let s = nameRef.takeRetainedValue() as? String {
                name = s
            }
            guard let eventRef = copyEvent(svc, temperatureType, 0, 0) else { continue }
            let event = eventRef.takeRetainedValue()
            let temp = getFloat(event, temperatureField)
            if temp.isFinite && temp > 0 && temp < 130 {
                let occurrence = occurrences[name, default: 0]
                occurrences[name] = occurrence + 1
                let registryID = getRegistryID?(svc)?.takeUnretainedValue() as? NSNumber
                let path = registryID.flatMap { registryPath($0.uint64Value) }
                let identity = Self.sensorIdentity(name: name, path: path,
                    fallback: registryID?.stringValue ?? String(occurrence), session: Self.sessionID)
                out.append(TemperatureReading(name: name, celsius: temp, sensorID: identity))
            }
        }
        // Some systems expose the same registry service more than once.
        out = Dictionary(grouping: out, by: \.id).compactMap { $0.value.first }.sorted { $0.id < $1.id }
        let counts = Dictionary(grouping: out, by: \.name).mapValues(\.count)
        var indices: [String: Int] = [:]
        return out.map { reading in
            var value = reading
            if counts[reading.name, default: 0] > 1 {
                indices[reading.name, default: 0] += 1
                value.channel = indices[reading.name]
            }
            return value
        }
    }

    // MARK: Battery temperature (AppleSmartBattery)

    static func sensorIdentity(name: String, path: String?, fallback: String, session: String) -> String {
        if let path, !path.isEmpty { return "hid:path:\(name):\(path)" }
        // Without a hardware path, don't risk pinning a different channel after
        // relaunch or a change in discovery order. This ID is session-scoped.
        return "hid:session:\(session):\(name):\(fallback)"
    }

    private func registryPath(_ registryID: UInt64) -> String? {
        let entry = IOServiceGetMatchingService(kIOMainPortDefault, IORegistryEntryIDMatching(registryID))
        guard entry != 0 else { return nil }
        defer { IOObjectRelease(entry) }
        var path = [CChar](repeating: 0, count: 512)
        guard IORegistryEntryGetPath(entry, kIOServicePlane, &path) == KERN_SUCCESS else { return nil }
        return String(cString: path)
    }

    private func readBatteryTemp() -> Double? {
        BatteryElectrical.temperatureCelsius(BatteryService.registryProperties()["Temperature"])
    }
}
