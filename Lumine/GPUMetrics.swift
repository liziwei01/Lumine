import Foundation
import Darwin
import IOKit

enum GPUUtilizationSource: String { case driverSnapshot, interval }

struct GPUUsage: Identifiable {
    let id: String
    let name: String
    var utilization: Double?
    let renderer: Double?
    let tiler: Double?
    let memoryUsed: UInt64?
    let coreCount: Int?
    var utilizationSource: GPUUtilizationSource = .driverSnapshot
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

/// A time-window measurement, distinct from the driver's instantaneous snapshot.
/// Private IOReport symbols are resolved at runtime and may be unavailable.
final class GPUActivitySampler {
    private typealias CopyGroup = @convention(c) (UnsafeRawPointer?, UnsafeRawPointer?, UInt64, UInt64, UInt64) -> UnsafeMutableRawPointer?
    private typealias Subscribe = @convention(c) (UnsafeRawPointer?, UnsafeMutableRawPointer?, UnsafeMutablePointer<UnsafeMutableRawPointer?>?, UInt64, UnsafeRawPointer?) -> UnsafeMutableRawPointer?
    private typealias Samples = @convention(c) (UnsafeRawPointer?, UnsafeRawPointer?, UnsafeRawPointer?) -> UnsafeMutableRawPointer?
    private typealias Count = @convention(c) (UnsafeRawPointer?) -> Int32
    private typealias Name = @convention(c) (UnsafeRawPointer?, Int32) -> UnsafeRawPointer?
    private typealias Residency = @convention(c) (UnsafeRawPointer?, Int32) -> Int64
    private let library: UnsafeMutableRawPointer
    private let subscription: UnsafeMutableRawPointer
    private let channels: CFDictionary
    private let createSamples: Samples
    private let createDelta: Samples
    private let stateCount: Count
    private let stateName: Name
    private let stateResidency: Residency
    private var previous: CFDictionary?

    init?() {
        guard let library = dlopen("/usr/lib/libIOReport.dylib", RTLD_NOW) else { return nil }
        func resolve<T>(_ name: String) -> T? {
            guard let symbol = dlsym(library, name) else { return nil }
            return unsafeBitCast(symbol, to: T.self)
        }
        guard let copy: CopyGroup = resolve("IOReportCopyChannelsInGroup"),
              let subscribe: Subscribe = resolve("IOReportCreateSubscription"),
              let samples: Samples = resolve("IOReportCreateSamples"),
              let delta: Samples = resolve("IOReportCreateSamplesDelta"),
              let count: Count = resolve("IOReportStateGetCount"),
              let name: Name = resolve("IOReportStateGetNameForIndex"),
              let residency: Residency = resolve("IOReportStateGetResidency") else {
            dlclose(library); return nil
        }
        let group = "GPU Stats" as CFString
        let subgroup = "GPU Performance States" as CFString
        guard let pointer = copy(Unmanaged.passUnretained(group).toOpaque(), Unmanaged.passUnretained(subgroup).toOpaque(), 0, 0, 0) else {
            dlclose(library); return nil
        }
        let original = Unmanaged<CFDictionary>.fromOpaque(pointer).takeRetainedValue()
        var actual: UnsafeMutableRawPointer?
        guard let sub = subscribe(nil, pointer, &actual, 0, nil) else {
            if let actual { Unmanaged<CFTypeRef>.fromOpaque(actual).release() }
            dlclose(library); return nil
        }
        self.library = library
        self.subscription = sub
        self.channels = actual.map { Unmanaged<CFDictionary>.fromOpaque($0).takeRetainedValue() } ?? original
        self.createSamples = samples; self.createDelta = delta
        self.stateCount = count; self.stateName = name; self.stateResidency = residency
    }

    deinit {
        previous = nil
        Unmanaged<CFTypeRef>.fromOpaque(subscription).release()
        dlclose(library)
    }

