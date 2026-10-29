import AppKit
import SwiftUI

struct DetailView: View {
    @ObservedObject var store: MonitorStore
    @ObservedObject private var preferences = PreferencesStore.shared
    @ObservedObject private var diskCategories = DiskCategoryStore.shared
    @ObservedObject private var diskSupplement = DiskSupplementStore.shared
    @ObservedObject private var speedTest = SpeedTestStore.shared
    @State private var confirmEmptyTrash = false
    @State private var pendingTrashPath: String?
    @State private var confirmProcessClose = false
    @State private var pendingProcess: ProcessUsage?
    @State private var processNotice: String?
    let kind: DetailKind
    let layoutChanged: () -> Void

    private var m: SystemMetrics { store.metrics }

    var body: some View {
        PanelSurface {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    Text(title).font(.system(size: 20, weight: .bold))
                    Spacer()
                    if preferences.values.allowDragging {
                        PanelDragControl(key: "detail.\(kind.rawValue)")
                    }
                }
                .padding(.horizontal, 8)

                switch kind {
                case .disk: diskContent
                case .memory: memoryContent
                case .battery: batteryContent
                case .cpu: cpuContent
                case .gpu: gpuContent
                case .network: networkContent
                case .devices: devicesContent
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .foregroundStyle(Palette.text)
        .id(preferences.values.theme)
        .environment(\.locale, L10n.locale)
        .onChange(of: preferences.values.diskSource) { _ in
            if kind == .disk {
                pendingTrashPath = nil
                confirmEmptyTrash = false
                let path = store.selectedVolume.id == "startup" ? "/" : store.selectedVolume.id
                configureDiskCategories(path: path)
                refreshDiskSupplement(path: path)
            }
        }
        .onChange(of: preferences.values.widgetVisibility) { _ in
            if kind == .disk {
                let path = store.selectedVolume.id == "startup" ? "/" : store.selectedVolume.id
                configureDiskCategories(path: path)
                refreshDiskSupplement(path: path)
            }
            if kind == .network && !shows(.networkSpeedTest) { speedTest.cancel() }
            layoutChanged()
        }
        .onChange(of: preferences.values.failedSampleRetentionSeconds) { _ in
            if kind == .disk {
                let path = store.selectedVolume.id == "startup" ? "/" : store.selectedVolume.id
                refreshDiskSupplement(path: path, force: true)
            }
        }
        .onChange(of: store.selectedVolumeAvailable) { available in
            guard kind == .disk else { return }
            if available {
                let path = store.selectedVolume.id == "startup" ? "/" : store.selectedVolume.id
                refreshDiskSupplement(path: path, force: true)
            } else {
                diskSupplement.invalidateReadings()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            if kind == .disk { refreshDiskSupplement(path: selectedDiskPath, force: true) }
        }
        .alert(L10n.tr("清空废纸篓？"), isPresented: $confirmEmptyTrash) {
            Button(L10n.tr("清空"), role: .destructive) {
                let path = selectedDiskPath
                if pendingTrashPath == path { diskSupplement.emptyTrash(path: path) }
                pendingTrashPath = nil
            }
            Button(L10n.tr("取消"), role: .cancel) { pendingTrashPath = nil }
        } message: {
            Text(L10n.tr("所选卷当前用户废纸篓中的文件将被永久删除。"))
        }
        .confirmationDialog(L10n.tr("关闭进程？"), isPresented: $confirmProcessClose) {
            Button(L10n.tr("关闭 \(pendingProcess?.name ?? L10n.tr("进程"))")) {
                guard let process = pendingProcess else { return }
                Task.detached(priority: .userInitiated) {
                    let error = ProcessCloser.close(process)
                    await MainActor.run {
                        processNotice = error ?? L10n.tr("已请求 \(process.name) 退出。")
                        store.refresh()
                    }
                }
            }
        } message: {
            Text(L10n.tr("未保存的数据可能丢失。"))
        }
    }

    private func shows(_ widget: Widget) -> Bool { preferences.values.shows(widget) }

    private var selectedDiskPath: String {
        store.selectedVolume.id == "startup" ? "/" : store.selectedVolume.id
    }

    private var trashUsageDescription: String {
        guard store.selectedVolumeAvailable else { return L10n.tr("不可用") }
        if diskSupplement.isLoading && !diskSupplement.trashAvailable { return L10n.tr("正在计算…") }
        guard diskSupplement.trashAvailable else { return L10n.tr("无法读取废纸篓") }
        let size = MetricFormat.diskBytes(Double(diskSupplement.trash.bytes))
        if diskSupplement.trash.usesCachedBytes { return L10n.tr("上次读数：\(size)") }
        if !diskSupplement.trash.isComplete { return L10n.tr("至少已读取：\(size)") }
        return L10n.tr("已使用：\(size)（提醒阈值 2 GB）")
    }

    private func configureDiskCategories(path: String) {
        diskCategories.configure(path: path,
                                 enabled: shows(.diskCategories))
    }

    private func refreshDiskSupplement(path: String, force: Bool = false) {
        guard store.selectedVolumeAvailable else {
            diskSupplement.invalidateReadings()
            return
        }
        let diagnostics = shows(.diskHealth) || shows(.diskTemperature)
        let trash = shows(.diskTrash)
        if diagnostics || trash {
            diskSupplement.refresh(path: path, diagnostics: diagnostics, trash: trash, force: force)
        } else {
            diskSupplement.cancel()
        }
    }

    private var title: String {
        switch kind {
        case .disk: store.selectedVolume.name
        case .memory: L10n.tr("内存")
        case .battery: L10n.tr("电池")
        case .cpu: m.cpuName
        case .gpu: "GPU"
        case .network: L10n.tr("网络")
        case .devices: L10n.tr("已连接的设备")
        }
    }

    private var diskContent: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 16) {
                RingChart(
                    segments: [(store.selectedVolumeAvailable && store.selectedVolume.totalBytes > 0 ? Double(store.selectedVolume.freeBytes) / Double(store.selectedVolume.totalBytes) : 0, Palette.text)],
                    main: store.selectedVolumeAvailable ? MetricFormat.diskBytes(Double(store.selectedVolume.freeBytes)) : L10n.tr("不可用"),
                    subtitle: L10n.tr("可用空间\n(总共 \(store.selectedVolumeAvailable ? MetricFormat.diskBytes(Double(store.selectedVolume.totalBytes)) : L10n.tr("不可用")))"),
                    mainColor: Palette.yellow
                )
                if shows(.diskCategories) {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(DiskCategory.allCases) { category in
                            legend(category.localizedName, color: diskCategoryColor(category), value: diskCategories.lastCompleted == nil && diskCategories.result.size(category) == 0
                                   ? (diskCategories.isScanning ? L10n.tr("正在计算…") : "—")
                                   : MetricFormat.diskBytes(Double(diskCategories.result.size(category))))
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.leading, 16)
            if shows(.diskCategories) {
                HStack(spacing: 7) {
                    if diskCategories.isScanning { ProgressView().controlSize(.small) }
                    if diskCategories.isScanning {
                        Text(diskCategories.lastCompleted == nil
                             ? L10n.tr("后台首次扫描中 · \(diskCategories.scanProgress.files.formatted()) 个文件")
                             : L10n.tr("后台更新中 · 显示上次结果"))
                    } else if let updated = diskCategories.lastCompleted {
                        Text(L10n.tr("文件类别 · 更新于 \(updated.formatted(Date.FormatStyle(date: .abbreviated, time: .shortened).locale(L10n.locale)))"))
                    } else {
                        Text(L10n.tr("文件类别 · 尚无缓存"))
                    }
                    if diskCategories.result.unreadable > 0 {
                        Text(L10n.tr("· \(diskCategories.result.unreadable) 项无法读取")).foregroundStyle(Palette.yellow)
                    }
                    Spacer()
                    Button(diskCategories.isScanning ? L10n.tr("停止") : L10n.tr("重新扫描")) {
                        if diskCategories.isScanning { diskCategories.cancel() }
                        else { diskCategories.scanNow() }
                    }
                }
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Palette.muted)
                .padding(.horizontal, 8)
            }
            if shows(.diskHealth) || shows(.diskTemperature) {
                HStack(spacing: 10) {
                    if shows(.diskHealth) {
                        insightCard(L10n.tr("运行状况"), icon: "heart.fill",
                                    value: store.selectedVolumeAvailable ? (diskSupplement.diagnostics.healthPercent.map { "\($0)%" } ?? L10n.lookup(diskSupplement.diagnostics.healthLabel)) : L10n.tr("不可用"),
                                    message: store.selectedVolumeAvailable ? diskSupplement.diagnostics.healthMessage : L10n.tr("不可用"),
                                    link: KnowledgeLink.diskHealth, accent: diskSupplement.diagnostics.healthLabel == "严重" ? Palette.coral : .white)
                    }
                    if shows(.diskTemperature) {
                        insightCard(L10n.tr("温度"), icon: "thermometer",
                                    value: store.selectedVolumeAvailable ? (TemperatureStatus.label(diskSupplement.diagnostics.temperatureCelsius) ?? L10n.tr("不可用")) : L10n.tr("不可用"),
                                    message: store.selectedVolumeAvailable ? diskSupplement.diagnostics.temperatureMessage : L10n.tr("不可用"),
                                    link: KnowledgeLink.diskTemperature,
                                    accent: temperatureColor(TemperatureStatus.disk(store.selectedVolumeAvailable ? diskSupplement.diagnostics.temperatureCelsius : nil)), tone: 1)
                    }
                }
            }
            if shows(.diskTrash) {
                sectionTitle(L10n.tr("组件"))
                MetricCard(selected: false) {
                    VStack(alignment: .leading, spacing: 10) {
                        Label(L10n.tr("废纸篓"), systemImage: "trash")
                            .font(.system(size: 13, weight: .bold))
                        GeometryReader { geometry in
                            ZStack(alignment: .leading) {
                                Capsule().fill(.white.opacity(0.15))
                                Capsule().fill(Palette.blue)
                                    .frame(width: geometry.size.width * min(1, Double(diskSupplement.trash.bytes) / 2_000_000_000))
                            }
                        }
                        .frame(height: 4)
                        Text(trashUsageDescription)
                            .font(.system(size: 11))
                            .foregroundStyle(diskSupplement.trashRootReadable ? Palette.muted : Palette.yellow)
                            .help(diskSupplement.trashRootReadable ? "" : L10n.tr("请检查 Lumine 的完全磁盘访问权限。"))
                        HStack {
                            if let notice = diskSupplement.trashNotice {
                                Text(notice).font(.system(size: 10)).foregroundStyle(Palette.muted).lineLimit(1)
                            }
                            if !diskSupplement.trashRootReadable && !diskSupplement.isLoading {
                                Button(L10n.tr("授权访问…")) {
                                    diskSupplement.authorizeTrash(path: selectedDiskPath)
                                }
                                .buttonStyle(.plain)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(Palette.cyan)
                                .help(L10n.tr("在完全磁盘访问权限中添加并启用 Lumine，然后退出并重新打开 App。"))
                                .contextMenu {
                                    Button(L10n.tr("选择废纸篓文件夹…")) {
                                        diskSupplement.chooseTrashFolder(path: selectedDiskPath)
                                    }
                                    Button(L10n.tr("在访达中显示 Lumine")) {
                                        NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL])
                                    }
                                }
                            }
                            Spacer(minLength: 0)
                            Button(diskSupplement.isEmptyingTrash ? L10n.tr("正在清空…") : L10n.tr("释放")) {
                                pendingTrashPath = selectedDiskPath
                                confirmEmptyTrash = true
                            }
                            .buttonStyle(.plain)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Palette.cyan)
                            .disabled(diskSupplement.isEmptyingTrash || diskSupplement.isLoading || !store.selectedVolumeAvailable || !diskSupplement.trashRootReadable || diskSupplement.trash.itemCount == 0)
                        }
                    }
                }
                .frame(width: 200, height: 112)
            }
            if shows(.diskCapacity) {
                HStack(spacing: 10) {
                    infoCard(L10n.tr("已使用"), icon: "internaldrive", value: store.selectedVolumeAvailable ? MetricFormat.diskBytes(Double(max(0, store.selectedVolume.totalBytes - store.selectedVolume.freeBytes))) : L10n.tr("不可用"), note: L10n.tr("当前卷所占空间"))
                    infoCard(L10n.tr("总容量"), icon: "square.stack.3d.up", value: store.selectedVolumeAvailable ? MetricFormat.diskBytes(Double(store.selectedVolume.totalBytes)) : L10n.tr("不可用"), note: L10n.tr("当前所选卷"), tone: 1)
                }
            }
            if shows(.diskExternal) && !m.externalVolumes.isEmpty {
                sectionTitle(L10n.tr("外置驱动器"))
                ForEach(m.externalVolumes.prefix(2)) { volume in
                    volumeRow(volume)
                }
            }
        }
    }

    private func diskCategoryColor(_ category: DiskCategory) -> Color {
        switch category {
        case .documents: Palette.blue
        case .applications: Palette.coral
        case .desktop: Palette.mint
        case .downloads: Color(red: 0.98, green: 0.56, blue: 0.95)
        case .other: Palette.text
        }
    }

    private var memoryContent: some View {
        VStack(alignment: .leading, spacing: 21) {
            HStack(spacing: 16) {
                RingChart(
                    segments: memorySegments,
                    main: m.has(.memory) ? MetricFormat.bytes(Double(store.selectedMemoryFree), decimals: 2) : L10n.tr("不可用"),
                    subtitle: L10n.tr("可用空间\n共 \(m.has(.memory) ? MetricFormat.bytes(Double(m.memoryTotal), decimals: 0) : L10n.tr("不可用"))")
                )
                VStack(alignment: .leading, spacing: 9) {
                    legend(L10n.tr("活跃内存"), color: Palette.cyan, value: m.has(.memory) ? MetricFormat.bytes(Double(m.memoryActive)) : L10n.tr("不可用"))
                    legend(L10n.tr("联动内存"), color: Palette.blue, value: m.has(.memory) ? MetricFormat.bytes(Double(m.memoryWired)) : L10n.tr("不可用"))
                    legend(L10n.tr("压缩"), color: Palette.violet, value: m.has(.memory) ? MetricFormat.bytes(Double(m.memoryCompressed)) : L10n.tr("不可用"))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.leading, 16)
            .padding(.vertical, 8)
            if shows(.memoryPressure) || shows(.memorySwap) {
                HStack(spacing: 10) {
                    if shows(.memoryPressure) {
                        insightCard(L10n.tr("压力"), icon: "memorychip", value: m.has(.memory) ? MetricFormat.percent(m.memoryPressureEstimate) : L10n.tr("不可用"),
                                    message: memoryPressureMessage, link: KnowledgeLink.memoryPressure, accent: Palette.yellow)
                    }
                    if shows(.memorySwap) {
                        insightCard(L10n.tr("交换分区"), icon: "externaldrive", value: m.has(.swap) ? MetricFormat.bytes(Double(m.swapUsed)) : L10n.tr("不可用"),
                                    message: !m.has(.swap) ? L10n.tr("不可用") : (m.swapUsed == 0 ? L10n.tr("没有使用磁盘交换空间。") : L10n.tr("虚拟内存占用了磁盘空间。")),
                                    link: KnowledgeLink.memorySwap, tone: 1)
                    }
                }
            }
            if shows(.memoryProcesses) { processSection(mode: .memory) }
        }
    }

    private var memoryPressureMessage: String {
        guard m.has(.memory) else { return L10n.tr("不可用") }
        let pressure = m.memoryPressureEstimate
        if m.memoryPressureLevel == 4 || (m.memoryPressureLevel == nil && pressure >= 90) { return L10n.tr("内存压力估算已达临界，建议关闭占用较高的应用。") }
        if m.memoryPressureLevel == 2 || (m.memoryPressureLevel == nil && pressure >= 70) { return L10n.tr("考虑退出暂不使用的应用，减轻内存压力。") }
        return L10n.tr("当前内存压力估算正常。")
    }

    private var memorySegments: [(Double, Color)] {
        guard m.memoryTotal > 0 else { return [] }
        let total = Double(m.memoryTotal)
        let active = min(1, Double(m.memoryActive) / total)
        let wired = min(1 - active, Double(m.memoryWired) / total)
        let compressed = min(1 - active - wired, Double(m.memoryCompressed) / total)
        return [(active, Palette.cyan), (wired, Palette.blue), (compressed, Palette.violet)]
    }

    private var batteryContent: some View {
        VStack(alignment: .leading, spacing: 23) {
            if let percentage = m.batteryPercent {
                HStack(spacing: 16) {
                    RingChart(segments: [(Double(percentage) / 100, Palette.mint)], main: "\(percentage)%", subtitle: L10n.tr("电池电量"), segmented: true)
                    VStack(alignment: .leading, spacing: 12) {
                        Text(m.batteryCharging ? L10n.tr("充电中") : (m.batteryOnAC ? L10n.tr("已接入电源") : L10n.tr("放电中")))
                            .font(.system(size: 15, weight: .bold))
                        Text(m.batteryOnAC && !m.batteryCharging ? L10n.tr("电池已充满或暂停充电") : MetricFormat.duration(m.batteryMinutes))
                            .font(.system(size: 12)).foregroundStyle(Palette.muted)
                        if shows(.batteryCycles), let cycles = m.batteryCycles {
                            Text("\(cycles) / \(m.batteryDesignCycles.map(String.init) ?? "—")")
                                .font(.system(size: 15, weight: .bold))
                            Text(L10n.tr("循环次数"))
                                .font(.system(size: 12)).foregroundStyle(Palette.muted)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.leading, 16)
                .padding(.vertical, 8)
                if shows(.batteryHealth) || shows(.batteryTemperature) {
                    HStack(spacing: 10) {
                        if shows(.batteryHealth) {
                            insightCard(L10n.tr("运行状况"), icon: "heart.fill", value: m.batteryHealthPercent.map { MetricFormat.percent($0) } ?? L10n.tr("不可用"),
                                        message: batteryHealthMessage, link: KnowledgeLink.batteryHealth, accent: Palette.mint)
                        }
                        if shows(.batteryTemperature) {
                            insightCard(L10n.tr("温度"), icon: "thermometer", value: TemperatureStatus.label(m.batteryTemperature) ?? L10n.tr("不可用"),
                                        message: batteryTemperatureMessage, link: KnowledgeLink.batteryTemperature,
                                        accent: temperatureColor(TemperatureStatus.battery(m.batteryTemperature)), tone: 1)
                        }
                    }
                }
                if shows(.batteryProcesses) { processSection(mode: .battery) }
            } else {
                emptyState(icon: "battery.0percent", message: store.batteryPreviouslyPresent ? L10n.tr("不可用") : L10n.tr("这台 Mac 没有报告内置电池。"))
            }
        }
    }

    private var batteryHealthMessage: String {
        guard let health = m.batteryHealthPercent else { return L10n.tr("目前无法计算电池的健康状况。") }
        if health <= 10 { return L10n.tr("电池健康状况较差，建议检查或更换。") }
        if health < 80 { return L10n.tr("电池容量有所下降，仍可继续使用。") }
        return L10n.tr("电池状况良好，可能已损失少量容量。")
    }

    private var batteryTemperatureMessage: String {
        switch TemperatureStatus.battery(m.batteryTemperature) {
        case .warning:
            return (m.batteryTemperature ?? 0) < 10
                ? L10n.tr("电池温度偏低，建议移至温暖环境。")
                : L10n.tr("电池温度偏高，请注意散热。")
        case .normal: return L10n.tr("电池温度处于理想范围。")
        case .unavailable: return L10n.tr("目前无法读取电池温度。")
        case .critical: return L10n.tr("电池温度偏高，请注意散热。")
        }
    }

    private func temperatureColor(_ status: TemperatureStatus) -> Color {
        switch status {
        case .normal: Palette.text
        case .warning: Palette.yellow
        case .critical: Palette.coral
        case .unavailable: Palette.muted
        }
    }

    private var gpuUsageHelp: String {
        store.selectedGPU?.utilizationSource == .interval
            ? L10n.tr("使用率为本次采样窗口内 GPU 活跃时间占比。渲染和平铺来自驱动快照，不能直接比较或相加；活动监视器的采样窗口可能不同。")
            : L10n.tr("当前使用率来自驱动快照，可能与活动监视器的区间统计不同。")
    }

    private var gpuContent: some View {
        VStack(alignment: .leading, spacing: 22) {
            Picker("GPU", selection: Binding(
                get: { preferences.values.gpuSource },
                set: { preferences.values.gpuSource = $0; store.gpuSourceChanged() }
            )) {
                Text(L10n.tr("自动选择")).tag("auto")
                ForEach(m.gpus) { gpu in Text(gpu.name).tag(gpu.id) }
                if preferences.values.gpuSource != "auto", !m.gpus.contains(where: { $0.id == preferences.values.gpuSource }) {
                    Text(L10n.tr("不可用")).tag(preferences.values.gpuSource)
                }
            }
            if let gpu = store.selectedGPU {
                Text(gpu.name).font(.system(size: 15, weight: .semibold))
            }
            if shows(.gpuChart) {
                HStack(alignment: .top, spacing: 18) {
                    HistoryChart(primary: store.gpuHistory, secondary: store.gpuRendererHistory,
                                 primaryColor: Palette.blue, secondaryColor: Palette.coral, ceiling: 100,
                                 tertiary: store.gpuTilerHistory, tertiaryColor: Palette.cyan, secondaryDash: [5, 3])
                        .help(L10n.tr("蓝色实线：使用率；红色长虚线：渲染；青色短虚线：平铺。数值相同时曲线可能重叠。"))
                        .frame(height: 134)
                        .overlay {
                            if [store.selectedGPU?.utilization, store.selectedGPU?.renderer, store.selectedGPU?.tiler].allSatisfy({ $0 == nil }) {
                                Text(L10n.tr("不可用")).foregroundStyle(Palette.muted)
                            }
                        }
                    VStack(alignment: .leading, spacing: 15) {
                        legend(L10n.tr("使用率"), color: Palette.blue, value: store.selectedGPU?.utilization.map(MetricFormat.percent) ?? L10n.tr("不可用"))
                            .help(gpuUsageHelp)
                        legend(L10n.tr("渲染"), color: Palette.coral, value: store.selectedGPU?.renderer.map(MetricFormat.percent) ?? L10n.tr("不可用"))
                        legend(L10n.tr("平铺"), color: Palette.cyan, value: store.selectedGPU?.tiler.map(MetricFormat.percent) ?? L10n.tr("不可用"))
                    }
                    .frame(width: 98, alignment: .leading)
                }
            }
            if shows(.gpuMemory) || shows(.gpuCores) {
                HStack(spacing: 10) {
                    if shows(.gpuMemory) {
                        MetricCard(selected: false) {
                            VStack(alignment: .leading, spacing: 10) {
                                Label(L10n.tr("GPU 已用内存"), systemImage: "memorychip").font(.system(size: 13, weight: .bold))
                                Text(store.selectedGPU?.memoryUsed.map { MetricFormat.bytes(Double($0)) } ?? L10n.tr("不可用"))
                                    .font(.system(size: 24, weight: .semibold)).foregroundStyle(Palette.yellow)
                                Text(L10n.tr("驱动报告的系统内存用量，包含共享内存。"))
                                    .font(.system(size: 11)).foregroundStyle(Palette.muted)
                            }
                        }
                    }
                    if shows(.gpuCores) {
                        MetricCard(selected: false, tone: 1) {
                            VStack(alignment: .leading, spacing: 10) {
                                Label(L10n.tr("GPU 核心"), systemImage: "cpu").font(.system(size: 13, weight: .bold))
                                Text(store.selectedGPU?.coreCount.map { String($0) } ?? L10n.tr("不可用"))
                                    .font(.system(size: 24, weight: .semibold)).foregroundStyle(Palette.cyan)
                                Text(L10n.tr("驱动未提供的指标显示为不可用。"))
                                    .font(.system(size: 11)).foregroundStyle(Palette.muted)
                            }
                        }
                    }
                }
                .frame(height: 142)
            }
            Text(L10n.tr("三项统计口径不同，不能相加。"))
                .font(.system(size: 11)).foregroundStyle(Palette.muted)
        }
    }

    private var cpuContent: some View {
        VStack(alignment: .leading, spacing: 22) {
            if shows(.cpuChart) {
                HStack(alignment: .top, spacing: 18) {
                    HistoryChart(primary: store.cpuHistory, secondary: nil, primaryColor: Palette.blue, secondaryColor: Palette.coral, ceiling: 100)
                        .frame(height: 134)
                    VStack(alignment: .leading, spacing: 15) {
                        legend(L10n.tr("可用"), color: Palette.purple, value: store.selectedCPUAvailable ? MetricFormat.percent(100 - store.selectedCPU.total) : L10n.tr("不可用"))
                        legend(L10n.tr("用户"), color: Palette.blue, value: store.selectedCPUAvailable ? MetricFormat.percent(store.selectedCPU.user) : L10n.tr("不可用"))
                        legend(L10n.tr("系统"), color: Palette.coral, value: store.selectedCPUAvailable ? MetricFormat.percent(store.selectedCPU.system) : L10n.tr("不可用"))
                    }
                    .frame(width: 98, alignment: .leading)
                }
            }
            if shows(.cpuUptime) || shows(.cpuTemperature) {
                HStack(spacing: 10) {
                    if shows(.cpuUptime) {
                        insightCard(L10n.tr("正常运行时间"), icon: "clock", value: uptimeText,
                                    message: m.uptime < 7 * 86400 ? L10n.tr("您的 Mac 最近重新启动过。") : L10n.tr("Mac 已运行较长时间，可考虑重启。"),
                                    link: KnowledgeLink.cpuUptime)
                    }
                    if shows(.cpuTemperature) {
                        insightCard(L10n.tr("温度"), icon: "thermometer", value: store.selectedTemperature.map { String(format: "%.0f°C", $0) } ?? L10n.tr("不可用"),
                                    message: cpuTemperatureMessage, link: KnowledgeLink.cpuTemperature,
                                    accent: cpuTemperatureColor, tone: 1)
                    }
                }
            }
            if shows(.cpuProcesses) { processSection(mode: .cpu) }
        }
    }

    private var cpuTemperatureMessage: String {
        guard let temperature = store.selectedTemperature else { return L10n.tr("当前无法读取 CPU 温度。") }
        if temperature >= 76 { return L10n.tr("CPU 温度过高，请注意散热。") }
        if temperature >= 56 { return L10n.tr("您的 Mac 正在升温，但温度读数仍在常见范围内。") }
        return L10n.tr("CPU 温度处于理想工作范围。")
    }

    private var cpuTemperatureColor: Color {
        guard let temperature = store.selectedTemperature else { return Palette.muted }
        if temperature >= 76 { return Palette.coral }
        if temperature >= 56 { return Palette.yellow }
        return Palette.text
    }

    private var uptimeText: String {
        let hours = Int(m.uptime) / 3600
        return hours >= 24 ? L10n.tr("\(hours / 24) 天 \(hours % 24) 小时") : L10n.tr("\(hours) 小时")
    }

    private var networkContent: some View {
        VStack(alignment: .leading, spacing: 22) {
            if shows(.networkConnection) {
                MetricCard(selected: false, tone: 0.5) {
                    VStack(alignment: .leading, spacing: 9) {
                        HStack(spacing: 10) {
                            Image(systemName: "wifi").font(.system(size: 24))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(m.has(.network) ? m.networkName : L10n.tr("不可用")).font(.system(size: 14, weight: .bold))
                                Text(!m.has(.network) ? L10n.tr("不可用") : (m.networkInterface.isEmpty ? L10n.tr("未连接") : L10n.tr("接口 \(m.networkInterface)")))
                                    .font(.system(size: 11)).foregroundStyle(Palette.muted)
                            }
                            Spacer()
                            if let strong = m.networkSecurityStrong {
                                Text(strong ? L10n.tr("强") : L10n.tr("弱"))
                                    .foregroundStyle(strong ? Palette.mint : Palette.yellow)
                            }
                        }
                        Text(networkSecurityMessage).font(.system(size: 11)).foregroundStyle(Palette.muted)
                        knowledgeLink(KnowledgeLink.networkSecurity)
                    }
                }
                .frame(height: 110)
            }
            if shows(.networkDownload) || shows(.networkUpload) {
                HStack(spacing: 10) {
                    if shows(.networkDownload) {
                        networkGraph(L10n.tr("下载"), total: m.has(.network) ? networkTotals.download : nil, speed: m.has(.network) ? m.downloadBytesPerSecond : nil, history: store.downloadHistory, color: Palette.blue, tone: 0)
                    }
                    if shows(.networkUpload) {
                        networkGraph(L10n.tr("上传"), total: m.has(.network) ? networkTotals.upload : nil, speed: m.has(.network) ? m.uploadBytesPerSecond : nil, history: store.uploadHistory, color: Palette.coral, tone: 1)
                    }
                }
            }
            if shows(.networkSpeedTest) { speedTestSection }
        }
    }

    private var networkTotals: (download: UInt64, upload: UInt64) {
        store.trafficHistory.totals(interface: m.networkInterface, minutes: preferences.values.trafficWindowMinutes)
    }

    private var networkSecurityMessage: String {
        guard m.has(.network) else { return L10n.tr("不可用") }
        guard !m.networkInterface.isEmpty else { return L10n.tr("当前没有可用的网络连接。") }
        let security = L10n.lookup(m.networkSecurity)
        if let strong = m.networkSecurityStrong {
            return strong ? L10n.tr("网络安全设置：强（\(security)）。") : L10n.tr("网络安全设置：较弱（\(security)）。")
        }
        return L10n.tr("当前使用 \(m.networkSecurity.isEmpty ? m.networkInterface : security)。")
    }

    private func networkGraph(_ name: String, total: UInt64?, speed: Double?, history: [Double], color: Color, tone: Double) -> some View {
        MetricCard(selected: false, tone: tone) {
            VStack(alignment: .leading, spacing: 7) {
                Text(name).font(.system(size: 13, weight: .bold))
                HStack {
                    Text(total.map { MetricFormat.diskBytes(Double($0)) } ?? L10n.tr("不可用"))
                        .help(L10n.tr("最近 \(preferences.values.trafficWindowMinutes) 分钟的累计\(name)流量"))
                    Spacer(minLength: 2)
                    Text(speed.map(MetricFormat.speed) ?? L10n.tr("不可用"))
                }
                .font(.system(size: 11)).foregroundStyle(Palette.muted).lineLimit(1)
                HistoryChart(primary: history, secondary: nil, primaryColor: color, secondaryColor: color, ceiling: max(history.max() ?? 0, 1024))
                    .frame(height: 62)
            }
        }
        .frame(height: 123)
    }

    private var speedTestSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionTitle(L10n.tr("测试您的网络连接"))
            HStack(alignment: .center, spacing: 24) {
                Button {
                    if speedTest.phase == .download || speedTest.phase == .upload { speedTest.cancel() }
                    else { speedTest.start() }
                } label: {
                    ZStack {
                        Circle().stroke(Palette.text.opacity(0.14), lineWidth: 1)
                            .frame(width: 152, height: 152)
                        Circle().fill(Palette.text.opacity(0.055))
                            .frame(width: 130, height: 130)
                        VStack(spacing: 5) {
                            if speedTest.phase == .download || speedTest.phase == .upload {
                                ProgressView().controlSize(.small)
                            }
                            Text(speedTest.phase == .download ? L10n.tr("测试下载中") :
                                 speedTest.phase == .upload ? L10n.tr("测试上传中") :
                                 speedTest.phase == .finished ? L10n.tr("重新测试") : L10n.tr("测试网速"))
                                .font(.system(size: 13, weight: .semibold))
                        }
                    }
                }
                .buttonStyle(.plain)
                .disabled(m.networkInterface.isEmpty)
                VStack(alignment: .leading, spacing: 9) {
                    Text(speedTest.phase == .finished ? L10n.tr("测试结果") : L10n.tr("运作方式"))
                        .font(.system(size: 13, weight: .bold))
                    if speedTest.phase == .finished {
                        Text(L10n.tr("下载  \(String(format: "%.1f", speedTest.downloadMbps ?? 0)) Mb/s"))
                        Text(L10n.tr("上传  \(String(format: "%.1f", speedTest.uploadMbps ?? 0)) Mb/s"))
                    } else if speedTest.phase == .failed {
                        Text(speedTest.errorMessage ?? L10n.tr("测速失败"))
                    } else {
                        Text(L10n.tr("点击后经 Cloudflare 测试下载和上传速度，约传输 28 MB 测试数据。"))
                    }
                }
                .font(.system(size: 11))
                .foregroundStyle(Palette.muted)
                .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 8)
        }
        .frame(height: 225, alignment: .top)
    }

    private var devicesContent: some View {
        VStack(alignment: .leading, spacing: 22) {
            Text(L10n.tr("将无线或有线设备连接到您的 Mac 后，它们将在此处显示。"))
                .font(.system(size: 12)).foregroundStyle(Palette.muted)
                .frame(maxWidth: .infinity, minHeight: 65)
            if shows(.devicesExternal) {
                sectionTitle(L10n.tr("外置驱动器"))
                if m.externalVolumes.isEmpty {
                    Text(m.has(.externalVolumes) ? L10n.tr("连接后，外部存储设备会在这里显示。") : L10n.tr("不可用"))
                        .font(.system(size: 12)).foregroundStyle(Palette.muted)
                        .frame(maxWidth: .infinity, minHeight: 65)
                } else {
                    ForEach(m.externalVolumes.prefix(2)) { volume in volumeRow(volume) }
                }
            }
        }
    }

    private func volumeRow(_ volume: ExternalVolume) -> some View {
        MetricCard(selected: false, tone: 0.5) {
            HStack(spacing: 10) {
                Image(systemName: "externaldrive.fill").font(.system(size: 20))
                VStack(alignment: .leading, spacing: 4) {
                    Text(volume.name).font(.system(size: 13, weight: .bold))
                    Text(L10n.tr("可用 \(volume.totalBytes > 0 ? MetricFormat.diskBytes(Double(volume.freeBytes)) : L10n.tr("不可用")) · 共 \(volume.totalBytes > 0 ? MetricFormat.diskBytes(Double(volume.totalBytes)) : L10n.tr("不可用"))"))
                        .font(.system(size: 11)).foregroundStyle(Palette.muted)
                }
                Spacer()
            }
        }
        .frame(height: 64)
    }

    private func processSection(mode: DetailKind) -> some View {
        let ranked = Array(m.processes.sorted { mode == .memory ? $0.memoryBytes > $1.memoryBytes : $0.cpuPercent > $1.cpuPercent }.prefix(5))
        return VStack(alignment: .leading, spacing: 9) {
            sectionTitle(L10n.tr("使用率排行"))
            HStack {
                Text(L10n.tr("进程名称"))
                Spacer()
                Text(mode == .memory ? L10n.tr("内存") : mode == .battery ? L10n.tr("使用率") : "CPU")
                Text(" ").frame(width: 35)
            }
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(Palette.muted)
            if ranked.isEmpty {
                Text(m.has(.processes) ? L10n.tr("当前没有可见进程。") : (store.processesPreviouslyAvailable ? L10n.tr("不可用") : L10n.tr("正在获取进程数据…")))
                    .font(.system(size: 11)).foregroundStyle(Palette.muted)
            }
            ForEach(ranked) { process in
                HStack(spacing: 9) {
                    if let icon = NSRunningApplication(processIdentifier: process.id)?.icon {
                        Image(nsImage: icon).resizable().frame(width: 20, height: 20)
                    } else {
                        Image(systemName: "app.fill").frame(width: 20, height: 20).foregroundStyle(Palette.muted)
                    }
                    Text(process.name).lineLimit(1)
                    Spacer()
                    Text(mode == .memory ? MetricFormat.bytes(Double(process.memoryBytes)) : String(format: mode == .battery ? "%.1f" : "%.1f%%", process.cpuPercent))
                        .foregroundStyle(process.cpuPercent > 20 || process.memoryBytes > 2_000_000_000 ? Palette.yellow : Palette.muted)
                    Button(L10n.tr("关闭")) {
                        pendingProcess = process
                        confirmProcessClose = true
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Palette.cyan)
                    .frame(width: 35, alignment: .trailing)
                    .disabled(process.id == getpid())
                }
                .font(.system(size: 11, weight: .medium))
                .frame(height: 25)
            }
            if let processNotice {
                Text(processNotice).font(.system(size: 10)).foregroundStyle(Palette.muted).lineLimit(1)
            }
        }
        .frame(height: 225, alignment: .top)
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text).font(.system(size: 15, weight: .bold)).padding(.horizontal, 8)
    }

    private func legend(_ name: String, color: Color, value: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Circle().fill(color).frame(width: 8, height: 8).padding(.top, 4)
            VStack(alignment: .leading, spacing: 2) {
                Text(name).font(.system(size: 11)).foregroundStyle(Palette.muted)
                Text(value).font(.system(size: 12, weight: .semibold)).lineLimit(1)
            }
        }
    }

    private func infoCard(_ title: String, icon: String, value: String, note: String, accent: Color = .white, tone: Double = 0) -> some View {
        MetricCard(selected: false, tone: tone) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 7) {
                    Image(systemName: icon).foregroundStyle(Palette.muted)
                    Text(title).font(.system(size: 12, weight: .bold)).lineLimit(1)
                }
                Text(value).font(.system(size: 14, weight: .semibold)).foregroundStyle(accent).lineLimit(1).minimumScaleFactor(0.8)
                Text(note).font(.system(size: 10)).foregroundStyle(Palette.muted).fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(height: 94)
    }

    private func insightCard(_ title: String, icon: String, value: String, message: String,
                             link: String, accent: Color = .white, tone: Double = 0) -> some View {
        MetricCard(selected: false, tone: tone) {
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 7) {
                    Image(systemName: icon).foregroundStyle(Palette.muted)
                    Text(title).font(.system(size: 13, weight: .bold)).lineLimit(1)
                    Spacer(minLength: 1)
                    Text(value).font(.system(size: 13, weight: .semibold)).foregroundStyle(accent).lineLimit(1)
                }
                Text(message).font(.system(size: 11)).foregroundStyle(Palette.muted)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                knowledgeLink(link)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .frame(height: 122)
    }

    private func knowledgeLink(_ address: String) -> some View {
        Button(L10n.tr("了解更多 ↗")) {
            if let url = URL(string: address) { NSWorkspace.shared.open(url) }
        }
        .buttonStyle(.plain)
        .font(.system(size: 11, weight: .semibold))
        .foregroundStyle(Palette.cyan)
        .accessibilityLabel(L10n.tr("打开官方说明网页"))
    }

    private func emptyState(icon: String, message: String) -> some View {
        VStack(spacing: 14) {
            Image(systemName: icon).font(.system(size: 36, weight: .ultraLight)).foregroundStyle(Palette.muted)
            Text(message).font(.system(size: 13)).foregroundStyle(Palette.muted).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 175)
    }
}

private enum KnowledgeLink {
    static let diskHealth = "https://macpaw.com/support/cleanmymac/knowledgebase/disk-health"
    static let diskTemperature = "https://macpaw.com/support/cleanmymac/knowledgebase/disk-temperature"
    static let memoryPressure = "https://macpaw.com/support/cleanmymac/knowledgebase/ram-pressure"
    static let memorySwap = "https://macpaw.com/support/cleanmymac/knowledgebase/swap-file"
    static let batteryHealth = "https://macpaw.com/support/cleanmymac/knowledgebase/battery-health"
    static let batteryTemperature = "https://macpaw.com/support/cleanmymac/knowledgebase/battery-temperature"
    static let cpuUptime = "https://macpaw.com/support/cleanmymac/knowledgebase/mac-uptime"
    static let cpuTemperature = "https://macpaw.com/support/cleanmymac/knowledgebase/cpu-temperature"
    static let networkSecurity = "https://macpaw.com/support/cleanmymac/knowledgebase/network-connection-security"
}
