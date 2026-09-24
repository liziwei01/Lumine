import AppKit
import SwiftUI

enum Palette {
    private static var t: ThemeConfiguration { PreferencesStore.shared.values.theme }
    static var background: Color { Color(hex: t.panelBottom) }
    static var purple: Color { Color(hex: t.panelTop) }
    static var muted: Color { Color(hex: t.muted) }
    static var text: Color { Color(hex: t.text) }
    static var blue: Color { Color(hex: t.blue) }
    static var cyan: Color { Color(hex: t.cyan) }
    static var yellow: Color { Color(hex: t.yellow) }
    static var mint: Color { Color(hex: t.mint) }
    static var coral: Color { Color(hex: t.coral) }
    static var violet: Color { Color(hex: "#5B3CFC") }
}

private struct RGBColor {
    let red: Double
    let green: Double
    let blue: Double

    init(_ hex: String) {
        let number = UInt32(hex.trimmingCharacters(in: CharacterSet(charactersIn: "#")), radix: 16) ?? 0
        red = Double((number >> 16) & 0xFF) / 255
        green = Double((number >> 8) & 0xFF) / 255
        blue = Double(number & 0xFF) / 255
    }

    var color: Color { Color(red: red, green: green, blue: blue) }

    static func blend(_ a: RGBColor, _ b: RGBColor, _ t: Double) -> RGBColor {
        RGBColor(red: a.red + (b.red - a.red) * t, green: a.green + (b.green - a.green) * t, blue: a.blue + (b.blue - a.blue) * t)
    }

    private init(red: Double, green: Double, blue: Double) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    static func across(_ left: RGBColor, _ middle: RGBColor, _ right: RGBColor, _ x: Double, middlePosition: Double = 0.5) -> RGBColor {
        x < middlePosition ? blend(left, middle, x / middlePosition) : blend(middle, right, (x - middlePosition) / (1 - middlePosition))
    }
}

private struct PanelGradient: View {
    let theme: ThemeConfiguration

    var body: some View {
        let topLeft = RGBColor(theme.panelTop)
        let topMiddle = RGBColor(theme.panelTopMiddle)
        let topRight = RGBColor(theme.panelTopRight)
        let bottomLeft = RGBColor(theme.panelBottom)
        let bottomMiddle = RGBColor(theme.panelBottomMiddle)
        let bottomRight = RGBColor(theme.panelBottomRight)
        let beam = theme.resolvedBeam
        let beamTint = RGBColor(beam.color)
        Canvas { context, size in
            let columns = max(1, min(128, Int(size.width.rounded(.up))))
            let stripWidth = size.width / CGFloat(columns)
            for column in 0..<columns {
                let x = Double(column) / Double(max(columns - 1, 1))
                let upperBase = RGBColor.across(topLeft, topMiddle, topRight, x)
                let lowerBase = RGBColor.across(bottomLeft, bottomMiddle, bottomRight, x, middlePosition: 0.39)
                let middleBase = RGBColor.blend(upperBase, lowerBase, 0.52)
                let middlePosition = (beam.topPosition + beam.bottomPosition) / 2
                let upper = RGBColor.blend(upperBase, beamTint, beamWeight(x, center: beam.topPosition) * beam.strength).color
                let middle = RGBColor.blend(middleBase, beamTint, beamWeight(x, center: middlePosition) * beam.strength).color
                let lower = RGBColor.blend(lowerBase, beamTint, beamWeight(x, center: beam.bottomPosition) * beam.strength * 0.23).color
                let startX = CGFloat(column) * stripWidth
                let rect = CGRect(x: startX, y: 0, width: stripWidth + 0.5, height: size.height)
                context.fill(Path(rect), with: .linearGradient(Gradient(stops: [
                    .init(color: upper, location: 0),
                    .init(color: middle, location: 0.52),
                    .init(color: lower, location: 1)
                ]), startPoint: CGPoint(x: startX, y: 0), endPoint: CGPoint(x: startX, y: size.height)))
            }
        }
        .overlay {
            RadialGradient(colors: [Color(hex: theme.panelGlow).opacity(theme.panelGlowStrength * 0.35), .clear], center: .trailing, startRadius: 0, endRadius: 330)
        }
    }

