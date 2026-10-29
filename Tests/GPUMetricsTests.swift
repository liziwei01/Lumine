import AppKit
import Foundation
import Metal

@main
struct GPUMetricsTests {
    @MainActor static func main() throws {
        precondition(GPUSampler.percentage(nil) == nil)
        precondition(GPUSampler.percentage("25") == nil)
        for invalid in [-1.0, 101, Double.nan, Double.infinity] {
            precondition(GPUSampler.percentage(NSNumber(value: invalid)) == nil)
        }
        precondition(GPUSampler.percentage(0) == 0)
        precondition(GPUSampler.percentage(100) == 100)
        precondition(GPUSampler.bytes(-1) == nil)
        precondition(GPUSampler.bytes(Double.infinity) == nil)
        precondition(GPUSampler.bytes(0) == 0)
        precondition(GPUSampler.bytes(414629888) == 414629888)
        let legacy = try JSONDecoder().decode(PreferencesData.self, from: Data("{}".utf8))
        precondition(legacy.gpuSource == "auto")
        precondition(legacy.shows(.overviewGPU))

        let store = MonitorStore(startSampling: false)
        func snapshot(_ id: String, usage: Double?, memory: UInt64? = nil) -> SystemMetrics {
            var result = SystemMetrics()
            result.validFields.insert(.gpus)
            result.gpus = [GPUUsage(id: id, name: id, utilization: usage, renderer: nil, tiler: nil, memoryUsed: memory, coreCount: nil)]
            return result
        }
        func merge(_ new: SystemMetrics, _ old: SystemMetrics, _ now: Double, lifetime: Double = 5) -> SystemMetrics {
            store.retainingRecentValues(from: new, previous: old, requestedInterface: "auto", now: now, lifetime: lifetime)
        }
        let first = merge(snapshot("A", usage: 45, memory: 100), SystemMetrics(), 100)
        let retained = merge(snapshot("A", usage: nil), first, 103)
        precondition(retained.gpus.first?.utilization == 45)
        precondition(retained.gpus.first?.memoryUsed == 100)
        let registryFailure = merge(SystemMetrics(), retained, 106)
        precondition(registryFailure.gpus.first?.utilization == nil)
        let expired = merge(snapshot("A", usage: nil), retained, 106)
        precondition(expired.gpus.first?.utilization == nil)
        precondition(expired.gpus.first?.memoryUsed == nil)
        let zero = merge(snapshot("A", usage: 0, memory: 0), first, 107)
        precondition(zero.gpus.first?.utilization == 0 && zero.gpus.first?.memoryUsed == 0)
        let different = merge(snapshot("B", usage: nil), zero, 108)
        precondition(different.gpus.first?.utilization == nil)
        let unavailable = merge(SystemMetrics(), different, 110)
        precondition(unavailable.gpus.first?.id == "B")
        let noRetention = merge(SystemMetrics(), zero, 110, lifetime: 0)
        precondition(noRetention.gpus.isEmpty)
        var removed = SystemMetrics()
        removed.validFields.insert(.gpus)
        precondition(merge(removed, first, 111).gpus.isEmpty)
        precondition(merge(snapshot("A", usage: nil), first, 112).gpus.first?.utilization == nil)
        func chartSample(_ id: String = "A", _ usage: Double? = 50,
                         _ renderer: Double? = 30, _ tiler: Double? = 10) -> SystemMetrics {
            var result = SystemMetrics()
            result.validFields.insert(.gpus)
            result.gpus = [GPUUsage(id: id, name: id, utilization: usage, renderer: renderer,
                                   tiler: tiler, memoryUsed: nil, coreCount: nil)]
            return result
        }
        func record(_ sample: SystemMetrics, selection: GPUUsage? = nil, source: String = "auto") {
            store.recordGPUHistory(fresh: sample, selected: selection ?? sample.gpus.first, source: source)
        }
        record(chartSample())
        record(chartSample("A", 60, 40, 0))
        precondition(store.gpuHistory == [50, 60])
        precondition(store.gpuRendererHistory == [30, 40])
        precondition(store.gpuTilerHistory == [10, 0], "Zero is a valid tiler reading")
        record(chartSample("A", 70, nil, 20))
        precondition(store.gpuHistory == [50, 60, 70] && store.gpuRendererHistory.isEmpty)
        precondition(store.gpuTilerHistory == [10, 0, 20])
        record(chartSample("A", nil, 25, 15))
        precondition(store.gpuHistory.isEmpty && store.gpuRendererHistory == [25])
        record(SystemMetrics(), selection: chartSample().gpus.first)
        precondition(store.gpuHistory.isEmpty && store.gpuRendererHistory.isEmpty && store.gpuTilerHistory.isEmpty)
        record(chartSample())
        record(chartSample("B", 80, 60, 40))
        precondition(store.gpuHistory == [80] && store.gpuRendererHistory == [60] && store.gpuTilerHistory == [40])
        record(chartSample("B", 20, 15, 5), source: "B")
        precondition(store.gpuHistory == [20] && store.gpuRendererHistory == [15] && store.gpuTilerHistory == [5])
        for _ in 0..<70 { record(chartSample("B"), source: "B") }
        precondition(store.gpuHistory.count == 60 && store.gpuRendererHistory.count == 60 && store.gpuTilerHistory.count == 60)
        store.gpuSourceChanged()
        precondition(store.gpuHistory.isEmpty && store.gpuRendererHistory.isEmpty && store.gpuTilerHistory.isEmpty)
        precondition(GPUActivitySampler.activePercent([("OFF", 900), ("P1", 100)]) == 10)
        precondition(GPUActivitySampler.activePercent([("OFF", 0), ("P1", 100)]) == 100)
        precondition(GPUActivitySampler.activePercent([("OFF", 100), ("P1", 0)]) == 0)
        precondition(GPUActivitySampler.activePercent([("IDLE", 20), ("DOWN", 30), ("P2", 50)]) == 50)
        precondition(GPUActivitySampler.activePercent([("OFF", 0), ("P1", 0)]) == nil)
        precondition(GPUActivitySampler.activePercent([("OFF", -1), ("P1", 10)]) == nil)
        precondition(GPUActivitySampler.activePercent([("UNKNOWN", 10), ("P1", 10)]) == nil)
        precondition(GPUActivitySampler.activePercent([("P1", 10)]) == nil)
        let apple = GPUUsage(id: "apple", name: "Apple M2 Max", utilization: 50, renderer: 50, tiler: 50, memoryUsed: nil, coreCount: 38)
        let integrated = GPUActivitySampler.applying(0, to: [apple])
        precondition(integrated[0].utilization == 0 && integrated[0].utilizationSource == .interval)
        precondition(integrated[0].renderer == 50 && integrated[0].tiler == 50)
        precondition(GPUActivitySampler.applying(nil, to: [apple])[0].utilization == 50)
        precondition(GPUActivitySampler.applying(101, to: [apple])[0].utilization == 50)
        precondition(GPUActivitySampler.applying(10, to: [apple, apple]).allSatisfy { $0.utilization == 50 })
        var interval = chartSample("apple")
        interval.gpus = GPUActivitySampler.applying(25, to: [apple])
        let cachedInterval = merge(interval, SystemMetrics(), 200)
        let staleInterval = merge(SystemMetrics(), cachedInterval, 202)
        precondition(staleInterval.gpus.first?.utilizationSource == .interval)
        store.recordGPUHistory(fresh: interval, selected: interval.gpus.first, source: "auto")
        var driver = interval
        driver.gpus = [apple]
        store.recordGPUHistory(fresh: driver, selected: apple, source: "auto")
        precondition(store.gpuHistory == [50], "Different measurement definitions must not share a trace")
        if let activity = GPUActivitySampler() {
            activity.begin()
            Thread.sleep(forTimeInterval: 0.2)
            let value = activity.finish()
            precondition(value.map { (0...100).contains($0) } ?? true)
            print("Live GPU interval active percent: \(String(describing: value))")
        }
        typealias Client = GPUProcessSampler.Client
        typealias Snapshot = GPUProcessSampler.Snapshot
        func client(_ id: UInt64 = 1, _ pid: Int32 = 100, _ times: [UInt64]) -> Client {
            Client(id: id, pid: pid, name: "test", queueTimes: times)
        }
        let processStart = Snapshot(time: 1, devices: ["A": [client(1, 100, [0, 10]), client(2, 100, [0]), client(3, 200, [20])],
                                                       "B": [client(4, 100, [0])]])
        let processEnd = Snapshot(time: 2, devices: ["A": [client(1, 100, [500_000_000, 10]), client(2, 100, [250_000_000]), client(3, 200, [1_500_000_020])],
                                                     "B": [client(4, 100, [100_000_000])]])
        let rates = GPUProcessSampler.usage(from: processStart, to: processEnd)
        precondition(rates["A"]?.map(\.id) == [200, 100])
        precondition(rates["A"]?.map(\.gpuPercent) == [150, 75], "Overlapping GPU execution must not be capped or normalized")
        precondition(rates["B"]?.first?.gpuPercent == 10, "Keep device attribution separate")
        let changed = Snapshot(time: 3, devices: ["A": [client(1, 999, [9_000_000_000]), client(2, 100, [1]), client(3, 200, [1_600_000_020, 0]), client(9, 300, [9_000_000_000])]])
        precondition(GPUProcessSampler.usage(from: processEnd, to: changed)["A"]?.isEmpty == true,
                     "PID reuse, resets, queue changes, and new clients must not produce spikes")
        precondition(GPUProcessSampler.usage(from: processEnd, to: Snapshot(time: 3, devices: [:])).isEmpty)
        precondition(GPUProcessSampler.usage(from: processStart, to: processStart).isEmpty)
        precondition(GPUProcessSampler.usage(from: Snapshot(time: 0, devices: [:]), to: processEnd).isEmpty)
        precondition(GPUProcessSampler.owner("pid 123, WindowServer")?.pid == 123)
        precondition(GPUProcessSampler.owner("pid 123, WindowServer")?.name == "WindowServer")
        precondition(GPUProcessSampler.owner("pid 0, invalid") == nil)
        precondition(GPUProcessSampler.owner("invalid") == nil)
        precondition(legacy.shows(.gpuProcesses))
        let processLiveStart = GPUProcessSampler.snapshot()
        Thread.sleep(forTimeInterval: 1)
        let liveProcesses = GPUProcessSampler.resolveNames(GPUProcessSampler.usage(from: processLiveStart, to: GPUProcessSampler.snapshot()))
        for (device, processes) in liveProcesses {
            precondition(processes.allSatisfy { $0.gpuPercent.isFinite && $0.gpuPercent >= 0 })
            print("GPU process clients on \(device): \(processes.count)")
            for process in processes.prefix(5) { print("  PID \(process.id) \(process.name): \(process.gpuPercent)%") }
        }
        // Exercise the real AGX attribution path with work owned by this test process.
        if !liveProcesses.isEmpty, let device = MTLCreateSystemDefaultDevice(),
           let queue = device.makeCommandQueue() {
            let library = try device.makeLibrary(source: """
                #include <metal_stdlib>
                using namespace metal;
                kernel void work(device float *output [[buffer(0)]], uint id [[thread_position_in_grid]]) {
                    float value = float(id) + 1.0f;
                    for (uint i = 0; i < 2048; ++i) { value = sqrt(value + float(i) + 1.0f); }
                    output[id] = value;
                }
                """, options: nil)
            let pipeline = try device.makeComputePipelineState(function: library.makeFunction(name: "work")!)
            let buffer = device.makeBuffer(length: 32768 * MemoryLayout<Float>.size, options: .storageModeShared)!
            func runMetalWork() {
                let command = queue.makeCommandBuffer()!
                let encoder = command.makeComputeCommandEncoder()!
                encoder.setComputePipelineState(pipeline)
                encoder.setBuffer(buffer, offset: 0, index: 0)
                encoder.dispatchThreads(MTLSize(width: 32768, height: 1, depth: 1), threadsPerThreadgroup: MTLSize(width: 256, height: 1, depth: 1))
                encoder.endEncoding()
                command.commit()
                command.waitUntilCompleted()
                precondition(command.status == .completed)
            }
            runMetalWork() // Establish this queue before measuring it.
            let workloadStart = GPUProcessSampler.snapshot()
            let until = ProcessInfo.processInfo.systemUptime + 0.6
            repeat { runMetalWork() } while ProcessInfo.processInfo.systemUptime < until
            Thread.sleep(forTimeInterval: 0.1)
            let measured = GPUProcessSampler.usage(from: workloadStart, to: GPUProcessSampler.snapshot())
            let ownUsage = measured.values.flatMap { $0 }.filter { $0.id == getpid() }.reduce(0) { $0 + $1.gpuPercent }
            precondition(ownUsage > 0, "The known Metal workload must be attributed to its owning PID")
            print("Known Metal workload attributed to test PID: \(ownUsage)%")
        }
        let live = GPUSampler.sample() ?? []
        for gpu in live {
            print("Live GPU: \(gpu.name), usage=\(String(describing: gpu.utilization)), memory=\(String(describing: gpu.memoryUsed)), cores=\(String(describing: gpu.coreCount))")
        }
        store.stop()
        if !liveProcesses.isEmpty, PreferencesStore.shared.values.shows(.gpuProcesses) {
            let opening = MonitorStore(startSampling: false)
            opening.refresh() // An ordinary sample is already in flight when the panel opens.
            opening.setDetail(.gpu)
            precondition(opening.gpuProcessesLoading)
            let deadline = Date().addingTimeInterval(5)
            while opening.gpuProcessesLoading && Date() < deadline {
                RunLoop.current.run(until: Date().addingTimeInterval(0.05))
            }
            precondition(!opening.gpuProcessesLoading && !opening.metrics.gpuProcesses.isEmpty,
                         "Opening the GPU panel during an ordinary sample must trigger process sampling")
            opening.setDetail(nil)
            precondition(opening.metrics.gpuProcesses.isEmpty, "Closing the panel must discard old process attribution")
            opening.stop()
        }
        print("GPU validation passed: missing/invalid readings, zero, expiry, device isolation/removal, legacy preferences, three histories, independent gaps, source changes, 60-sample limit, GPU process deltas/resets/PID reuse/device isolation, live Metal attribution")
    }
}
