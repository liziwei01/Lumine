import AppKit
import Foundation

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
        let live = GPUSampler.sample() ?? []
        for gpu in live {
            print("Live GPU: \(gpu.name), usage=\(String(describing: gpu.utilization)), memory=\(String(describing: gpu.memoryUsed)), cores=\(String(describing: gpu.coreCount))")
        }
        store.stop()
        print("GPU validation passed: missing/invalid readings, zero, expiry, device isolation/removal, legacy preferences, three histories, independent gaps, source changes, 60-sample limit, live sampling")
    }
}
