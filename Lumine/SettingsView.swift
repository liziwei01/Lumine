import AppKit
import SwiftUI

struct WindowDragHandle: NSViewRepresentable {
    let key: String

    final class DragView: NSView {
        var key = ""
        override func mouseDown(with event: NSEvent) {
            window?.performDrag(with: event)
            if let origin = window?.frame.origin {
                PreferencesStore.shared.savePanelPosition(origin, key: key)
            }
        }
    }

    func makeNSView(context: Context) -> DragView {
        let view = DragView()
        view.key = key
        return view
    }

    func updateNSView(_ nsView: DragView, context: Context) {
        nsView.key = key
    }
}

struct PanelDragControl: View {
    let key: String

    var body: some View {
        ZStack {
            Capsule().fill(.white.opacity(0.11))
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Palette.muted)
            WindowDragHandle(key: key)
        }
        .frame(width: 47, height: 25)
        .help(L10n.tr("拖动面板并保存位置"))
        .accessibilityLabel(L10n.tr("拖动面板"))
    }
}

struct SettingsView: View {
    @ObservedObject private var preferences = PreferencesStore.shared
    @ObservedObject var store: MonitorStore
    let resetPositions: () -> Void
    @State private var selectedWidgetGroup = 0
    @State private var appearancePage = 0
    @State private var dataPage = 0

    private var widgetGroups: [(String, [(Widget, String)])] { [
        (L10n.tr("总览"), [(.health, L10n.tr("Mac 健康度")), (.overviewDisk, L10n.tr("磁盘")), (.overviewMemory, L10n.tr("内存")), (.overviewBattery, L10n.tr("电池")), (.overviewCPU, "CPU"), (.overviewNetwork, L10n.tr("网络")), (.overviewDevices, L10n.tr("已连接的设备"))]),
        (L10n.tr("磁盘"), [(.diskCategories, L10n.tr("文件类别")), (.diskHealth, L10n.tr("运行状况")), (.diskTemperature, L10n.tr("温度")), (.diskTrash, L10n.tr("废纸篓")), (.diskCapacity, L10n.tr("已使用与总容量（附加）")), (.diskExternal, L10n.tr("外置驱动器（附加）"))]),
        (L10n.tr("内存"), [(.memoryPressure, L10n.tr("压力")), (.memorySwap, L10n.tr("交换分区")), (.memoryProcesses, L10n.tr("使用率排行"))]),
        (L10n.tr("电池"), [(.batteryHealth, L10n.tr("运行状况")), (.batteryTemperature, L10n.tr("温度")), (.batteryCycles, L10n.tr("循环次数")), (.batteryProcesses, L10n.tr("使用率排行"))]),
        ("CPU", [(.cpuChart, L10n.tr("负载图表")), (.cpuUptime, L10n.tr("正常运行时间")), (.cpuTemperature, L10n.tr("温度")), (.cpuProcesses, L10n.tr("使用率排行"))]),
        (L10n.tr("网络"), [(.networkConnection, L10n.tr("连接信息")), (.networkDownload, L10n.tr("下载")), (.networkUpload, L10n.tr("上传")), (.networkSpeedTest, L10n.tr("测速"))]),
        (L10n.tr("设备"), [(.devicesExternal, L10n.tr("外置驱动器"))])
    ] }

    var body: some View {
        TabView {
            appearanceTab
                .tabItem { Label(L10n.tr("外观"), systemImage: "paintpalette") }
            layoutTab
                .tabItem { Label(L10n.tr("面板"), systemImage: "rectangle.on.rectangle") }
            componentsTab
                .tabItem { Label(L10n.tr("组件"), systemImage: "square.grid.2x2") }
            dataTab
                .tabItem { Label(L10n.tr("数据来源"), systemImage: "cpu") }
            languageTab
                .tabItem { Label(L10n.tr("语言"), systemImage: "globe") }
        }
        .padding(16)
        .frame(minWidth: 630, minHeight: 530)
        .environment(\.locale, L10n.locale)
    }