    private func beamWeight(_ x: Double, center: Double) -> Double {
        let distance = (x - center) / 0.24
        return exp(-0.5 * distance * distance)
    }
}

struct PanelSurface<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        let theme = PreferencesStore.shared.values.theme
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background {
                PanelGradient(theme: theme)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .strokeBorder(Color(hex: theme.panelBorder).opacity(0.8), lineWidth: 1)
                    }
            }
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .padding(8)
    }
}

struct MetricCard<Content: View>: View {
    let selected: Bool
    var tone: Double = 0
    @ViewBuilder let content: Content

    var body: some View {
        let theme = PreferencesStore.shared.values.theme
        let cardPoints = ThemeConfiguration.points(for: theme.cardDirection)
        let start = RGBColor(theme.cardStart)
        let end = RGBColor(theme.cardEnd)
        let first = RGBColor.blend(start, end, min(1, max(0, tone)) * 0.52).color
        let last = RGBColor.blend(start, end, 0.48 + min(1, max(0, tone)) * 0.52).color
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(12)
            .background {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(LinearGradient(colors: [first, last], startPoint: cardPoints.0, endPoint: cardPoints.1))
                    .overlay {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(selected ? Color(hex: theme.selection) : Color(hex: theme.cardBorder).opacity(0.45), lineWidth: selected ? 2 : 0.6)
                    }
            }
    }
}

/// A small original vector laptop silhouette, drawn for the health header.
struct MacHealthIcon: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 3)
                .fill(LinearGradient(colors: [Color(red: 0.96, green: 1, blue: 0.83), Palette.cyan, Palette.blue], startPoint: .top, endPoint: .bottom))
                .frame(width: 43, height: 28)
                .overlay(alignment: .top) {
                    Capsule().fill(Color(hex: "526383")).frame(width: 8, height: 2).offset(y: 1)
                }
                .offset(y: -6)
            Path { path in
                path.move(to: CGPoint(x: 8, y: 31))
                path.addLine(to: CGPoint(x: 52, y: 31))
                path.addLine(to: CGPoint(x: 58, y: 39))
                path.addLine(to: CGPoint(x: 2, y: 39))
                path.closeSubpath()
            }
            .fill(LinearGradient(colors: [Palette.cyan, Palette.blue, Color(hex: "44418F")], startPoint: .top, endPoint: .bottom))
            Path { path in
                path.move(to: CGPoint(x: 2, y: 39))
                path.addLine(to: CGPoint(x: 58, y: 39))
                path.addLine(to: CGPoint(x: 55, y: 41))
                path.addLine(to: CGPoint(x: 5, y: 41))
                path.closeSubpath()
            }
            .fill(Palette.purple)
        }
        .frame(width: 60, height: 44)
        .accessibilityLabel(L10n.tr("Mac 健康状态图标"))
    }
}

struct OverviewView: View {
    @ObservedObject var store: MonitorStore
    @ObservedObject private var preferences = PreferencesStore.shared
    let selected: DetailKind?
    let select: (DetailKind) -> Void
    let openSettings: () -> Void

    private var m: SystemMetrics { store.metrics }
    private func shows(_ widget: Widget) -> Bool { preferences.values.shows(widget) }

    private var healthLabel: String {
        guard m.has(.disk), m.diskTotal > 0 else { return L10n.tr("不可用") }
        let freeRatio = Double(m.diskFree) / Double(m.diskTotal)
        if freeRatio < 0.10 || m.batteryHealthPercent.map({ $0 <= 10 }) == true || store.selectedTemperature.map({ $0 >= 76 }) == true {
            return L10n.tr("需要关注")
        }
        return L10n.tr("良好")
    }

    private var cpuTemperatureColor: Color {
        guard let temperature = store.selectedTemperature else { return Palette.muted }
        if temperature >= 76 { return Palette.coral }
        if temperature >= 56 { return Palette.yellow }
        return Palette.text
    }

