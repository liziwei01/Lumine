import Combine
import Foundation

enum DiskCategory: String, CaseIterable, Identifiable, Codable {
    case documents = "文稿"
    case applications = "应用程序"
    case desktop = "桌面"
    case downloads = "下载"
    case other = "其他"

    var localizedName: String { L10n.lookup(rawValue) }

    var id: String { rawValue }

    static func category(for path: String, root: String) -> DiskCategory {
        let relative = root == "/" ? path : String(path.dropFirst(root.count))
        let parts = relative.split(separator: "/").map(String.init)
        guard !parts.isEmpty else { return .other }
        if root != "/" {
            switch parts[0] {
            case "Documents": return .documents
            case "Applications": return .applications
            case "Desktop": return .desktop
            case "Downloads": return .downloads
            default: return .other
            }
        }
        if parts[0] == "Applications" || (parts.count >= 2 && parts[0] == "System" && parts[1] == "Applications") ||
            (parts.count >= 3 && parts[0] == "Users" && parts[2] == "Applications") { return .applications }
        if parts.count >= 3 && parts[0] == "Users" {
            switch parts[2] {
            case "Documents": return .documents
            case "Desktop": return .desktop
            case "Downloads": return .downloads
            default: break
            }
        }
        return .other
    }
}

struct DiskScanResult: Codable {
    var bytes: [DiskCategory: UInt64] = [:]
    var files = 0
    var unreadable = 0
    var fallbackSizes = 0
    var finished = false

    func size(_ category: DiskCategory) -> UInt64 { bytes[category] ?? 0 }
    var total: UInt64 { bytes.values.reduce(0, +) }
}

private struct DiskCategoryCacheEntry: Codable {
    var completed: Date
    var result: DiskScanResult
}

enum DiskCategoryScanner {
    static func scan(root: URL, cancelled: () -> Bool, progress: (DiskScanResult) -> Void) -> DiskScanResult {
        var result = DiskScanResult()
        let path = root.withUnsafeFileSystemRepresentation { representation -> String? in
            guard let representation, let resolved = realpath(representation, nil) else { return nil }
            defer { free(resolved) }
            return String(cString: resolved)
        } ?? root.standardizedFileURL.path
        let resolvedRoot = URL(fileURLWithPath: path, isDirectory: true)
        let keys: [URLResourceKey] = [.isRegularFileKey, .isDirectoryKey, .totalFileAllocatedSizeKey, .fileAllocatedSizeKey, .fileSizeKey]
        let keySet = Set(keys)
        guard let enumerator = FileManager.default.enumerator(at: resolvedRoot, includingPropertiesForKeys: keys, options: [], errorHandler: { _, _ in
            result.unreadable += 1
            return true
        }) else {
            result.unreadable += 1
            progress(result)
            return result
        }
        var lastUpdate = ProcessInfo.processInfo.systemUptime
        var examined = 0
        while !cancelled(), let url = enumerator.nextObject() as? URL {
            examined += 1
            let itemPath = url.path
            if path == "/" && (itemPath == "/System/Volumes" || itemPath == "/Volumes" || itemPath == "/Network" || itemPath == "/dev") {
                enumerator.skipDescendants()
                continue
            }
            do {
                let values = try url.resourceValues(forKeys: keySet)
                guard values.isRegularFile == true else { continue }
                var size = values.totalFileAllocatedSize ?? values.fileAllocatedSize
                if size == nil {
                    size = values.fileSize
                    result.fallbackSizes += 1
                }
                guard let size else {
                    result.unreadable += 1
                    continue
                }
                let category = DiskCategory.category(for: itemPath, root: path)
                result.bytes[category, default: 0] += UInt64(max(0, size))
                result.files += 1
            } catch {
                result.unreadable += 1
            }
            if examined.isMultiple(of: 256) {
                let now = ProcessInfo.processInfo.systemUptime
                if now - lastUpdate >= 0.5 {
                    progress(result)
                    lastUpdate = now
                }
                if examined.isMultiple(of: 512) { Thread.sleep(forTimeInterval: 0.002) }
            }
        }
        result.finished = !cancelled()
        progress(result)
        return result
    }
}

@MainActor
final class DiskCategoryStore: ObservableObject {
    static let shared = DiskCategoryStore()

    @Published private(set) var result = DiskScanResult()
    @Published private(set) var scanProgress = DiskScanResult()
    @Published private(set) var isScanning = false
    @Published private(set) var rootPath = ""
    @Published private(set) var lastCompleted: Date?

    private let cacheURL: URL
    private var cache: [String: DiskCategoryCacheEntry] = [:]
    private var task: Task<Void, Never>?
    private var generation = 0
    private var enabled = false

    init(cacheURL: URL? = nil) {
        let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Lumine", isDirectory: true)
        self.cacheURL = cacheURL ?? folder.appendingPathComponent("disk-categories.json")
        if let data = try? Data(contentsOf: self.cacheURL),
           let saved = try? JSONDecoder().decode([String: DiskCategoryCacheEntry].self, from: data) {
            cache = saved
        }
    }

    func configure(path: String, enabled: Bool) {
        let normalizedPath = path == "startup" ? "/" : path
        if rootPath != normalizedPath {
            cancel()
            rootPath = normalizedPath
            result = cache[normalizedPath]?.result ?? DiskScanResult()
            lastCompleted = cache[normalizedPath]?.completed
            scanProgress = DiskScanResult()
        }
        self.enabled = enabled
        if !enabled { cancel() }
    }

    func scanNow() {
        guard enabled, !rootPath.isEmpty,
              FileManager.default.fileExists(atPath: rootPath) else { return }
        cancel()
        beginScan()
    }

    private func beginScan() {
        scanProgress = DiskScanResult()
        isScanning = true
        generation += 1
        let currentGeneration = generation
        let path = rootPath
        let url = URL(fileURLWithPath: path, isDirectory: true)
        task = Task.detached(priority: .utility) { [weak self] in
            let finalResult = DiskCategoryScanner.scan(root: url, cancelled: { Task.isCancelled }) { partial in
                Task { @MainActor [weak self] in
                    guard let self, self.generation == currentGeneration else { return }
                    self.scanProgress = partial
                    if self.lastCompleted == nil { self.result = partial }
                }
            }
            await MainActor.run { [weak self] in
                guard let self, self.generation == currentGeneration else { return }
                self.isScanning = false
                self.task = nil
                if finalResult.finished {
                    let completed = Date()
                    self.result = finalResult
                    self.lastCompleted = completed
                    self.cache[path] = DiskCategoryCacheEntry(completed: completed, result: finalResult)
                    self.saveCache()
                } else if self.lastCompleted == nil {
                    self.result = DiskScanResult()
                }
                self.generation += 1
            }
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
        generation += 1
        isScanning = false
        scanProgress = DiskScanResult()
        if lastCompleted == nil { result = DiskScanResult() }
    }

    func stop() {
        cancel()
    }

    private func saveCache() {
        do {
            try FileManager.default.createDirectory(at: cacheURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(cache).write(to: cacheURL, options: .atomic)
        } catch {
            // The completed result remains available in memory for this run.
        }
    }
}