    private func snapshot() -> CFDictionary? {
        guard let pointer = createSamples(subscription, Unmanaged.passUnretained(channels).toOpaque(), nil) else { return nil }
        return Unmanaged<CFDictionary>.fromOpaque(pointer).takeRetainedValue()
    }

    func begin() { previous = snapshot() }

    func finish() -> Double? {
        defer { previous = nil }
        guard let previous, let current = snapshot(),
              let pointer = createDelta(Unmanaged.passUnretained(previous).toOpaque(), Unmanaged.passUnretained(current).toOpaque(), nil) else { return nil }
        let delta = Unmanaged<CFDictionary>.fromOpaque(pointer).takeRetainedValue()
        guard let dictionary = delta as? [String: Any],
              let channels = dictionary["IOReportChannels"] as? [NSDictionary], channels.count == 1,
              let channel = channels.first else { return nil }
        let raw = Unmanaged.passUnretained(channel).toOpaque()
        let count = stateCount(raw)
        guard count > 0, count <= 256 else { return nil }
        var states: [(String, Int64)] = []
        for index in 0..<count {
            guard let name = stateName(raw, index) else { return nil }
            let label = Unmanaged<CFString>.fromOpaque(name).takeUnretainedValue() as String
            states.append((label, stateResidency(raw, index)))
        }
        return Self.activePercent(states)
    }

    static func activePercent(_ states: [(String, Int64)]) -> Double? {
        var total = 0.0, active = 0.0
        var hasIdle = false, hasActive = false
        for (label, ticks) in states {
            guard ticks >= 0 else { return nil }
            let name = label.uppercased()
            let idle = ["OFF", "IDLE", "DOWN"].contains(name)
            let frequency = name.hasPrefix("P") && Int(name.dropFirst()).map { $0 > 0 } == true
            guard idle || frequency else { return nil }
            hasIdle = hasIdle || idle; hasActive = hasActive || frequency
            total += Double(ticks)
            if frequency { active += Double(ticks) }
        }
        guard hasIdle, hasActive, total > 0 else { return nil }
        return active / total * 100
    }

    static func applying(_ activity: Double?, to devices: [GPUUsage]) -> [GPUUsage] {
        let apple = devices.indices.filter { devices[$0].name.hasPrefix("Apple ") }
        guard devices.count == 1, let activity, activity.isFinite, (0...100).contains(activity), apple.count == 1 else { return devices }
        var result = devices
        result[apple[0]].utilization = activity
        result[apple[0]].utilizationSource = .interval
        return result
    }
}


struct GPUProcessUsage: Identifiable {
    let id: Int32
    let name: String
    let gpuPercent: Double
}

/// AGX counters are private, optional driver data. Keep clients and devices separate
/// until after differencing: disappearing queues/clients must not subtract another PID's time.
enum GPUProcessSampler {
    struct Client {
        let id: UInt64
        let pid: Int32
        let name: String
        let queueTimes: [UInt64]
    }
    struct Snapshot {
        let time: TimeInterval
        let devices: [String: [Client]]
    }