    var body: some View {
        PanelSurface {
            VStack(alignment: .leading, spacing: 12) {
                if shows(.health) {
                    HStack(alignment: .center) {
                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 5) {
                                Text(L10n.tr("Mac 健康度：")).foregroundStyle(Palette.text)
                                Text(healthLabel).foregroundStyle(healthLabel == L10n.tr("良好") ? Palette.mint : Palette.yellow)
                            }
                            .font(.system(size: 18, weight: .bold))
                            Text(m.has(.deviceName) ? m.deviceName : L10n.tr("不可用"))
                                .font(.system(size: 12)).foregroundStyle(Palette.muted)
                        }
                        Spacer()
                        if preferences.values.allowDragging { PanelDragControl(key: "overview") }
                        MacHealthIcon()
                    }
                    .padding(.horizontal, 3)
                    .padding(.top, 2)
                }

                HStack(spacing: 10) {
                    if shows(.overviewDisk) {
                        overviewButton(.disk, height: 76, tone: 0) {
                            cardHeader("internaldrive", store.selectedVolume.name)
                            Spacer(minLength: 2)
                            Text(L10n.tr("可用：\(store.selectedVolumeAvailable ? MetricFormat.diskBytes(Double(store.selectedVolume.freeBytes)) : L10n.tr("不可用"))"))
                                .font(.system(size: 12)).foregroundStyle(Palette.yellow)
                        }
                    }
                    if shows(.overviewMemory) {
                        overviewButton(.memory, height: 76, tone: 1) {
                            cardHeader("memorychip", L10n.tr("内存"))
                            Spacer(minLength: 2)
                            Text(L10n.tr("压力值：\(m.has(.memory) ? MetricFormat.percent(m.memoryPressureEstimate) : L10n.tr("不可用"))"))
                                .font(.system(size: 12)).foregroundStyle(Palette.yellow)
                        }
                    }
                }
                HStack(spacing: 10) {
                    if shows(.overviewBattery) {
                        overviewButton(.battery, height: 56, tone: 0) {
                            cardHeader("battery.75percent", L10n.tr("电池"), trailing: m.batteryPercent.map { "\($0)%" } ?? "—")
                            Text(m.batteryPercent == nil ? (store.batteryPreviouslyPresent ? L10n.tr("不可用") : L10n.tr("此 Mac 未报告电池")) : (m.batteryCharging ? L10n.tr("正在充电") : MetricFormat.duration(m.batteryMinutes)))
                                .font(.system(size: 11)).foregroundStyle(Palette.muted).lineLimit(1)
                        }
                    }
                    if shows(.overviewCPU) {
                        overviewButton(.cpu, height: 56, tone: 1) {
                            cardHeader("cpu", "CPU", trailing: preferences.values.temperatureSource == "off" ? nil : store.selectedTemperature.map { String(format: "%.0f°C", $0) } ?? "—°C", trailingColor: cpuTemperatureColor)
                            Text(L10n.tr("\(store.cpuSourceLabel)加载：\(store.selectedCPUAvailable ? MetricFormat.percent(store.selectedCPU.total) : L10n.tr("不可用"))"))
                                .font(.system(size: 11)).foregroundStyle(Palette.muted).lineLimit(1)
                        }
                    }
                }
                HStack(alignment: .top, spacing: 10) {
                    if shows(.overviewNetwork) {
                        networkOverviewCard
                    }
                    if shows(.overviewDevices) {
                        overviewButton(.devices, height: 64, tone: 1) {
                            cardHeader("externaldrive.connected.to.line.below", L10n.tr("已连接的设备"))
                            Spacer(minLength: 2)
                            Text(!m.has(.externalVolumes) ? L10n.tr("不可用") : (m.externalVolumes.isEmpty ? L10n.tr("无外置存储设备") : L10n.tr("\(m.externalVolumes.count) 个外置存储设备")))
                                .font(.system(size: 11)).foregroundStyle(Palette.muted).lineLimit(1)
                        }
                    }
                }
                Spacer(minLength: 0)
                HStack {
                    Spacer()
                    Menu {
                        Button(L10n.tr("设置")) { openSettings() }
                        Button(L10n.tr("退出")) { NSApp.terminate(nil) }
                    } label: {
                        Image(systemName: "gearshape.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(.white.opacity(0.88))
                            .frame(width: 28, height: 28)
                            .background(.white.opacity(0.16), in: RoundedRectangle(cornerRadius: 7))
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .fixedSize()
                    .accessibilityLabel(L10n.tr("更多选项"))
                }
                .padding(.horizontal, 3)
                .padding(.top, 2)
            }
            .padding(10)
        }
        .foregroundStyle(Palette.text)
        .id(preferences.values.theme)
        .environment(\.locale, L10n.locale)
    }

