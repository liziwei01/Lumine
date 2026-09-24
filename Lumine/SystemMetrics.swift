import AppKit
import Combine
import CoreWLAN
import Darwin
import IOKit
import IOKit.ps

enum DetailKind: String, CaseIterable {
    case disk, memory, battery, cpu, network, devices
}

struct ProcessUsage: Identifiable {
    let id: Int32
    let name: String
    let commandPath: String
    let memoryBytes: UInt64
    let cpuPercent: Double
}

struct CoreUsage {
    let index: Int
    let total: Double
    let user: Double
    let system: Double
}

struct ExternalVolume: Identifiable {
    let id: String
    let name: String
    let totalBytes: Int64
    let freeBytes: Int64
}

struct SystemMetrics {
    var deviceName = Host.current().localizedName ?? "Mac"
    var cpuName = "CPU"
    var volumeName = "Macintosh HD"
    var diskTotal: Int64 = 0
    var diskFree: Int64 = 0
    var memoryTotal: UInt64 = 0
    var memoryFree: UInt64 = 0
    var memoryImmediatelyFree: UInt64 = 0
    var memoryActive: UInt64 = 0
    var memoryWired: UInt64 = 0
    var memoryCompressed: UInt64 = 0
    var swapUsed: UInt64 = 0
    var cpuTotal: Double = 0
    var cpuUser: Double = 0
    var cpuSystem: Double = 0
    var cpuCores: [CoreUsage] = []
    var cpuTemperatures: [TemperatureReading] = []
    var batteryPercent: Int? = nil
    var batteryMinutes: Int? = nil
    var batteryCharging = false
    var batteryOnAC = false
    var batteryCycles: Int? = nil
    var batteryDesignCycles: Int? = nil
    var batteryHealthPercent: Double? = nil
    var batteryTemperature: Double? = nil
    var networkName = "网络"
    var networkInterface = ""
    var networkSecurity = ""
    var networkSecurityStrong: Bool? = nil
    var networkInterfaces: [String] = []
    var uploadBytesPerSecond: Double = 0
    var downloadBytesPerSecond: Double = 0
    var uploadedBytes: UInt64 = 0
    var downloadedBytes: UInt64 = 0
    var externalVolumes: [ExternalVolume] = []
    var processes: [ProcessUsage] = []
    var uptime: TimeInterval = 0

    var memoryUsed: UInt64 { memoryTotal > memoryFree ? memoryTotal - memoryFree : 0 }
    var memoryPressureEstimate: Double {
        memoryTotal > 0 ? min(100, Double(memoryUsed) / Double(memoryTotal) * 100) : 0
    }
}

private struct CPUCounters {
    let user: UInt64
    let system: UInt64
    let idle: UInt64
    let nice: UInt64
}

private struct NetworkCounters {
    let received: UInt64
    let sent: UInt64
}

// All mutable state is accessed on MonitorStore's serial sampling queue.
final class SystemSampler: @unchecked Sendable {
    private var previousCPU: CPUCounters?
    private var previousCoreCounters: [CPUCounters] = []
    private var previousNetwork: [String: NetworkCounters] = [:]
    private var previousTime: TimeInterval?
    private lazy var modelName = cpuModelName()
    private var smcReader = SMCReader()
    private var cachedProcesses: [ProcessUsage] = []
    private var lastProcessSample: TimeInterval = 0

    func sample(networkInterface: String = "auto", includeProcesses: Bool = false) -> SystemMetrics {
        var result = SystemMetrics()
        result.uptime = ProcessInfo.processInfo.systemUptime
        result.cpuName = modelName
        sampleCPU(into: &result)
        sampleCores(into: &result)
        result.cpuTemperatures = smcReader?.cpuTemperatures(model: result.cpuName) ?? []
        sampleMemory(into: &result)
        sampleDisk(into: &result)
        sampleBattery(into: &result)
        sampleBatteryRegistry(into: &result)
        sampleNetwork(into: &result, preferredInterface: networkInterface)
        if includeProcesses {
            let now = ProcessInfo.processInfo.systemUptime
            if now - lastProcessSample >= 10 {
                sampleProcesses(into: &result)
                cachedProcesses = result.processes
                lastProcessSample = now
            } else {
                result.processes = cachedProcesses
            }
        }
        return result
    }

    func stop() {
        smcReader?.close()
        smcReader = nil
    }

