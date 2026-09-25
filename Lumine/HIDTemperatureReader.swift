import CoreFoundation
import Darwin
import Foundation

/// Reads Apple Silicon temperature services without requiring a privileged helper.
/// These IOKit symbols are private, so resolve them at runtime and fall back to SMC.
final class HIDTemperatureReader {
    private typealias Create = @convention(c) (UnsafeRawPointer?) -> UnsafeMutableRawPointer?
    private typealias SetMatching = @convention(c) (UnsafeMutableRawPointer?, UnsafeRawPointer?) -> Void
    private typealias CopyServices = @convention(c) (UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer?
    private typealias CopyProperty = @convention(c) (UnsafeRawPointer?, UnsafeRawPointer?) -> UnsafeMutableRawPointer?
    private typealias CopyEvent = @convention(c) (UnsafeRawPointer?, Int64, Int32, Int64) -> UnsafeMutableRawPointer?
    private typealias GetFloat = @convention(c) (UnsafeRawPointer?, Int32) -> Double

    private let library: UnsafeMutableRawPointer
    private let client: UnsafeMutableRawPointer
    private let copyServices: CopyServices
    private let copyProperty: CopyProperty
    private let copyEvent: CopyEvent
    private let getFloat: GetFloat

    init?() {
        guard let library = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_NOW) else { return nil }
        guard let create: Create = Self.resolve("IOHIDEventSystemClientCreate", in: library),
              let setMatching: SetMatching = Self.resolve("IOHIDEventSystemClientSetMatching", in: library),
              let copyServices: CopyServices = Self.resolve("IOHIDEventSystemClientCopyServices", in: library),
              let copyProperty: CopyProperty = Self.resolve("IOHIDServiceClientCopyProperty", in: library),
              let copyEvent: CopyEvent = Self.resolve("IOHIDServiceClientCopyEvent", in: library),
              let getFloat: GetFloat = Self.resolve("IOHIDEventGetFloatValue", in: library),
              let client = create(nil) else {
            dlclose(library)
            return nil
        }
        let matching: NSDictionary = [
            "PrimaryUsagePage": NSNumber(value: 0xff00),
            "PrimaryUsage": NSNumber(value: 5)
        ]
        setMatching(client, Unmanaged.passUnretained(matching).toOpaque())
        self.library = library
        self.client = client
        self.copyServices = copyServices
        self.copyProperty = copyProperty
        self.copyEvent = copyEvent
        self.getFloat = getFloat
    }

    deinit {
        Unmanaged<CFTypeRef>.fromOpaque(client).release()
        dlclose(library)
    }

    func cpuTemperatures() -> [TemperatureReading] {
        guard let pointer = copyServices(client) else { return [] }
        let services = Unmanaged<CFArray>.fromOpaque(pointer).takeRetainedValue()
        let product = "Product" as CFString
        var cores: [String: [Double]] = [:]
        var dies: [String: [Double]] = [:]

        for index in 0..<CFArrayGetCount(services) {
            guard let service = CFArrayGetValueAtIndex(services, index),
                  let namePointer = copyProperty(service, Unmanaged.passUnretained(product).toOpaque()) else { continue }
            let name = Unmanaged<CFString>.fromOpaque(namePointer).takeRetainedValue() as String
            let lower = name.lowercased()
            let isCore = lower.hasPrefix("eacc ") || lower.hasPrefix("pacc ")
            let dieIndex = lower.hasPrefix("pmu tdie") ? lower.dropFirst("pmu tdie".count) : ""
            let isDie = !dieIndex.isEmpty && dieIndex.allSatisfy(\.isNumber)
            guard isCore || isDie, let event = copyEvent(service, 15, 0, 0) else { continue }
            let value = getFloat(event, 15 << 16)
            Unmanaged<CFTypeRef>.fromOpaque(event).release()
            guard value.isFinite, value > 10, value < 120 else { continue }
            if isCore { cores[name, default: []].append(value) }
            else { dies[name, default: []].append(value) }
        }

        let selected = cores.isEmpty ? dies : cores
        return selected.keys.sorted { $0.localizedStandardCompare($1) == .orderedAscending }.compactMap { name in
            guard let values = selected[name], !values.isEmpty else { return nil }
            return TemperatureReading(key: "HID:\(name)", name: name, celsius: values.reduce(0, +) / Double(values.count))
        }
    }

    private static func resolve<T>(_ name: String, in library: UnsafeMutableRawPointer) -> T? {
        guard let symbol = dlsym(library, name) else { return nil }
        return unsafeBitCast(symbol, to: T.self)
    }
}