    private func overviewButton<Content: View>(_ kind: DetailKind, height: CGFloat, tone: Double, @ViewBuilder content: () -> Content) -> some View {
        Button { select(kind) } label: {
            MetricCard(selected: selected == kind, tone: tone) {
                VStack(alignment: .leading, spacing: 4, content: content)
            }
            .frame(height: height)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityName(kind))
    }

    private var networkOverviewCard: some View {
        Button { select(.network) } label: {
            MetricCard(selected: selected == .network, tone: 0) {
                VStack(alignment: .leading, spacing: 6) {
                    cardHeader("wifi", m.has(.network) ? L10n.lookup(m.networkName) : L10n.tr("不可用"))
                    Text("↑  \(m.has(.network) ? MetricFormat.speed(m.uploadBytesPerSecond) : L10n.tr("不可用"))")
                    Text("↓  \(m.has(.network) ? MetricFormat.speed(m.downloadBytesPerSecond) : L10n.tr("不可用"))")
                    Spacer(minLength: 0)
                }
                .font(.system(size: 12, weight: .medium))
            }
            .frame(height: 122)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityName(.network))
        .overlay(alignment: .bottomTrailing) {
            if shows(.networkSpeedTest) {
                Button(L10n.tr("测试速度")) {
                    if selected != .network { select(.network) }
                    SpeedTestStore.shared.start()
                }
                .buttonStyle(.plain)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Palette.cyan)
                .disabled(m.networkInterface.isEmpty)
                .padding(12)
            }
        }
    }

    private func accessibilityName(_ kind: DetailKind) -> String {
        switch kind {
        case .disk: L10n.tr("查看磁盘详情")
        case .memory: L10n.tr("查看内存详情")
        case .battery: L10n.tr("查看电池详情")
        case .cpu: L10n.tr("查看 CPU 详情")
        case .network: L10n.tr("查看网络详情")
        case .devices: L10n.tr("查看已连接设备")
        }
    }

    private func cardHeader(_ icon: String, _ title: String, trailing: String? = nil, trailingColor: Color = Palette.text) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .regular))
                .foregroundStyle(.white.opacity(0.90))
                .frame(width: 20)
            Text(title).font(.system(size: 13, weight: .bold)).lineLimit(1)
            Spacer(minLength: 1)
            if let trailing {
                Text(trailing).font(.system(size: 12, weight: .semibold)).foregroundStyle(trailingColor)
            }
        }
    }
}

struct RingChart: View {
    let segments: [(Double, Color)]
    let main: String
    let subtitle: String
    var segmented = false
    var mainColor: Color = Palette.text