    private func cpuModelName() -> String {
        var size = 0
        guard sysctlbyname("machdep.cpu.brand_string", nil, &size, nil, 0) == 0, size > 1 else { return "CPU" }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname("machdep.cpu.brand_string", &buffer, &size, nil, 0) == 0 else { return "CPU" }
        return String(cString: buffer)
    }

    private func sampleCPU(into result: inout SystemMetrics) {
        var info = host_cpu_load_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info_data_t>.size / MemoryLayout<integer_t>.size)
        let status = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard status == KERN_SUCCESS else { return }
        let current = CPUCounters(
            user: UInt64(info.cpu_ticks.0),
            system: UInt64(info.cpu_ticks.1),
            idle: UInt64(info.cpu_ticks.2),
            nice: UInt64(info.cpu_ticks.3)
        )
        if let previousCPU {
            let user = Double(current.user &- previousCPU.user)
            let system = Double(current.system &- previousCPU.system)
            let idle = Double(current.idle &- previousCPU.idle)
            let nice = Double(current.nice &- previousCPU.nice)
            let total = user + system + idle + nice
            if total > 0 {
                result.cpuUser = (user + nice) / total * 100
                result.cpuSystem = system / total * 100
                result.cpuTotal = result.cpuUser + result.cpuSystem
            }
        }
        previousCPU = current
    }

    private func sampleCores(into result: inout SystemMetrics) {
        var processorCount: natural_t = 0
        var information: processor_info_array_t?
        var informationCount: mach_msg_type_number_t = 0
        guard host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO, &processorCount, &information, &informationCount) == KERN_SUCCESS,
              let information else { return }
        defer {
            vm_deallocate(mach_task_self_, vm_address_t(UInt(bitPattern: information)), vm_size_t(informationCount) * vm_size_t(MemoryLayout<integer_t>.size))
        }
        let states = Int(CPU_STATE_MAX)
        var currentCounters: [CPUCounters] = []
        for index in 0..<Int(processorCount) {
            let start = index * states
            guard start + states <= Int(informationCount) else { break }
            let current = CPUCounters(
                user: UInt64(UInt32(bitPattern: information[start + Int(CPU_STATE_USER)])),
                system: UInt64(UInt32(bitPattern: information[start + Int(CPU_STATE_SYSTEM)])),
                idle: UInt64(UInt32(bitPattern: information[start + Int(CPU_STATE_IDLE)])),
                nice: UInt64(UInt32(bitPattern: information[start + Int(CPU_STATE_NICE)]))
            )
            currentCounters.append(current)
            var usage = CoreUsage(index: index, total: 0, user: 0, system: 0)
            if index < previousCoreCounters.count {
                let prior = previousCoreCounters[index]
                let user = Double(current.user &- prior.user)
                let system = Double(current.system &- prior.system)
                let idle = Double(current.idle &- prior.idle)
                let nice = Double(current.nice &- prior.nice)
                let sum = user + system + idle + nice
                if sum > 0 {
                    usage = CoreUsage(index: index, total: (user + system + nice) / sum * 100, user: (user + nice) / sum * 100, system: system / sum * 100)
                }
            }
            result.cpuCores.append(usage)
        }
        previousCoreCounters = currentCounters
    }

    private func sampleMemory(into result: inout SystemMetrics) {
        result.memoryTotal = ProcessInfo.processInfo.physicalMemory
        var info = vm_statistics64_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        let status = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard status == KERN_SUCCESS else { return }
        let pageSize = UInt64(vm_kernel_page_size)
        result.memoryImmediatelyFree = UInt64(info.free_count) * pageSize
        result.memoryActive = UInt64(info.active_count) * pageSize
        result.memoryWired = UInt64(info.wire_count) * pageSize
        result.memoryCompressed = UInt64(info.compressor_page_count) * pageSize
        let freePages = UInt64(info.free_count) + UInt64(info.inactive_count) + UInt64(info.speculative_count)
        result.memoryFree = min(result.memoryTotal, freePages * pageSize)

        var usage = xsw_usage()
        var size = MemoryLayout<xsw_usage>.size
        if sysctlbyname("vm.swapusage", &usage, &size, nil, 0) == 0 {
            result.swapUsed = usage.xsu_used
        }
    }

    private func sampleDisk(into result: inout SystemMetrics) {
        let root = URL(fileURLWithPath: "/")
        let keys: Set<URLResourceKey> = [.volumeNameKey, .volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey]
        if let values = try? root.resourceValues(forKeys: keys) {
            result.volumeName = values.volumeName ?? result.volumeName
            result.diskTotal = Int64(values.volumeTotalCapacity ?? 0)
            result.diskFree = values.volumeAvailableCapacityForImportantUsage ?? 0
        }
        let volumeKeys: Set<URLResourceKey> = [.volumeNameKey, .volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey, .volumeIsInternalKey, .volumeIsLocalKey]
        result.externalVolumes = (FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: Array(volumeKeys), options: [.skipHiddenVolumes]) ?? [])
            .compactMap { url -> ExternalVolume? in
                guard let values = try? url.resourceValues(forKeys: volumeKeys),
                      values.volumeIsLocal != false,
                      values.volumeIsInternal == false || url.path.hasPrefix("/Volumes/") else { return nil }
                return ExternalVolume(
                    id: url.path,
                    name: values.volumeName ?? url.lastPathComponent,
                    totalBytes: Int64(values.volumeTotalCapacity ?? 0),
                    freeBytes: values.volumeAvailableCapacityForImportantUsage ?? 0
                )
            }
    }

    private func sampleBattery(into result: inout SystemMetrics) {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else { return }
        for source in sources {
            guard let details = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
                  let current = details[kIOPSCurrentCapacityKey as String] as? Int,
                  let maxCapacity = details[kIOPSMaxCapacityKey as String] as? Int,
                  maxCapacity > 0 else { continue }
            result.batteryPercent = Int((Double(current) / Double(maxCapacity) * 100).rounded())
            result.batteryCharging = details[kIOPSIsChargingKey as String] as? Bool ?? false
            result.batteryOnAC = (details[kIOPSPowerSourceStateKey as String] as? String) == (kIOPSACPowerValue as String)
            let minutesKey = result.batteryOnAC ? kIOPSTimeToFullChargeKey : kIOPSTimeToEmptyKey
            if let minutes = details[minutesKey as String] as? Int, minutes >= 0, minutes < 24 * 60 {
                result.batteryMinutes = minutes
            }
            return
        }
    }

    private func sampleBatteryRegistry(into result: inout SystemMetrics) {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard service != IO_OBJECT_NULL else { return }
        defer { IOObjectRelease(service) }

        func value(_ key: String) -> Any? {
            IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue()
        }
        result.batteryCycles = (value("CycleCount") as? NSNumber)?.intValue
        result.batteryDesignCycles = (value("DesignCycleCount9C") as? NSNumber)?.intValue
        if let raw = (value("Temperature") as? NSNumber)?.doubleValue {
            let temperature = raw > 1000 ? raw / 100 : raw
            if (0...80).contains(temperature) { result.batteryTemperature = temperature }
        }
        if let data = value("BatteryData") as? [String: Any],
           let full = data["FullChargeCapacity"] as? NSNumber,
           let design = data["DesignCapacity"] as? NSNumber,
           design.doubleValue > 0 {
            result.batteryHealthPercent = min(100, full.doubleValue / design.doubleValue * 100)
        }
    }

    private func sampleNetwork(into result: inout SystemMetrics, preferredInterface: String) {
        let wifi = CWWiFiClient.shared().interface()
        let wifiName = wifi?.ssid()
        let wifiInterface = wifi?.interfaceName
        var addressList: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&addressList) == 0, let head = addressList else { return }
        defer { freeifaddrs(head) }
        var counters: [String: NetworkCounters] = [:]
        var cursor: UnsafeMutablePointer<ifaddrs>? = head
        while let entry = cursor?.pointee {
            defer { cursor = entry.ifa_next }
            guard let address = entry.ifa_addr, address.pointee.sa_family == UInt8(AF_LINK),
                  let data = entry.ifa_data else { continue }
            let name = String(cString: entry.ifa_name)
            guard (entry.ifa_flags & UInt32(IFF_LOOPBACK)) == 0,
                  (entry.ifa_flags & UInt32(IFF_UP)) != 0 else { continue }
            let stats = data.assumingMemoryBound(to: if_data.self).pointee
            counters[name] = NetworkCounters(received: UInt64(stats.ifi_ibytes), sent: UInt64(stats.ifi_obytes))
        }
        result.networkInterfaces = counters.keys.sorted()
        let chosen = (preferredInterface != "auto" && counters[preferredInterface] != nil ? preferredInterface : nil)
            ?? wifiInterface.flatMap { counters[$0] != nil ? $0 : nil }
            ?? counters.keys.filter { $0.hasPrefix("en") }.sorted().first
            ?? counters.keys.sorted().first
        let now = ProcessInfo.processInfo.systemUptime
        if let chosen, let current = counters[chosen] {
            result.networkInterface = chosen
            result.networkName = chosen == wifiInterface ? (wifiName ?? "Wi-Fi") : chosen
            if chosen == wifiInterface, let security = wifi?.security().rawValue {
                switch security {
                case 0: result.networkSecurity = "开放网络"; result.networkSecurityStrong = false
                case 4, 9: result.networkSecurity = "WPA2"; result.networkSecurityStrong = true
                case 11, 12, 13: result.networkSecurity = "WPA3"; result.networkSecurityStrong = true
                case 1, 2, 3, 5, 6, 7, 8, 10: result.networkSecurity = "旧版 Wi-Fi 加密"; result.networkSecurityStrong = false
                default: result.networkSecurity = "未知安全协议"
                }
            } else if chosen != wifiInterface {
                result.networkSecurity = "有线或其他接口"
            }
            if let prior = previousNetwork[chosen], let previousTime {
                let elapsed = max(now - previousTime, 0.1)
                result.downloadedBytes = counterDelta(current.received, prior.received)
                result.uploadedBytes = counterDelta(current.sent, prior.sent)
                result.downloadBytesPerSecond = Double(result.downloadedBytes) / elapsed
                result.uploadBytesPerSecond = Double(result.uploadedBytes) / elapsed
            }
        }
        previousNetwork = counters
        previousTime = now
    }

    private func counterDelta(_ current: UInt64, _ prior: UInt64) -> UInt64 {
        if current >= prior { return current - prior }
        if prior <= UInt32.max && current <= UInt32.max { return UInt64(UInt32.max) - prior + current + 1 }
        return 0
    }

    private func sampleProcesses(into result: inout SystemMetrics) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-ww", "-axo", "pid=,rss=,%cpu=,comm="]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = Pipe()
        do {
            try process.run()
            let data = output.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            guard process.terminationStatus == 0, let text = String(data: data, encoding: .utf8) else { return }
            result.processes = text.split(separator: "\n").compactMap { line in
                let parts = line.split(maxSplits: 3, whereSeparator: \.isWhitespace)
                guard parts.count == 4, let pid = Int32(parts[0]),
                      let rss = UInt64(parts[1]), let cpu = Double(parts[2]) else { return nil }
                let commandPath = String(parts[3])
                let name = URL(fileURLWithPath: commandPath).lastPathComponent
                return ProcessUsage(id: pid, name: name, commandPath: commandPath, memoryBytes: rss * 1024, cpuPercent: cpu)
            }
        } catch {
            return
        }
    }
}

