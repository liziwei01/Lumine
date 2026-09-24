import Foundation
import IOKit

struct TemperatureReading {
    let key: String
    let name: String
    let celsius: Double
}

/// Read-only AppleSMC client. The SMC ABI and model key maps are not public macOS APIs.
/// See THIRD_PARTY_NOTICES.md for the sources used to identify the protocol and keys.
final class SMCReader {
    private typealias Bytes = (
        UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
        UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
        UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
        UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8
    )
    private struct Version {
        var major: UInt8 = 0
        var minor: UInt8 = 0
        var build: UInt8 = 0
        var reserved: UInt8 = 0
        var release: UInt16 = 0
    }
    private struct PowerLimits {
        var version: UInt16 = 0
        var length: UInt16 = 0
        var cpu: UInt32 = 0
        var gpu: UInt32 = 0
        var memory: UInt32 = 0
    }
    private struct KeyInfo {
        var size: UInt32 = 0
        var type: UInt32 = 0
        var attributes: UInt8 = 0
    }
    private struct Packet {
        var key: UInt32 = 0
        var version = Version()
        var limits = PowerLimits()
        var info = KeyInfo()
        var padding: UInt16 = 0
        var result: UInt8 = 0
        var status: UInt8 = 0
        var command: UInt8 = 0
        var data32: UInt32 = 0
        var bytes: Bytes = (
            0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
            0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
        )
    }

    private var connection: io_connect_t = 0

    init?() {
        guard MemoryLayout<Packet>.stride == 80 else { return nil }
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
        guard service != IO_OBJECT_NULL else { return nil }
        let result = IOServiceOpen(service, mach_task_self_, 0, &connection)
        IOObjectRelease(service)
        guard result == kIOReturnSuccess, connection != 0 else { return nil }
    }

    deinit { close() }

    func close() {
        if connection != 0 {
            IOServiceClose(connection)
            connection = 0
        }
    }

    func cpuTemperatures(model: String) -> [TemperatureReading] {
        let entries = Self.keys(for: model)
        return entries.compactMap { key, name in
            guard let value = readTemperature(key), value > 10, value < 120 else { return nil }
            return TemperatureReading(key: key, name: name, celsius: value)
        }
    }

    private func readTemperature(_ key: String) -> Double? {
        var request = Packet()
        request.key = Self.fourCC(key)
        request.command = 9 // read key information
        guard let metadata = call(request), metadata.info.size > 0, metadata.info.size <= 32 else { return nil }
        request = Packet()
        request.key = Self.fourCC(key)
        request.info.size = metadata.info.size
        request.command = 5 // read bytes; this client never writes SMC keys
        guard let response = call(request) else { return nil }
        let bytes = withUnsafeBytes(of: response.bytes) { Array($0) }
        switch Self.string(from: metadata.info.type) {
        case "flt ":
            let raw = UInt32(bytes[0]) | (UInt32(bytes[1]) << 8) | (UInt32(bytes[2]) << 16) | (UInt32(bytes[3]) << 24)
            let result = Double(Float(bitPattern: raw))
            return result.isFinite ? result : nil
        case "sp78":
            let raw = Int16(bitPattern: (UInt16(bytes[0]) << 8) | UInt16(bytes[1]))
            return Double(raw) / 256
        default:
            return nil
        }
    }

    private func call(_ input: Packet) -> Packet? {
        guard connection != 0 else { return nil }
        var input = input
        var output = Packet()
        var outputSize = MemoryLayout<Packet>.stride
        let status = IOConnectCallStructMethod(connection, 2, &input, MemoryLayout<Packet>.stride, &output, &outputSize)
        guard status == kIOReturnSuccess, output.result == 0, outputSize == MemoryLayout<Packet>.stride else { return nil }
        return output
    }

    private static func fourCC(_ value: String) -> UInt32 {
        value.utf8.prefix(4).reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
    }

    private static func string(from value: UInt32) -> String {
        String(bytes: [UInt8((value >> 24) & 0xFF), UInt8((value >> 16) & 0xFF), UInt8((value >> 8) & 0xFF), UInt8(value & 0xFF)], encoding: .ascii) ?? ""
    }

    private static func keys(for model: String) -> [(String, String)] {
        if model.contains("Apple M1") {
            return [
                ("Tp09", "能效核心 1"), ("Tp0T", "能效核心 2"),
                ("Tp01", "性能核心 1"), ("Tp05", "性能核心 2"), ("Tp0D", "性能核心 3"), ("Tp0H", "性能核心 4"),
                ("Tp0L", "性能核心 5"), ("Tp0P", "性能核心 6"), ("Tp0X", "性能核心 7"), ("Tp0b", "性能核心 8")
            ]
        }
        if model.contains("Apple M2") {
            return [
                ("Tp1h", "能效核心 1"), ("Tp1t", "能效核心 2"), ("Tp1p", "能效核心 3"), ("Tp1l", "能效核心 4"),
                ("Tp01", "性能核心 1"), ("Tp05", "性能核心 2"), ("Tp09", "性能核心 3"), ("Tp0D", "性能核心 4"),
                ("Tp0X", "性能核心 5"), ("Tp0b", "性能核心 6"), ("Tp0f", "性能核心 7"), ("Tp0j", "性能核心 8")
            ]
        }
        if model.contains("Apple M3") {
            return [
                ("Te05", "能效核心 1"), ("Te0L", "能效核心 2"), ("Te0P", "能效核心 3"), ("Te0S", "能效核心 4"),
                ("Tf04", "性能核心 1"), ("Tf09", "性能核心 2"), ("Tf0A", "性能核心 3"), ("Tf0B", "性能核心 4"),
                ("Tf0D", "性能核心 5"), ("Tf0E", "性能核心 6"), ("Tf44", "性能核心 7"), ("Tf49", "性能核心 8"),
                ("Tf4A", "性能核心 9"), ("Tf4B", "性能核心 10"), ("Tf4D", "性能核心 11"), ("Tf4E", "性能核心 12")
            ]
        }
        if model.contains("Apple M4") {
            return [
                ("Te05", "能效核心 1"), ("Te0S", "能效核心 2"), ("Te09", "能效核心 3"), ("Te0H", "能效核心 4"),
                ("Tp01", "性能核心 1"), ("Tp05", "性能核心 2"), ("Tp09", "性能核心 3"), ("Tp0D", "性能核心 4"),
                ("Tp0V", "性能核心 5"), ("Tp0Y", "性能核心 6"), ("Tp0b", "性能核心 7"), ("Tp0e", "性能核心 8")
            ]
        }
        if model.contains("Apple M5") {
            return [
                ("Tp00", "超级核心 1"), ("Tp04", "超级核心 2"), ("Tp08", "超级核心 3"), ("Tp0C", "超级核心 4"),
                ("Tp0G", "超级核心 5"), ("Tp0K", "超级核心 6"),
                ("Tp0O", "性能核心 1"), ("Tp0R", "性能核心 2"), ("Tp0U", "性能核心 3"), ("Tp0X", "性能核心 4"),
                ("Tp0a", "性能核心 5"), ("Tp0d", "性能核心 6"), ("Tp0g", "性能核心 7"), ("Tp0j", "性能核心 8"),
                ("Tp0m", "性能核心 9"), ("Tp0p", "性能核心 10"), ("Tp0u", "性能核心 11"), ("Tp0y", "性能核心 12")
            ]
        }
        return [("TC0D", "CPU 二极管"), ("TC0F", "CPU 晶片")]
    }
}
