import Foundation
import IOKit

struct GPUUsage: Identifiable {
    let id: String
    let name: String
    let utilization: Double?
    let renderer: Double?
    let tiler: Double?
    let memoryUsed: UInt64?
    let coreCount: Int?
}

/// Driver statistics are optional and differ across Apple, Intel and AMD GPUs.
/// Keep each accelerator separate; never add utilization percentages across devices.
enum GPUSampler {
    static func sample() -> [GPUUsage]? {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOAccelerator"), &iterator) == KERN_SUCCESS else { return nil }
        defer { IOObjectRelease(iterator) }
        var devices: [GPUUsage] = []
        while case let service = IOIteratorNext(iterator), service != 0 {
            defer { IOObjectRelease(service) }
            var registryID: UInt64 = 0
            guard IORegistryEntryGetRegistryEntryID(service, &registryID) == KERN_SUCCESS else { continue }
            var properties: Unmanaged<CFMutableDictionary>?
            guard IORegistryEntryCreateCFProperties(service, &properties, kCFAllocatorDefault, 0) == KERN_SUCCESS,
                  let values = properties?.takeRetainedValue() as? [String: Any] else { continue }
            let stats = values["PerformanceStatistics"] as? [String: Any] ?? [:]
            var model = values["model"]
            if model == nil {
                model = IORegistryEntrySearchCFProperty(service, kIOServicePlane, "model" as CFString, kCFAllocatorDefault,
                                                       IOOptionBits(kIORegistryIterateRecursively | kIORegistryIterateParents))
            }
            let name: String
            if let string = model as? String { name = string }
            else if let data = model as? Data, let string = String(data: data, encoding: .utf8) { name = string.trimmingCharacters(in: .controlCharacters) }
            else { name = "GPU" }
            // A registry path remains usable across launches and reboots.
            var path = [CChar](repeating: 0, count: 512)
            let id = IORegistryEntryGetPath(service, kIOServicePlane, &path) == KERN_SUCCESS
                ? String(cString: path) : String(registryID)
            devices.append(GPUUsage(id: id, name: name,
                                    utilization: percentage(stats["Device Utilization %"]),
                                    renderer: percentage(stats["Renderer Utilization %"]),
                                    tiler: percentage(stats["Tiler Utilization %"]),
                                    memoryUsed: bytes(stats["In use system memory"]),
                                    coreCount: (values["gpu-core-count"] as? NSNumber).flatMap { $0.intValue > 0 ? $0.intValue : nil }))
        }
        return devices.sorted { $0.id < $1.id }
    }

    static func percentage(_ raw: Any?) -> Double? {
        guard let value = (raw as? NSNumber)?.doubleValue, value.isFinite, (0...100).contains(value) else { return nil }
        return value
    }

    static func bytes(_ raw: Any?) -> UInt64? {
        guard let value = raw as? NSNumber, value.doubleValue.isFinite, value.doubleValue >= 0,
              value.doubleValue < Double(UInt64.max) else { return nil }
        return value.uint64Value
    }
}
