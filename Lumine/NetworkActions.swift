import AppKit
import Combine
import Darwin
import Foundation

private struct TrafficBucket: Codable {
    var minute: Int64
    var interface: String
    var download: UInt64
    var upload: UInt64
}

@MainActor
final class TrafficHistoryStore {
    private var buckets: [TrafficBucket] = []
    private let fileURL: URL
    private var lastSavedMinute: Int64 = -1

    init(fileURL: URL? = nil) {
        let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Lumine", isDirectory: true)
        self.fileURL = fileURL ?? folder.appendingPathComponent("network-traffic.json")
        if let data = try? Data(contentsOf: self.fileURL),
           let decoded = try? JSONDecoder().decode([TrafficBucket].self, from: data) {
            buckets = decoded
            prune(now: Date())
        }
    }

    func record(interface: String, download: UInt64, upload: UInt64, at date: Date = Date()) {
        guard !interface.isEmpty, download > 0 || upload > 0 else { return }
        let minute = Int64(date.timeIntervalSince1970 / 60)
        if let index = buckets.lastIndex(where: { $0.minute == minute && $0.interface == interface }) {
            buckets[index].download = adding(buckets[index].download, download)
            buckets[index].upload = adding(buckets[index].upload, upload)
        } else {
            buckets.append(TrafficBucket(minute: minute, interface: interface, download: download, upload: upload))
        }
        prune(now: date)
        if lastSavedMinute != minute {
            lastSavedMinute = minute
            flush()
        }
    }

    func totals(interface: String, minutes: Int, now: Date = Date()) -> (download: UInt64, upload: UInt64) {
        let cutoff = Int64((now.timeIntervalSince1970 - Double(minutes * 60)) / 60)
        var download: UInt64 = 0
        var upload: UInt64 = 0
        for bucket in buckets where bucket.interface == interface && bucket.minute >= cutoff {
            download = adding(download, bucket.download)
            upload = adding(upload, bucket.upload)
        }
        return (download, upload)
    }

    func flush() {
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(buckets).write(to: fileURL, options: .atomic)
        } catch {
            // Traffic history is optional; live rates continue even if persistence fails.
        }
    }

    private func prune(now: Date) {
        let oldest = Int64((now.timeIntervalSince1970 - 24 * 3600) / 60)
        buckets.removeAll { $0.minute < oldest }
    }

    private func adding(_ lhs: UInt64, _ rhs: UInt64) -> UInt64 {
        lhs > UInt64.max - rhs ? UInt64.max : lhs + rhs
    }
}

@MainActor
final class SpeedTestStore: ObservableObject {
    static let shared = SpeedTestStore()

    enum Phase: String {
        case idle, download, upload, finished, failed
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var downloadMbps: Double?
    @Published private(set) var uploadMbps: Double?
    @Published private(set) var errorMessage: String?
    private var task: Task<Void, Never>?
    private var session: URLSession?
    private var generation = 0

    func start() {
        cancel()
        downloadMbps = nil
        uploadMbps = nil
        errorMessage = nil
        phase = .download
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 25
        configuration.timeoutIntervalForResource = 45
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        let session = URLSession(configuration: configuration)
        self.session = session
        let currentGeneration = generation
        task = Task { [weak self] in
            guard let self else { return }
            do {
                _ = try await self.download(bytes: 100_000, using: session)
                let down = try await self.download(bytes: 20_000_000, using: session)
                try Task.checkCancellation()
                guard self.generation == currentGeneration else { return }
                self.downloadMbps = down
                self.phase = .upload
                let up = try await self.upload(bytes: 8_000_000, using: session)
                try Task.checkCancellation()
                guard self.generation == currentGeneration else { return }
                self.uploadMbps = up
                self.phase = .finished
            } catch is CancellationError {
                if self.generation == currentGeneration { self.phase = .idle }
            } catch {
                if !Task.isCancelled && self.generation == currentGeneration {
                    self.errorMessage = error.localizedDescription
                    self.phase = .failed
                }
            }
            session.finishTasksAndInvalidate()
            if self.generation == currentGeneration {
                self.session = nil
                self.task = nil
            }
        }
    }

    func cancel() {
        generation += 1
        task?.cancel()
        session?.invalidateAndCancel()
        task = nil
        session = nil
        if phase == .download || phase == .upload { phase = .idle }
    }

    private func download(bytes: Int, using session: URLSession) async throws -> Double {
        let url = URL(string: "https://speed.cloudflare.com/__down?bytes=\(bytes)&r=\(UUID().uuidString)")!
        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        let start = ProcessInfo.processInfo.systemUptime
        let (data, response) = try await session.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200, data.count >= bytes else {
            throw URLError(.badServerResponse)
        }
        return Double(data.count) * 8 / max(ProcessInfo.processInfo.systemUptime - start, 0.001) / 1_000_000
    }

    private func upload(bytes: Int, using session: URLSession) async throws -> Double {
        let url = URL(string: "https://speed.cloudflare.com/__up")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        let payload = Data(repeating: 0xA5, count: bytes)
        let start = ProcessInfo.processInfo.systemUptime
        let (_, response) = try await session.upload(for: request, from: payload)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        return Double(bytes) * 8 / max(ProcessInfo.processInfo.systemUptime - start, 0.001) / 1_000_000
    }
}

enum ProcessCloser {
    static func close(_ target: ProcessUsage) -> String? {
        guard target.id > 1, target.id != getpid() else { return L10n.tr("无法关闭这个进程。") }
        let inspector = Process()
        inspector.executableURL = URL(fileURLWithPath: "/bin/ps")
        inspector.arguments = ["-ww", "-p", String(target.id), "-o", "comm="]
        let output = Pipe()
        inspector.standardOutput = output
        inspector.standardError = Pipe()
        do {
            try inspector.run()
            let data = output.fileHandleForReading.readDataToEndOfFile()
            inspector.waitUntilExit()
            guard inspector.terminationStatus == 0,
                  let command = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
                  command == target.commandPath else { return L10n.tr("进程已退出或身份发生变化，请刷新排行。") }
        } catch {
            return L10n.tr("无法确认进程身份：\(error.localizedDescription)")
        }
        if let application = NSRunningApplication(processIdentifier: target.id) {
            return application.terminate() ? nil : L10n.tr("应用未接受退出请求。")
        }
        return kill(target.id, SIGTERM) == 0 ? nil : L10n.tr("无法关闭进程：\(String(cString: strerror(errno)))")
    }
}