    static func snapshot() -> Snapshot {
        var devices: [String: [Client]] = [:]
        var accelerators: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOAccelerator"), &accelerators) == KERN_SUCCESS else {
            return Snapshot(time: ProcessInfo.processInfo.systemUptime, devices: [:])
        }
        defer { IOObjectRelease(accelerators) }
        while case let accelerator = IOIteratorNext(accelerators), accelerator != 0 {
            defer { IOObjectRelease(accelerator) }
            var path = [CChar](repeating: 0, count: 512)
            guard IORegistryEntryGetPath(accelerator, kIOServicePlane, &path) == KERN_SUCCESS else { continue }
            let deviceID = String(cString: path)
            var children: io_iterator_t = 0
            guard IORegistryEntryCreateIterator(accelerator, kIOServicePlane, IOOptionBits(kIORegistryIterateRecursively), &children) == KERN_SUCCESS else { continue }
            defer { IOObjectRelease(children) }
            var clients: [Client] = []
            var supported = false
            while case let child = IOIteratorNext(children), child != 0 {
                defer { IOObjectRelease(child) }
                guard IOObjectConformsTo(child, "AGXDeviceUserClient") != 0 else { continue }
                var properties: Unmanaged<CFMutableDictionary>?
                guard IORegistryEntryCreateCFProperties(child, &properties, kCFAllocatorDefault, 0) == KERN_SUCCESS,
                      let values = properties?.takeRetainedValue() as? [String: Any],
                      let usage = values["AppUsage"] as? [[String: Any]] else { continue }
                supported = true
                guard let creator = values["IOUserClientCreator"] as? String,
                      let owner = owner(creator) else { continue }
                var clientID: UInt64 = 0
                guard IORegistryEntryGetRegistryEntryID(child, &clientID) == KERN_SUCCESS else { continue }
                let times = usage.compactMap { GPUSampler.bytes($0["accumulatedGPUTime"]) }
                guard times.count == usage.count else { continue }
                clients.append(Client(id: clientID, pid: owner.pid, name: owner.name, queueTimes: times))
            }
            if supported { devices[deviceID] = clients }
        }
        return Snapshot(time: ProcessInfo.processInfo.systemUptime, devices: devices)
    }

    static func owner(_ creator: String) -> (pid: Int32, name: String)? {
        guard creator.hasPrefix("pid "), let comma = creator.firstIndex(of: ","),
              let pid = Int32(creator[creator.index(creator.startIndex, offsetBy: 4)..<comma]), pid > 0 else { return nil }
        return (pid, String(creator[creator.index(after: comma)...]).trimmingCharacters(in: .whitespaces))
    }

    static func usage(from start: Snapshot, to end: Snapshot) -> [String: [GPUProcessUsage]] {
        let seconds = end.time - start.time
        guard seconds.isFinite, seconds > 0 else { return [:] }
        var result: [String: [GPUProcessUsage]] = [:]
        for (device, clients) in end.devices {
            guard let oldClients = start.devices[device] else { continue }
            let oldByID = Dictionary(oldClients.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            var totals: [Int32: (name: String, nanoseconds: Double)] = [:]
            for client in clients {
                guard let old = oldByID[client.id], old.pid == client.pid,
                      old.queueTimes.count == client.queueTimes.count,
                      zip(old.queueTimes, client.queueTimes).allSatisfy({ $1 >= $0 }) else { continue }
                let delta = zip(old.queueTimes, client.queueTimes).reduce(0.0) { $0 + Double($1.1 - $1.0) }
                let previous = totals[client.pid]?.nanoseconds ?? 0
                totals[client.pid] = (client.name, previous + delta)
            }
            result[device] = totals.map { pid, value in
                GPUProcessUsage(id: pid, name: value.name, gpuPercent: value.nanoseconds / (seconds * 1_000_000_000) * 100)
            }.sorted { $0.gpuPercent == $1.gpuPercent ? $0.id < $1.id : $0.gpuPercent > $1.gpuPercent }
        }
        return result
    }

    static func resolveNames(_ devices: [String: [GPUProcessUsage]]) -> [String: [GPUProcessUsage]] {
        devices.mapValues { processes in
            processes.compactMap { process in
                var path = [CChar](repeating: 0, count: 4096)
                let length = proc_pidpath(process.id, &path, UInt32(path.count))
                // A protected process may have no readable path; do not drop it for that reason.
                guard length > 0 || kill(process.id, 0) == 0 || errno == EPERM else { return nil }
                let name = length > 0 ? URL(fileURLWithPath: String(cString: path)).lastPathComponent : process.name
                return GPUProcessUsage(id: process.id, name: name, gpuPercent: process.gpuPercent)
            }
        }
    }
}