    private var languageTab: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(L10n.tr("界面语言")).font(.system(size: 17, weight: .bold))
            Text(L10n.tr("选择“跟随系统”时，Lumine 使用 macOS 首选语言列表中第一个受支持的语言。切换后立即生效。"))
                .font(.system(size: 12)).foregroundStyle(.secondary)
            Picker(L10n.tr("语言"), selection: Binding(
                get: { preferences.values.language },
                set: {
                    preferences.values.language = $0
                    resetPositions()
                }
            )) {
                Text(L10n.tr("跟随系统")).tag("system")
                Text(verbatim: "简体中文").tag("zh-Hans")
                Text(verbatim: "繁體中文").tag("zh-Hant")
                Text(verbatim: "English").tag("en")
                Text(verbatim: "日本語").tag("ja")
                Text(verbatim: "Русский").tag("ru")
                Text(verbatim: "한국어").tag("ko")
                Text(verbatim: "Español").tag("es")
            }
            .frame(maxWidth: 360)
            Text(L10n.tr("当前语言：\(L10n.displayName(for: L10n.language))"))
                .font(.system(size: 12)).foregroundStyle(.secondary)
            Spacer()
        }
        .padding(18)
    }

    private var componentsTab: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(L10n.tr("选择显示的组件")).font(.system(size: 17, weight: .bold))
            Text(L10n.tr("每个开关立即生效。磁盘的“已使用与总容量”和“外置驱动器”是附加组件，默认隐藏。"))
                .font(.system(size: 12)).foregroundStyle(.secondary)
            Picker(L10n.tr("区域"), selection: $selectedWidgetGroup) {
                ForEach(widgetGroups.indices, id: \.self) { index in
                    Text(widgetGroups[index].0).tag(index)
                }
            }
            .pickerStyle(.segmented)
            Divider()
            ForEach(widgetGroups[selectedWidgetGroup].1.indices, id: \.self) { index in
                Toggle(widgetGroups[selectedWidgetGroup].1[index].1,
                       isOn: widgetBinding(widgetGroups[selectedWidgetGroup].1[index].0))
                    .font(.system(size: 13))
                    .padding(.vertical, 2)
            }
            Spacer()
            HStack {
                Button(L10n.tr("本组全部显示")) {
                    for (widget, _) in widgetGroups[selectedWidgetGroup].1 {
                        preferences.values.widgetVisibility[widget.rawValue] = true
                    }
                    updateDiskCategorySelection()
                    resetPositions()
                }
                Spacer()
                Button(L10n.tr("恢复默认显示")) {
                    preferences.values.widgetVisibility = [:]
                    updateDiskCategorySelection()
                    resetPositions()
                }
            }
        }
        .padding(18)
    }

    private var appearanceTab: some View {
        VStack(alignment: .leading, spacing: 15) {
            themePreview
                .frame(height: 132)
                .id(preferences.values.theme)
            HStack {
                Text(L10n.tr("参考截图配色可随时恢复，修改会立即用于监控面板。"))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                Spacer()
                Button(L10n.tr("恢复截图配色")) { preferences.resetTheme() }
            }
            Picker(L10n.tr("外观区域"), selection: $appearancePage) {
                Text(L10n.tr("面板背景")).tag(0)
                Text(L10n.tr("卡片")).tag(1)
                Text(L10n.tr("文字与指标")).tag(2)
                Text(L10n.tr("斜向柔光")).tag(3)
                Text(L10n.tr("圆环光晕")).tag(4)
            }
            .pickerStyle(.segmented)
            if appearancePage == 0 {
                GroupBox(L10n.tr("面板背景渐变")) {
                    VStack(spacing: 8) {
                        colorPair(L10n.tr("左上"), \.panelTop, L10n.tr("上中"), \.panelTopMiddle)
                        colorPair(L10n.tr("右上"), \.panelTopRight, L10n.tr("左下"), \.panelBottom)
                        colorPair(L10n.tr("下中"), \.panelBottomMiddle, L10n.tr("右下"), \.panelBottomRight)
                        colorPair(L10n.tr("光晕"), \.panelGlow, L10n.tr("边框"), \.panelBorder)
                        HStack {
                            Text(L10n.tr("光晕强度"))
                            Slider(value: themeBinding(\.panelGlowStrength), in: 0...1)
                            Text("\(Int(preferences.values.theme.panelGlowStrength * 100))%")
                                .frame(width: 40, alignment: .trailing)
                                .monospacedDigit()
                        }
                    }
                    .padding(5)
                }
            }
            if appearancePage == 3 {
                GroupBox(L10n.tr("斜向柔光柱")) {
                    VStack(spacing: 6) {
                        ColorPicker(L10n.tr("光柱颜色"), selection: beamColorBinding, supportsOpacity: false)
                        beamSlider(L10n.tr("强度"), \.strength, 0...0.5)
                        beamSlider(L10n.tr("顶部位置"), \.topPosition, 0.25...1.2)
                        beamSlider(L10n.tr("底部位置"), \.bottomPosition, 0.25...1.4)
                    }
                    .padding(5)
                }
            }
            if appearancePage == 1 {
                GroupBox(L10n.tr("卡片渐变与边框")) {
                    VStack(spacing: 8) {
                        colorPair(L10n.tr("起点"), \.cardStart, L10n.tr("终点"), \.cardEnd)
                        colorPair(L10n.tr("普通边框"), \.cardBorder, L10n.tr("选中边框"), \.selection)
                        directionPicker(L10n.tr("渐变方向"), keyPath: \.cardDirection)
                    }
                    .padding(5)
                }
            }
            if appearancePage == 2 {
                GroupBox(L10n.tr("文字与指标颜色")) {
                    VStack(spacing: 8) {
                        colorPair(L10n.tr("主文字"), \.text, L10n.tr("次文字"), \.muted)
                        colorPair(L10n.tr("蓝色"), \.blue, L10n.tr("青色"), \.cyan)
                        colorPair(L10n.tr("黄色"), \.yellow, L10n.tr("薄荷绿"), \.mint)
                        colorPair(L10n.tr("珊瑚红"), \.coral, "", nil)
                    }
                    .padding(5)
                }
            }
            if appearancePage == 4 {
                GroupBox(L10n.tr("圆环光晕")) {
                    VStack(spacing: 12) {
                        ringGlowSlider(L10n.tr("光晕强度"), value: ringGlowStrengthBinding, range: 0...1, format: { "\(Int($0 * 100))%" })
                        ringGlowSlider(L10n.tr("光晕范围"), value: ringGlowRadiusBinding, range: 0...16, format: { "\(Int($0)) pt" })
                        Text(L10n.tr("强度设为 0 可关闭圆环光晕。"))
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(5)
                }
            }
            Spacer()
        }
        .padding(18)
    }

    private var themePreview: some View {
        PanelSurface {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(L10n.tr("Mac 健康度：良好")).font(.system(size: 18, weight: .bold))
                    Spacer()
                    MacHealthIcon().scaleEffect(0.7)
                }
                HStack(spacing: 9) {
                    MetricCard(selected: true) {
                        VStack(alignment: .leading, spacing: 7) {
                            Text(L10n.tr("内存")).font(.system(size: 12, weight: .bold))
                            Text(L10n.tr("占用：58%")).font(.system(size: 11)).foregroundStyle(Palette.yellow)
                        }
                    }
                    MetricCard(selected: false, tone: 1) {
                        VStack(alignment: .leading, spacing: 7) {
                            Text("CPU").font(.system(size: 12, weight: .bold))
                            Text(L10n.tr("加载：23%")).font(.system(size: 11)).foregroundStyle(Palette.cyan)
                        }
                    }
                }
            }
            .padding(15)
        }
        .foregroundStyle(Palette.text)
    }

    private var layoutTab: some View {
        VStack(alignment: .leading, spacing: 16) {
            Toggle(L10n.tr("允许拖动监控面板"), isOn: binding(\.allowDragging))
                .font(.system(size: 13, weight: .semibold))
            Text(L10n.tr("启用后，总览和详情标题栏出现拖动手柄。拖到目标位置松开鼠标，位置会自动保存。每种详情面板可分别放置。"))
                .font(.system(size: 12)).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Divider()
            Text(L10n.tr("保存的位置")).font(.system(size: 14, weight: .semibold))
            VStack(spacing: 6) {
                panelPositionRow(L10n.tr("总览"), key: "overview")
                ForEach(DetailKind.allCases, id: \.self) { kind in
                    panelPositionRow(panelName(kind), key: "detail.\(kind.rawValue)")
                }
            }
            Spacer(minLength: 0)
            HStack {
                Spacer()
                Button(L10n.tr("全部恢复自动位置")) {
                    preferences.resetPanelPositions()
                    resetPositions()
                }
            }
        }
        .padding(16)
    }

    private func panelPositionRow(_ name: String, key: String) -> some View {
        HStack {
            Text(name).frame(width: 80, alignment: .leading)
            if let position = preferences.values.panelPositions[key] {
                Text("x: \(Int(position.x))   y: \(Int(position.y))")
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(.secondary)
            } else {
                Text(L10n.tr("自动放置")).foregroundStyle(.secondary)
            }
            Spacer()
            Button(L10n.tr("恢复自动")) {
                preferences.values.panelPositions.removeValue(forKey: key)
                resetPositions()
            }
            .disabled(preferences.values.panelPositions[key] == nil)
        }
        .padding(8)
        .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 7))
    }

    private var dataTab: some View {
        VStack(alignment: .leading, spacing: 15) {
            Picker(L10n.tr("数据分组"), selection: $dataPage) {
                Text(L10n.tr("采集与处理器")).tag(0)
                Text(L10n.tr("内存与网络")).tag(1)
                Text(L10n.tr("磁盘与文件类别")).tag(2)
            }
            .pickerStyle(.segmented)
            if dataPage == 0 {
                sourceGroup(L10n.tr("采集间隔"), note: L10n.tr("关闭监控面板时使用较低频率；进程排行只在对应详情打开时采集。设置立即生效。")) {
                    HStack(spacing: 24) {
                        Picker(L10n.tr("面板打开"), selection: samplingBinding(\.activeSamplingInterval)) {
                            ForEach([2, 5, 10, 15, 30, 60], id: \.self) { seconds in
                                Text(L10n.tr("\(seconds) 秒")).tag(seconds)
                            }
                        }
                        Picker(L10n.tr("面板关闭"), selection: samplingBinding(\.idleSamplingInterval)) {
                            ForEach([10, 30, 60, 120, 300], id: \.self) { seconds in
                                Text(L10n.tr("\(seconds) 秒")).tag(seconds)
                            }
                        }
                    }
                }
                sourceGroup(L10n.tr("CPU 使用率"), note: L10n.tr("总体为全部逻辑核心平均；单核心使用率来自 macOS 的逐核心计数器。")) {
                    Picker(L10n.tr("显示"), selection: binding(\.cpuSource)) {
                        Text(L10n.tr("总体平均")).tag("overall")
                        ForEach(store.metrics.cpuCores, id: \.index) { core in
                            Text(L10n.tr("逻辑核心 \(core.index)")).tag("core:\(core.index)")
                        }
                    }
                }
                sourceGroup(L10n.tr("CPU 温度"), note: L10n.tr("SMC 是未公开的硬件传感器接口；此机型无法读取时显示不可用。")) {
                    Picker(L10n.tr("显示"), selection: binding(\.temperatureSource)) {
                        Text(L10n.tr("平均温度")).tag("average")
                        Text(L10n.tr("最高温度")).tag("hottest")
                        ForEach(store.metrics.cpuTemperatures, id: \.key) { sensor in
                            Text("\(L10n.lookup(sensor.name)) · \(sensor.key)").tag("sensor:\(sensor.key)")
                        }
                        Text(L10n.tr("不显示温度")).tag("off")
                    }
                }
            }
            if dataPage == 1 {
                sourceGroup(L10n.tr("网络"), note: L10n.tr("可选择自动识别或指定网络接口。速率只统计所选接口。")) {
                    Picker(L10n.tr("接口"), selection: binding(\.networkInterface)) {
                        Text(L10n.tr("自动识别")).tag("auto")
                        ForEach(store.metrics.networkInterfaces, id: \.self) { name in
                            Text(name).tag(name)
                        }
                    }
                }
                sourceGroup(L10n.tr("流量统计窗口"), note: L10n.tr("按所选接口统计最近时间窗；首次启动时从开始采集后算起。测速只在点击按钮时发送测试数据。")) {
                    Picker(L10n.tr("累计时间"), selection: binding(\.trafficWindowMinutes)) {
                        Text(L10n.tr("最近 15 分钟")).tag(15)
                        Text(L10n.tr("最近 30 分钟")).tag(30)
                        Text(L10n.tr("最近 1 小时")).tag(60)
                        Text(L10n.tr("最近 3 小时")).tag(180)
                        Text(L10n.tr("最近 6 小时")).tag(360)
                        Text(L10n.tr("最近 24 小时")).tag(1440)
                    }
                }
                sourceGroup(L10n.tr("内存"), note: L10n.tr("可用包含非活跃和推测页；立即空闲只计算空闲页。")) {
                    Picker(L10n.tr("可用口径"), selection: binding(\.memorySource)) {
                        Text(L10n.tr("可用（可回收）")).tag("available")
                        Text(L10n.tr("立即空闲")).tag("free")
                    }
                }
            }
            if dataPage == 2 {
                sourceGroup(L10n.tr("磁盘"), note: L10n.tr("启动卷和已挂载的本地外置卷可选；每个卷保存各自的文件类别缓存。")) {
                    Picker(L10n.tr("卷"), selection: diskSourceBinding) {
                        Text(L10n.tr("启动卷")).tag("startup")
                        ForEach(store.metrics.externalVolumes) { volume in
                            Text(volume.name).tag(volume.id)
                        }
                    }
                }
                GroupBox(L10n.tr("文件类别扫描")) {
                    Text(L10n.tr("打开磁盘详情只读取缓存。点击“重新扫描”才开始扫描所选卷。"))
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(5)
                }
            }
            Spacer()
        }
        .padding(18)
    }

    private func sourceGroup<Content: View>(_ title: String, note: String, @ViewBuilder content: () -> Content) -> some View {
        GroupBox(title) {
            VStack(alignment: .leading, spacing: 5) {
                content()
                Text(note).font(.system(size: 11)).foregroundStyle(.secondary)
            }
            .padding(5)
        }
    }

    private func colorPair(_ left: String, _ leftKey: WritableKeyPath<ThemeConfiguration, String>, _ right: String, _ rightKey: WritableKeyPath<ThemeConfiguration, String>?) -> some View {
        HStack(spacing: 16) {
            ColorPicker(left, selection: colorBinding(leftKey), supportsOpacity: false)
            if let rightKey {
                ColorPicker(right, selection: colorBinding(rightKey), supportsOpacity: false)
            } else {
                Spacer()
            }
        }
    }

    private func directionPicker(_ label: String, keyPath: WritableKeyPath<ThemeConfiguration, String>) -> some View {
        Picker(label, selection: themeBinding(keyPath)) {
            Text(L10n.tr("上 → 下")).tag("vertical")
            Text(L10n.tr("左 → 右")).tag("horizontal")
            Text(L10n.tr("左上 → 右下")).tag("diagonal")
            Text(L10n.tr("右上 → 左下")).tag("reverseDiagonal")
        }
    }

    private func colorBinding(_ keyPath: WritableKeyPath<ThemeConfiguration, String>) -> Binding<Color> {
        Binding(
            get: { Color(hex: preferences.values.theme[keyPath: keyPath]) },
            set: { preferences.values.theme[keyPath: keyPath] = $0.hexRGB }
        )
    }

    private func themeBinding<Value>(_ keyPath: WritableKeyPath<ThemeConfiguration, Value>) -> Binding<Value> {
        Binding(
            get: { preferences.values.theme[keyPath: keyPath] },
            set: { preferences.values.theme[keyPath: keyPath] = $0 }
        )
    }

    private var beamColorBinding: Binding<Color> {
        Binding(
            get: { Color(hex: preferences.values.theme.resolvedBeam.color) },
            set: {
                var beam = preferences.values.theme.resolvedBeam
                beam.color = $0.hexRGB
                preferences.values.theme.beam = beam
            }
        )
    }

    private func beamSlider(_ label: String, _ keyPath: WritableKeyPath<BeamConfiguration, Double>, _ range: ClosedRange<Double>) -> some View {
        HStack {
            Text(label).frame(width: 76, alignment: .leading)
            Slider(value: Binding(
                get: { preferences.values.theme.resolvedBeam[keyPath: keyPath] },
                set: {
                    var beam = preferences.values.theme.resolvedBeam
                    beam[keyPath: keyPath] = $0
                    preferences.values.theme.beam = beam
                }
            ), in: range)
            Text(String(format: "%.2f", preferences.values.theme.resolvedBeam[keyPath: keyPath]))
                .frame(width: 42, alignment: .trailing)
                .monospacedDigit()
        }
        .font(.system(size: 11))
    }

    private var ringGlowStrengthBinding: Binding<Double> {
        Binding(
            get: { preferences.values.theme.resolvedRingGlowStrength },
            set: { preferences.values.theme.ringGlowStrength = $0 }
        )
    }

    private var ringGlowRadiusBinding: Binding<Double> {
        Binding(
            get: { preferences.values.theme.resolvedRingGlowRadius },
            set: { preferences.values.theme.ringGlowRadius = $0 }
        )
    }

    private func ringGlowSlider(_ label: String, value: Binding<Double>, range: ClosedRange<Double>, format: @escaping (Double) -> String) -> some View {
        HStack {
            Text(label).frame(width: 86, alignment: .leading)
            Slider(value: value, in: range)
            Text(format(value.wrappedValue)).frame(width: 48, alignment: .trailing).monospacedDigit()
        }
        .font(.system(size: 11))
    }

    private func binding<Value>(_ keyPath: WritableKeyPath<PreferencesData, Value>) -> Binding<Value> {
        Binding(
            get: { preferences.values[keyPath: keyPath] },
            set: { preferences.values[keyPath: keyPath] = $0 }
        )
    }

    private func samplingBinding(_ keyPath: WritableKeyPath<PreferencesData, Int>) -> Binding<Int> {
        Binding(
            get: { preferences.values[keyPath: keyPath] },
            set: {
                preferences.values[keyPath: keyPath] = $0
                store.reschedule()
            }
        )
    }

    private var diskSourceBinding: Binding<String> {
        Binding(
            get: { preferences.values.diskSource },
            set: {
                preferences.values.diskSource = $0
                updateDiskCategorySelection()
            }
        )
    }

    private func updateDiskCategorySelection() {
        let values = preferences.values
        DiskCategoryStore.shared.configure(path: values.diskSource,
                                           enabled: values.shows(.diskCategories))
    }

    private func widgetBinding(_ widget: Widget) -> Binding<Bool> {
        Binding(
            get: { preferences.values.shows(widget) },
            set: {
                preferences.values.widgetVisibility[widget.rawValue] = $0
                if widget == .diskCategories { updateDiskCategorySelection() }
                resetPositions()
            }
        )
    }

    private func panelName(_ kind: DetailKind) -> String {
        switch kind {
        case .disk: L10n.tr("磁盘")
        case .memory: L10n.tr("内存")
        case .battery: L10n.tr("电池")
        case .cpu: "CPU"
        case .network: L10n.tr("网络")
        case .devices: L10n.tr("设备")
        }
    }
}