    private let diameter: CGFloat = 166
    private var glowStrength: Double { PreferencesStore.shared.values.theme.resolvedRingGlowStrength }
    private var glowRadius: CGFloat { CGFloat(PreferencesStore.shared.values.theme.resolvedRingGlowRadius) }

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color(hex: PreferencesStore.shared.values.theme.cardEnd).opacity(0.58), lineWidth: 24)
                .frame(width: diameter, height: diameter)
            if segmented {
                let amount = min(1, max(0, segments.first?.0 ?? 0))
                let color = segments.first?.1 ?? Palette.mint
                if glowStrength > 0 {
                    arc(from: 0, to: amount, color: color, lineWidth: 28)
                        .opacity(glowStrength)
                        .blur(radius: glowRadius)
                        .blendMode(.screen)
                }
                ForEach(0..<32, id: \.self) { index in
                    arc(from: Double(index) / 32 + 0.003,
                        to: Double(index + 1) / 32 - 0.003,
                        color: Double(index) / 32 < amount ? color : .clear)
                }
            } else {
                if glowStrength > 0 {
                    ForEach(Array(segments.enumerated()), id: \.offset) { index, segment in
                        let start = segments.prefix(index).reduce(0) { $0 + $1.0 }
                        arc(from: start, to: start + segment.0, color: segment.1, lineWidth: 28)
                            .opacity(glowStrength)
                            .blur(radius: glowRadius)
                            .blendMode(.screen)
                    }
                }
                ForEach(Array(segments.enumerated()), id: \.offset) { index, segment in
                    let start = segments.prefix(index).reduce(0) { $0 + $1.0 }
                    arc(from: start, to: start + segment.0, color: segment.1)
                }
            }
            VStack(spacing: 3) {
                Text(main).font(.system(size: 25, weight: .bold, design: .rounded)).foregroundStyle(mainColor)
                Text(subtitle).font(.system(size: 11)).foregroundStyle(Palette.muted).multilineTextAlignment(.center)
            }
        }
        .frame(width: 200, height: 200)
    }

    private func arc(from start: Double, to end: Double, color: Color, lineWidth: CGFloat = 24) -> some View {
        Circle()
            .trim(from: max(0, min(1, start)), to: max(0, min(1, end)))
            .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .butt))
            .frame(width: diameter, height: diameter)
            .rotationEffect(.degrees(-90))
    }
}

struct HistoryChart: View {
    let primary: [Double]
    let secondary: [Double]?
    let primaryColor: Color
    let secondaryColor: Color
    let ceiling: Double

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Canvas { context, size in
                    for row in 0...5 {
                        var line = Path()
                        let y = size.height * CGFloat(row) / 5
                        line.move(to: CGPoint(x: 0, y: y))
                        line.addLine(to: CGPoint(x: size.width, y: y))
                        context.stroke(line, with: .color(.white.opacity(0.10)), lineWidth: 0.5)
                    }
                    for column in 0...12 {
                        var line = Path()
                        let x = size.width * CGFloat(column) / 12
                        line.move(to: CGPoint(x: x, y: 0))
                        line.addLine(to: CGPoint(x: x, y: size.height))
                        context.stroke(line, with: .color(.white.opacity(0.08)), lineWidth: 0.5)
                    }
                }
                area(primary, in: geometry.size, limit: ceiling)
                    .fill(LinearGradient(colors: [primaryColor.opacity(0.34), primaryColor.opacity(0.03)], startPoint: .top, endPoint: .bottom))
                if let secondary {
                    area(secondary, in: geometry.size, limit: ceiling)
                        .fill(LinearGradient(colors: [secondaryColor.opacity(0.28), secondaryColor.opacity(0.02)], startPoint: .top, endPoint: .bottom))
                }
                line(primary, in: geometry.size, limit: ceiling)
                    .stroke(primaryColor, style: StrokeStyle(lineWidth: 1.4, lineJoin: .round))
                if let secondary {
                    line(secondary, in: geometry.size, limit: ceiling)
                        .stroke(secondaryColor, style: StrokeStyle(lineWidth: 1.4, lineJoin: .round))
                }
            }
        }
    }

    private func line(_ values: [Double], in size: CGSize, limit: Double) -> Path {
        var path = Path()
        guard values.count > 1 else { return path }
        for (index, value) in values.enumerated() {
            let x = size.width * CGFloat(index) / CGFloat(values.count - 1)
            let y = size.height * (1 - CGFloat(min(max(value / max(limit, 1), 0), 1)))
            if index == 0 { path.move(to: CGPoint(x: x, y: y)) }
            else { path.addLine(to: CGPoint(x: x, y: y)) }
        }
        return path
    }

    private func area(_ values: [Double], in size: CGSize, limit: Double) -> Path {
        var path = line(values, in: size, limit: limit)
        guard values.count > 1 else { return path }
        path.addLine(to: CGPoint(x: size.width, y: size.height))
        path.addLine(to: CGPoint(x: 0, y: size.height))
        path.closeSubpath()
        return path
    }
}
