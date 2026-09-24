import AppKit
import SwiftUI

@main
struct LumineApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings { EmptyView() }
    }
}

final class MonitorPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let store = MonitorStore()
    private var statusItem: NSStatusItem!
    private var overviewPanel: MonitorPanel!
    private var detailPanel: MonitorPanel!
    private var settingsWindow: NSWindow?
    private var selected: DetailKind?
    private var globalMouseMonitor: Any?
    private var localMouseMonitor: Any?
    private var languageObserver: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        _ = PreferencesStore.shared
        NSApp.setActivationPolicy(.accessory)
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "display", accessibilityDescription: L10n.tr("打开 Lumine 监控"))
            button.image?.isTemplate = true
            button.target = self
            button.action = #selector(toggleOverview)
            button.toolTip = L10n.tr("Lumine 系统监控")
        }
        overviewPanel = makePanel(size: NSSize(width: 446, height: 420))
        detailPanel = makePanel(size: NSSize(width: 446, height: 650))
        updateOverview()
        resizePanels()
        let values = PreferencesStore.shared.values
        DiskCategoryStore.shared.configure(path: values.diskSource,
                                           enabled: values.shows(.diskCategories))

        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor in self?.hidePanels() }
        }
        localMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            guard let self, self.overviewPanel.isVisible else { return event }
            if event.window !== self.overviewPanel && event.window !== self.detailPanel && event.window !== self.statusItem.button?.window {
                self.hidePanels()
            }
            return event
        }
        languageObserver = NotificationCenter.default.addObserver(forName: NSLocale.currentLocaleDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                L10n.systemLanguageDidChange()
                PreferencesStore.shared.objectWillChange.send()
                self?.refreshAppKitLanguage()
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        store.stop()
        DiskCategoryStore.shared.stop()
        DiskSupplementStore.shared.cancel()
        SpeedTestStore.shared.cancel()
        if let globalMouseMonitor { NSEvent.removeMonitor(globalMouseMonitor) }
        if let localMouseMonitor { NSEvent.removeMonitor(localMouseMonitor) }
        if let languageObserver { NotificationCenter.default.removeObserver(languageObserver) }
    }

    @objc private func toggleOverview() {
        if overviewPanel.isVisible {
            hidePanels()
        } else {
            store.setActive(true)
            updateOverview()
            positionPanels()
            overviewPanel.orderFrontRegardless()
        }
    }

    private func makePanel(size: NSSize) -> MonitorPanel {
        let panel = MonitorPanel(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .popUpMenu
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isMovable = true
        panel.isMovableByWindowBackground = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        return panel
    }

    private func updateOverview() {
        overviewPanel.contentView = NSHostingView(rootView: OverviewView(store: store, selected: selected) { [weak self] kind in
            self?.select(kind)
        } openSettings: { [weak self] in
            self?.showSettings()
        })
    }

    private func showSettings() {
        if settingsWindow == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 680, height: 610),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false
            )
            window.title = L10n.tr("Lumine 设置")
            window.minSize = NSSize(width: 630, height: 560)
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: SettingsView(store: store) { [weak self] in
                self?.resizePanels()
                self?.refreshAppKitLanguage()
            })
            window.center()
            settingsWindow = window
        }
        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func refreshAppKitLanguage() {
        statusItem.button?.toolTip = L10n.tr("Lumine 系统监控")
        statusItem.button?.image?.accessibilityDescription = L10n.tr("打开 Lumine 监控")
        settingsWindow?.title = L10n.tr("Lumine 设置")
    }

    private func select(_ kind: DetailKind) {
        if selected == .network { SpeedTestStore.shared.cancel() }
        if selected == kind {
            if kind == .disk {
                DiskSupplementStore.shared.cancel()
            }
            selected = nil
            store.setDetail(nil)
            detailPanel.orderOut(nil)
        } else {
            if selected == .disk {
                DiskSupplementStore.shared.cancel()
            }
            selected = kind
            store.setDetail(kind)
            if kind == .disk {
                let path = store.selectedVolume.id == "startup" ? "/" : store.selectedVolume.id
                let visible = PreferencesStore.shared.values
                if store.selectedVolumeAvailable && (visible.shows(.diskHealth) || visible.shows(.diskTemperature) || visible.shows(.diskTrash)) {
                    DiskSupplementStore.shared.refresh(path: path,
                                                       diagnostics: visible.shows(.diskHealth) || visible.shows(.diskTemperature),
                                                       trash: visible.shows(.diskTrash))
                }
            }
            detailPanel.contentView = NSHostingView(rootView: DetailView(store: store, kind: kind, layoutChanged: { [weak self] in
                self?.resizePanels()
            }))
            resizePanels()
            positionPanels()
            detailPanel.orderFrontRegardless()
        }
        updateOverview()
    }

    private func resizePanels() {
        guard overviewPanel != nil, detailPanel != nil else { return }
        let preferences = PreferencesStore.shared.values
        let hasRow1 = preferences.shows(.overviewDisk) || preferences.shows(.overviewMemory)
        let hasRow2 = preferences.shows(.overviewBattery) || preferences.shows(.overviewCPU)
        let hasRow3 = preferences.shows(.overviewNetwork) || preferences.shows(.overviewDevices)
        var overviewHeight: CGFloat = 420
        if !preferences.shows(.health) { overviewHeight -= 56 }
        if !hasRow1 { overviewHeight -= 88 }
        if !hasRow2 { overviewHeight -= 68 }
        if !hasRow3 { overviewHeight -= 134 }
        overviewPanel.setContentSize(NSSize(width: 446, height: max(90, overviewHeight)))

        if let selected {
            let screen = statusItem.button?.window?.screen ?? NSScreen.main ?? NSScreen.screens[0]
            var height: CGFloat
            switch selected {
            case .disk:
                height = 692
                if !preferences.shows(.diskCategories) { height -= 26 }
                if !preferences.shows(.diskHealth) && !preferences.shows(.diskTemperature) { height -= 140 }
                if !preferences.shows(.diskTrash) { height -= 132 }
                if preferences.shows(.diskCapacity) { height += 112 }
                if preferences.shows(.diskExternal) && !store.metrics.externalVolumes.isEmpty { height += 105 }
            case .memory:
                height = 696
                if !preferences.shows(.memoryPressure) && !preferences.shows(.memorySwap) { height -= 142 }
                if !preferences.shows(.memoryProcesses) { height -= 225 }
            case .battery:
                height = 476
                if !preferences.shows(.batteryHealth) && !preferences.shows(.batteryTemperature) { height -= 142 }
                if preferences.shows(.batteryProcesses) { height += 225 }
            case .cpu:
                height = 670
                if !preferences.shows(.cpuChart) { height -= 160 }
                if !preferences.shows(.cpuUptime) && !preferences.shows(.cpuTemperature) { height -= 142 }
                if !preferences.shows(.cpuProcesses) { height -= 225 }
            case .network:
                height = 615
                if !preferences.shows(.networkConnection) { height -= 132 }
                if !preferences.shows(.networkDownload) && !preferences.shows(.networkUpload) { height -= 145 }
                if !preferences.shows(.networkSpeedTest) { height -= 235 }
            case .devices:
                height = preferences.shows(.devicesExternal) ? 280 : 170
            }
            detailPanel.setContentSize(NSSize(width: 446, height: min(max(110, height), screen.visibleFrame.height - 8)))
        }
        positionPanels()
    }

    private func positionPanels() {
        let anchorScreen = statusItem.button?.window?.screen ?? NSScreen.main ?? NSScreen.screens[0]
        let storedMain = PreferencesStore.shared.values.panelPositions["overview"]?.point
        let mainScreen = storedMain.flatMap { saved in NSScreen.screens.first { $0.visibleFrame.contains(saved) } } ?? anchorScreen
        let visible = mainScreen.visibleFrame
        let top = min(statusItem.button?.window?.frame.minY ?? visible.maxY, visible.maxY) - 3
        let mainSize = overviewPanel.frame.size
        let detailSize = detailPanel.frame.size
        let autoMain = NSPoint(x: visible.maxX - mainSize.width - 6, y: max(visible.minY + 4, top - mainSize.height))
        let mainOrigin = clamped(storedMain ?? autoMain, size: mainSize, in: visible)
        overviewPanel.setFrameOrigin(mainOrigin)

        let leftX = mainOrigin.x - detailSize.width - 5
        let detailX: CGFloat
        if leftX >= visible.minX + 4 {
            detailX = leftX
        } else {
            detailX = max(visible.minX + 4, visible.maxX - detailSize.width - 4)
        }
        let detailY = max(visible.minY + 4, top - detailSize.height)
        let key = "detail.\(selected?.rawValue ?? "disk")"
        let storedDetail = PreferencesStore.shared.values.panelPositions[key]?.point
        let detailScreen = storedDetail.flatMap { saved in NSScreen.screens.first { $0.visibleFrame.contains(saved) } } ?? mainScreen
        detailPanel.setFrameOrigin(clamped(storedDetail ?? NSPoint(x: detailX, y: detailY), size: detailSize, in: detailScreen.visibleFrame))
    }

    private func clamped(_ origin: NSPoint, size: NSSize, in visible: NSRect) -> NSPoint {
        NSPoint(
            x: min(max(origin.x, visible.minX + 4), visible.maxX - size.width - 4),
            y: min(max(origin.y, visible.minY + 4), visible.maxY - size.height - 4)
        )
    }

    private func hidePanels() {
        SpeedTestStore.shared.cancel()
        if selected == .disk {
            DiskSupplementStore.shared.cancel()
        }
        overviewPanel.orderOut(nil)
        detailPanel.orderOut(nil)
        selected = nil
        store.setActive(false)
        updateOverview()
    }
}
