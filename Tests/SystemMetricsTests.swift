import Foundation

@main
struct SystemMetricsTests {
    @MainActor static func main() throws {
        var metrics = SystemMetrics()
        metrics.memoryTotal = 1000
        metrics.memoryFree = 10
        metrics.memoryActive = 800
        metrics.memoryWired = 100
        metrics.memoryCompressed = 50
        precondition(metrics.memoryPressureEstimate == 15, "Reclaimable memory must not inflate pressure")
        metrics.memoryTotal = 0
        precondition(metrics.memoryPressureEstimate == 0)
        metrics.memoryTotal = 100
        precondition(metrics.memoryPressureEstimate == 100)

        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        let trash = root.appendingPathComponent("Trash")
        let absent = DiskSupplementCollector.scanTrash(at: trash, cancelled: { false })
        precondition(absent.isAccessible && absent.isComplete && absent.itemCount == 0)
        try fm.createDirectory(at: trash, withIntermediateDirectories: true)
        try Data().write(to: trash.appendingPathComponent("zero"))
        try fm.createDirectory(at: trash.appendingPathComponent("empty"), withIntermediateDirectories: true)
        let outside = root.appendingPathComponent("outside")
        try Data("keep".utf8).write(to: outside)
        try fm.createSymbolicLink(at: trash.appendingPathComponent("link"), withDestinationURL: outside)
        let usage = DiskSupplementCollector.scanTrash(at: trash, cancelled: { false })
        precondition(usage.isAccessible && usage.isComplete && usage.itemCount == 3 && usage.bytes == 0)
        precondition(!DiskSupplementCollector.scanTrash(at: trash, cancelled: { true }).isComplete)
        let emptied = DiskSupplementCollector.emptyTrash(at: trash)
        precondition(emptied.removed == 3 && emptied.failed == 0)
        let preserved = try Data(contentsOf: outside)
        precondition(preserved == Data("keep".utf8))
        // A non-directory is a read failure, never a successful empty operation.
        precondition(DiskSupplementCollector.emptyTrash(at: outside).failed == 1)
        let denied = root.appendingPathComponent("denied")
        try fm.createDirectory(at: denied, withIntermediateDirectories: true)
        try fm.setAttributes([.posixPermissions: 0], ofItemAtPath: denied.path)
        let blocked = DiskSupplementCollector.scanTrash(at: denied, cancelled: { false })
        precondition(!blocked.isAccessible && !blocked.isComplete)
        precondition(DiskSupplementCollector.emptyTrash(at: denied).failed == 1)
        try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: denied.path)
        let empty = DiskSupplementCollector.scanTrash(at: trash, cancelled: { false })
        precondition(empty.isComplete && empty.itemCount == 0)

        let sampler = SystemSampler()
        defer { sampler.stop() }
        let first = sampler.sample()
        precondition(first.has(.cpu) && first.has(.cores), "First sample needs a measured CPU window")
        precondition((0...100).contains(first.cpuTotal))
        precondition(first.cpuCores.allSatisfy { (0...100).contains($0.total) })
        precondition(first.has(.memory) && first.has(.memoryPressure))
        print("Live CPU: \(first.cpuTotal)%, memory pressure estimate: \(first.memoryPressureEstimate)%, kernel level: \(String(describing: first.memoryPressureLevel))")
        print("System GPU: \(first.gpus.map { ($0.name, $0.utilization, $0.utilizationSource.rawValue) })")
        let store = MonitorStore(startSampling: false)
        let old = store.retainingRecentValues(from: first, previous: SystemMetrics(), requestedInterface: "auto", now: 100, lifetime: 5)
        let retained = store.retainingRecentValues(from: SystemMetrics(), previous: old, requestedInterface: "auto", now: 103, lifetime: 5)
        precondition(retained.memoryPressureLevel == first.memoryPressureLevel)
        let expired = store.retainingRecentValues(from: SystemMetrics(), previous: retained, requestedInterface: "auto", now: 106, lifetime: 5)
        precondition(!expired.has(.memoryPressure) && expired.memoryPressureLevel == nil)
        print("System regression tests passed: pressure, fresh CPU, trash scan/cancellation/empty, symlink safety, error reporting")
    }
}
