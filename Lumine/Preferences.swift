import AppKit
import Combine
import SwiftUI

struct BeamConfiguration: Codable, Hashable {
    var color = "#A85DEE"
    var strength = 0.25
    var topPosition = 0.45
    var bottomPosition = 0.94

    static let reference = BeamConfiguration()
}

struct ThemeConfiguration: Codable, Hashable {
    var panelTop = "#281669"
    var panelTopMiddle = "#38207E"
    var panelTopRight = "#4B2D86"
    var panelBottom = "#0A0644"
    var panelBottomMiddle = "#040438"
    var panelBottomRight = "#3B1E6B"
    var panelGlow = "#6049A5"
    var panelGlowStrength = 0.18
    var ringGlowStrength: Double? = nil
    var ringGlowRadius: Double? = nil
    var beam: BeamConfiguration? = nil
    var cardStart = "#2A1B5D"
    var cardEnd = "#523A99"
    var cardDirection = "diagonal"
    var panelBorder = "#68509A"
    var cardBorder = "#745D9E"
    var selection = "#6A85F8"
    var hoverWhitening: Double? = nil
    var selectedBlueTint: Double? = nil
    var text = "#FAF8FF"
    var muted = "#C9C4DC"
    var blue = "#7895FF"
    var cyan = "#91E3FF"
    var yellow = "#FFD332"
    var mint = "#60ECC8"
    var coral = "#FF718A"

    static let reference = ThemeConfiguration()
    var resolvedBeam: BeamConfiguration { beam ?? .reference }
    var resolvedRingGlowStrength: Double { min(1, max(0, ringGlowStrength ?? 0.7)) }
    var resolvedRingGlowRadius: Double { min(16, max(0, ringGlowRadius ?? 7)) }
    var resolvedHoverWhitening: Double { min(0.3, max(0, hoverWhitening ?? 0.10)) }
    var resolvedSelectedBlueTint: Double { min(0.3, max(0, selectedBlueTint ?? 0.15)) }

    static func points(for direction: String) -> (UnitPoint, UnitPoint) {
        switch direction {
        case "horizontal": (.leading, .trailing)
        case "reverseDiagonal": (.topTrailing, .bottomLeading)
        case "diagonal": (.topLeading, .bottomTrailing)
        default: (.top, .bottom)
        }
    }
}

struct PanelPosition: Codable, Hashable {
    let x: Double
    let y: Double
    init(_ point: NSPoint) { x = point.x; y = point.y }
    var point: NSPoint { NSPoint(x: x, y: y) }
}

enum Widget: String, CaseIterable, Identifiable {
    case health = "health"
    case overviewDisk = "overview.disk", overviewMemory = "overview.memory", overviewBattery = "overview.battery"
    case overviewGPU = "overview.gpu"
    case overviewCPU = "overview.cpu", overviewNetwork = "overview.network", overviewDevices = "overview.devices"
    case diskCategories = "disk.categories", diskHealth = "disk.health", diskTemperature = "disk.temperature"
    case diskTrash = "disk.trash", diskCapacity = "disk.capacity", diskExternal = "disk.external"
    case memoryPressure = "memory.pressure", memorySwap = "memory.swap", memoryProcesses = "memory.processes"
    case batteryHealth = "battery.health", batteryTemperature = "battery.temperature", batteryCycles = "battery.cycles", batteryProcesses = "battery.processes"
    case gpuChart = "gpu.chart", gpuMemory = "gpu.memory", gpuCores = "gpu.cores"
    case cpuChart = "cpu.chart", cpuUptime = "cpu.uptime", cpuTemperature = "cpu.temperature", cpuProcesses = "cpu.processes"
    case networkConnection = "network.connection", networkDownload = "network.download", networkUpload = "network.upload", networkSpeedTest = "network.speedtest"
    case devicesExternal = "devices.external"

    var id: String { rawValue }
    var defaultVisible: Bool { self != .diskCapacity && self != .diskExternal }
}

struct PreferencesData: Codable {
    var theme = ThemeConfiguration.reference
    var allowDragging = false
    var panelPositions: [String: PanelPosition] = [:]
    var gpuSource = "auto"
    var cpuSource = "overall"
    var temperatureSource = "average"
    var networkInterface = "auto"
    var diskSource = "startup"
    var memorySource = "available"
    var activeSamplingInterval = 5
    var idleSamplingInterval = 30
    var failedSampleRetentionSeconds = 300
    var trafficWindowMinutes = 60
    var language = "system"
    var widgetVisibility: [String: Bool] = [:]