@MainActor
final class MonitorStore: ObservableObject {
    @Published private(set) var metrics = SystemMetrics()
    @Published private(set) var cpuHistory: [Double] = Array(repeating: 0, count: 60)
    @Published private(set) var downloadHistory: [Double] = Array(repeating: 0, count: 60)
    @Published private(set) var uploadHistory: [Double] = Array(repeating: 0, count: 60)
    let trafficHistory = TrafficHistoryStore()

    private let sampler = SystemSampler()
    private let samplingQueue = DispatchQueue(label: "app.lumine.sampling", qos: .utility)
    private let preferences = PreferencesStore.shared
    private var timer: Timer?
    private var lastCPUSource = "overall"
    private var isActive = false
    private var activeDetail: DetailKind?
    private var isSampling = false
    private var isStopped = false
    private var pendingDetailRefresh = false

    var selectedCPU: CoreUsage {
        let source = preferences.values.cpuSource
        if source.hasPrefix("core:"), let index = Int(source.dropFirst(5)),
           let core = metrics.cpuCores.first(where: { $0.index == index }) { return core }
        return CoreUsage(index: -1, total: metrics.cpuTotal, user: metrics.cpuUser, system: metrics.cpuSystem)
    }

    var cpuSourceLabel: String {
        selectedCPU.index < 0 ? L10n.tr("总体") : L10n.tr("核心 \(selectedCPU.index)")
    }

