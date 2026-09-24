import Combine
import Foundation

struct DiskDiagnostics {
    var smartStatus: String?
    var healthPercent: Int?
    var temperatureCelsius: Double?
    var availableSpare: Int?
    var availableSpareThreshold: Int?

    var healthLabel: String {
        if smartStatus == "Failing" || spareIsCritical { return "严重" }
        if let healthPercent { return healthPercent < 70 ? "警告" : "良好" }
        return smartStatus == "Verified" ? "正常" : "不可用"
    }

    var healthMessage: String {
        switch healthLabel {
        case "严重": L10n.tr("磁盘报告严重问题，请尽快备份数据。")
        case "警告": L10n.tr("磁盘运行资源减少，建议定期备份。")
        case "良好": L10n.tr("此驱动器状态良好，不过已经开始逐渐老化。")
        case "正常": L10n.tr("SMART 状态正常，但此磁盘未提供寿命百分比。")
        default: L10n.tr("当前无法获取此磁盘的健康数据。")
        }
    }

    var temperatureMessage: String {
        guard let temperatureCelsius else { return L10n.tr("当前无法获取此磁盘的温度。") }
        if temperatureCelsius >= 71 { return L10n.tr("磁盘温度过高，请尽快让设备降温。") }
        if temperatureCelsius >= 51 { return L10n.tr("磁盘开始升温，建议注意散热。") }
        return L10n.tr("当前温度在理想工作范围内。")
    }

    private var spareIsCritical: Bool {
        guard let availableSpare, let availableSpareThreshold else { return false }
        return availableSpare < availableSpareThreshold
    }

    static func parse(_ plist: [String: Any]) -> DiskDiagnostics {
        var result = DiskDiagnostics()
        result.smartStatus = plist["SMARTStatus"] as? String
        let fields = plist["SMARTDeviceSpecificKeysMayVaryNotGuaranteed"] as? [String: Any] ?? [:]
        if let used = (fields["PERCENTAGE_USED"] as? NSNumber)?.intValue, used >= 0 {
            result.healthPercent = max(0, min(100, 100 - used))
        }
        result.availableSpare = (fields["AVAILABLE_SPARE"] as? NSNumber)?.intValue
        result.availableSpareThreshold = (fields["AVAILABLE_SPARE_THRESHOLD"] as? NSNumber)?.intValue
        if let raw = (fields["TEMPERATURE"] as? NSNumber)?.doubleValue {
            let celsius = raw > 200 ? raw - 273.15 : raw
            if (0...120).contains(celsius) { result.temperatureCelsius = celsius }
        }
        return result
    }
}

struct TrashUsage {
    var bytes: UInt64 = 0
    var unreadable = 0
}

struct TrashEmptyResult {
    var removed = 0
    var failed = 0
}

enum DiskSupplementCollector {
    static func diagnostics(path: String) -> DiskDiagnostics {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/diskutil")
        process.arguments = ["info", "-plist", path]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = Pipe()
        do {
            try process.run()
            let data = output.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            guard process.terminationStatus == 0,
                  let plist = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
                return DiskDiagnostics()
            }
            return .parse(plist)
        } catch {
            return DiskDiagnostics()
        }
    }

    static func trashURL(path: String) -> URL {
        if path == "/" {
            return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".Trash", isDirectory: true)
        }
        return URL(fileURLWithPath: path, isDirectory: true)
            .appendingPathComponent(".Trashes/\(getuid())", isDirectory: true)
    }

    static func trash(path: String, cancelled: () -> Bool) -> TrashUsage {
        let trashURL = trashURL(path: path)
        var result = TrashUsage()
        if !FileManager.default.fileExists(atPath: trashURL.path) { return result }
        let keys: [URLResourceKey] = [.isRegularFileKey, .totalFileAllocatedSizeKey, .fileAllocatedSizeKey, .fileSizeKey]
        guard let enumerator = FileManager.default.enumerator(at: trashURL, includingPropertiesForKeys: keys, errorHandler: { _, _ in
            result.unreadable += 1
            return true
        }) else {
            result.unreadable += 1
            return result
        }
        for case let url as URL in enumerator {
            if cancelled() { break }
            guard let values = try? url.resourceValues(forKeys: Set(keys)), values.isRegularFile == true else { continue }
            result.bytes += UInt64(max(0, values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? values.fileSize ?? 0))
        }
        return result
    }

    static func emptyTrash(at trashURL: URL) -> TrashEmptyResult {
        var result = TrashEmptyResult()
        guard let contents = try? FileManager.default.contentsOfDirectory(at: trashURL, includingPropertiesForKeys: nil) else {
            result.failed = FileManager.default.fileExists(atPath: trashURL.path) ? 1 : 0
            return result
        }
        for item in contents {
            do {
                try FileManager.default.removeItem(at: item)
                result.removed += 1
            } catch {
                result.failed += 1
            }
        }
        return result
    }
}

@MainActor
final class DiskSupplementStore: ObservableObject {
    static let shared = DiskSupplementStore()

    @Published private(set) var diagnostics = DiskDiagnostics()
    @Published private(set) var trash = TrashUsage()
    @Published private(set) var isLoading = false
    @Published private(set) var isEmptyingTrash = false
    @Published private var trashOutcome: TrashEmptyResult?
    var trashNotice: String? {
        guard let trashOutcome else { return nil }
        return trashOutcome.failed == 0
            ? L10n.tr("已清空 \(trashOutcome.removed) 项。")
            : L10n.tr("已清空 \(trashOutcome.removed) 项，\(trashOutcome.failed) 项未能删除。")
    }
    private var rootPath = ""
    private var collectedDiagnostics = false
    private var collectedTrash = false
    private var lastUpdate: Date?
    private var task: Task<Void, Never>?
    private var generation = 0

    func refresh(path: String, diagnostics includeDiagnostics: Bool, trash includeTrash: Bool, force: Bool = false) {
        if !force && rootPath == path && collectedDiagnostics == includeDiagnostics && collectedTrash == includeTrash &&
            (isLoading || lastUpdate.map { Date().timeIntervalSince($0) < 60 } == true) { return }
        cancel()
        rootPath = path
        trashOutcome = nil
        collectedDiagnostics = includeDiagnostics
        collectedTrash = includeTrash
        diagnostics = DiskDiagnostics()
        trash = TrashUsage()
        isLoading = true
        let currentGeneration = generation
        task = Task.detached(priority: .utility) { [weak self] in
            let diagnostics = includeDiagnostics ? DiskSupplementCollector.diagnostics(path: path) : DiskDiagnostics()
            let trash = includeTrash ? DiskSupplementCollector.trash(path: path, cancelled: { Task.isCancelled }) : TrashUsage()
            await MainActor.run { [weak self] in
                guard let self, self.generation == currentGeneration else { return }
                self.diagnostics = diagnostics
                self.trash = trash
                self.isLoading = false
                self.lastUpdate = Date()
                self.task = nil
            }
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
        generation += 1
        isLoading = false
    }

    func emptyTrash(path: String) {
        guard !isEmptyingTrash else { return }
        isEmptyingTrash = true
        trashOutcome = nil
        let url = DiskSupplementCollector.trashURL(path: path)
        Task.detached(priority: .utility) { [weak self] in
            let outcome = DiskSupplementCollector.emptyTrash(at: url)
            let current = DiskSupplementCollector.trash(path: path, cancelled: { false })
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.isEmptyingTrash = false
                if self.rootPath == path { self.trash = current }
                self.trashOutcome = outcome
            }
        }
    }
}