    func shows(_ widget: Widget) -> Bool { widgetVisibility[widget.rawValue] ?? widget.defaultVisible }

    init() {}

    private enum CodingKeys: String, CodingKey {
        case theme, allowDragging, panelPositions, gpuSource, cpuSource, temperatureSource
        case networkInterface, diskSource, memorySource, activeSamplingInterval, idleSamplingInterval, failedSampleRetentionSeconds, trafficWindowMinutes, language, widgetVisibility
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        theme = try values.decodeIfPresent(ThemeConfiguration.self, forKey: .theme) ?? .reference
        if theme.selection.uppercased() == "#637CFF" { theme.selection = ThemeConfiguration.reference.selection }
        allowDragging = try values.decodeIfPresent(Bool.self, forKey: .allowDragging) ?? false
        panelPositions = try values.decodeIfPresent([String: PanelPosition].self, forKey: .panelPositions) ?? [:]
        gpuSource = try values.decodeIfPresent(String.self, forKey: .gpuSource) ?? "auto"
        cpuSource = try values.decodeIfPresent(String.self, forKey: .cpuSource) ?? "overall"
        temperatureSource = try values.decodeIfPresent(String.self, forKey: .temperatureSource) ?? "average"
        networkInterface = try values.decodeIfPresent(String.self, forKey: .networkInterface) ?? "auto"
        diskSource = try values.decodeIfPresent(String.self, forKey: .diskSource) ?? "startup"
        memorySource = try values.decodeIfPresent(String.self, forKey: .memorySource) ?? "available"
        activeSamplingInterval = max(2, try values.decodeIfPresent(Int.self, forKey: .activeSamplingInterval) ?? 5)
        idleSamplingInterval = max(10, try values.decodeIfPresent(Int.self, forKey: .idleSamplingInterval) ?? 30)
        failedSampleRetentionSeconds = min(1800, max(0, try values.decodeIfPresent(Int.self, forKey: .failedSampleRetentionSeconds) ?? 300))
        trafficWindowMinutes = min(1440, max(5, try values.decodeIfPresent(Int.self, forKey: .trafficWindowMinutes) ?? 60))
        let savedLanguage = try values.decodeIfPresent(String.self, forKey: .language) ?? "system"
        language = L10n.supported.contains(savedLanguage) ? savedLanguage : "system"
        widgetVisibility = try values.decodeIfPresent([String: Bool].self, forKey: .widgetVisibility) ?? [:]
    }
}

final class PreferencesStore: ObservableObject {
    static let shared = PreferencesStore()
    private static let key = "lumine.preferences.v3"

    @Published var values: PreferencesData {
        didSet {
            if oldValue.language != values.language { L10n.configure(values.language) }
            save()
        }
    }

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.key),
           let decoded = try? JSONDecoder().decode(PreferencesData.self, from: data) {
            values = decoded
        } else {
            values = PreferencesData()
        }
        L10n.configure(values.language)
    }

    func savePanelPosition(_ point: NSPoint, key: String) {
        values.panelPositions[key] = PanelPosition(point)
    }

    func resetPanelPositions() {
        values.panelPositions = [:]
    }

    func resetTheme() {
        values.theme = .reference
    }

    private func save() {
        if let data = try? JSONEncoder().encode(values) {
            UserDefaults.standard.set(data, forKey: Self.key)
        }
    }
}

extension Color {
    init(hex: String) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard cleaned.count == 6, let number = UInt32(cleaned, radix: 16) else {
            self = .white
            return
        }
        self = Color(
            red: Double((number >> 16) & 0xFF) / 255,
            green: Double((number >> 8) & 0xFF) / 255,
            blue: Double(number & 0xFF) / 255
        )
    }

    var hexRGB: String {
        guard let color = NSColor(self).usingColorSpace(.deviceRGB) else { return "#FFFFFF" }
        return String(
            format: "#%02X%02X%02X",
            Int((color.redComponent * 255).rounded()),
            Int((color.greenComponent * 255).rounded()),
            Int((color.blueComponent * 255).rounded())
        )
    }
}