    var selectedTemperature: Double? {
        let readings = metrics.cpuTemperatures
        guard !readings.isEmpty else { return nil }
        let source = preferences.values.temperatureSource
        if source == "off" { return nil }
        if source == "hottest" { return readings.map(\.celsius).max() }
        if source.hasPrefix("sensor:") {
            return readings.first { $0.key == String(source.dropFirst(7)) }?.celsius
        }
        return readings.map(\.celsius).reduce(0, +) / Double(readings.count)
    }

    var selectedVolume: ExternalVolume {
        if let external = metrics.externalVolumes.first(where: { $0.id == preferences.values.diskSource }) { return external }
        return ExternalVolume(id: "startup", name: metrics.volumeName, totalBytes: metrics.diskTotal, freeBytes: metrics.diskFree)
    }

    var selectedMemoryFree: UInt64 {
        preferences.values.memorySource == "free" ? metrics.memoryImmediatelyFree : metrics.memoryFree
    }

    var selectedMemoryUsage: Double {
        guard metrics.memoryTotal > 0 else { return 0 }
        return min(100, Double(metrics.memoryTotal - min(selectedMemoryFree, metrics.memoryTotal)) / Double(metrics.memoryTotal) * 100)
    }

    init() {
        refresh()
        schedule()
    }

    func setActive(_ active: Bool) {
        isActive = active
        if !active { activeDetail = nil }
        schedule()
        if active { refresh() }
    }

    func setDetail(_ detail: DetailKind?) {
        activeDetail = detail
        pendingDetailRefresh = (detail == .cpu && preferences.values.shows(.cpuProcesses)) ||
            (detail == .memory && preferences.values.shows(.memoryProcesses)) ||
            (detail == .battery && preferences.values.shows(.batteryProcesses))
        if pendingDetailRefresh { refresh() }
    }

    func reschedule() {
        schedule()
    }

    func refresh() {
        guard !isSampling && !isStopped else { return }
        isSampling = true
        let interface = preferences.values.networkInterface
        let includeProcesses = (activeDetail == .cpu && preferences.values.shows(.cpuProcesses)) ||
            (activeDetail == .memory && preferences.values.shows(.memoryProcesses)) ||
            (activeDetail == .battery && preferences.values.shows(.batteryProcesses))
        samplingQueue.async { [weak self] in
            guard let self else { return }
            let sampled = self.sampler.sample(networkInterface: interface, includeProcesses: includeProcesses)
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.isSampling = false
                guard !self.isStopped else { return }
                self.metrics = sampled
                self.trafficHistory.record(interface: sampled.networkInterface,
                                           download: sampled.downloadedBytes,
                                           upload: sampled.uploadedBytes)
                self.recordHistory()
                if self.pendingDetailRefresh {
                    self.pendingDetailRefresh = false
                    if !includeProcesses { self.refresh() }
                }
            }
        }
    }

    private func recordHistory() {
        if lastCPUSource != preferences.values.cpuSource {
            cpuHistory = Array(repeating: 0, count: 60)
            lastCPUSource = preferences.values.cpuSource
        }
        append(selectedCPU.total, to: &cpuHistory)
        append(metrics.downloadBytesPerSecond, to: &downloadHistory)
        append(metrics.uploadBytesPerSecond, to: &uploadHistory)
    }

    func stop() {
        isStopped = true
        timer?.invalidate()
        timer = nil
        trafficHistory.flush()
        samplingQueue.async { [sampler] in sampler.stop() }
    }

    private func append(_ value: Double, to history: inout [Double]) {
        history.append(value)
        if history.count > 60 { history.removeFirst(history.count - 60) }
    }

    private func schedule() {
        timer?.invalidate()
        let interval = isActive ? preferences.values.activeSamplingInterval : preferences.values.idleSamplingInterval
        let seconds = TimeInterval(max(2, interval))
        timer = Timer.scheduledTimer(withTimeInterval: seconds, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }
}

enum MetricFormat {
    static func bytes(_ value: Double, decimals: Int = 1, base: Double = 1024) -> String {
        guard value.isFinite else { return "—" }
        let units = ["B", "KB", "MB", "GB", "TB"]
        var number = max(value, 0)
        var index = 0
        while number >= base, index < units.count - 1 {
            number /= base
            index += 1
        }
        return String(format: "%.*f %@", locale: L10n.locale, arguments: [index == 0 ? 0 : decimals, number, units[index]])
    }

    static func diskBytes(_ value: Double, decimals: Int = 2) -> String { bytes(value, decimals: decimals, base: 1000) }
    static func speed(_ value: Double) -> String { bytes(value, decimals: value < 10_000 ? 1 : 0, base: 1000) + L10n.tr("/秒") }
    static func percent(_ value: Double) -> String { String(format: "%.0f%%", locale: L10n.locale, arguments: [value]) }
    static func duration(_ minutes: Int?) -> String {
        guard let minutes else { return L10n.tr("剩余时间不可用") }
        return L10n.tr("约 \(minutes / 60) 小时 \(minutes % 60) 分钟")
    }
}
