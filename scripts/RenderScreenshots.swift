import AppKit
import SwiftUI

@main
struct Preview {
    @MainActor static func main() {
        _ = NSApplication.shared
        NSApp.appearance = NSAppearance(named: .darkAqua)
        _ = PreferencesStore.shared
        L10n.configure("zh-Hans")
        let store = MonitorStore()
        store.setActive(true)
        store.setDetail(.gpu)
        RunLoop.current.run(until: Date().addingTimeInterval(3))
        store.refresh()
        RunLoop.current.run(until: Date().addingTimeInterval(3))
        let output = CommandLine.arguments[1]
        capture(OverviewView(store: store, selected: nil, select: { _ in }, openSettings: {}).frame(width: 446, height: 488), to: output + "/overview.png")
        capture(HStack(alignment: .top, spacing: 12) {
            DetailView(store: store, kind: .gpu, layoutChanged: {}).frame(width: 446, height: 777)
            OverviewView(store: store, selected: .gpu, select: { _ in }, openSettings: {}).frame(width: 446, height: 488)
        }.padding(16).background(Color(red: 0.06, green: 0.04, blue: 0.14)), to: output + "/gpu.png")
        store.stop()
    }
    @MainActor static func capture<V: View>(_ view: V, to path: String) {
        let hosting = NSHostingView(rootView: view)
        let size = hosting.fittingSize
        hosting.frame = NSRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: hosting.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = hosting
        hosting.layoutSubtreeIfNeeded()
        hosting.displayIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.5))
        guard let bitmap = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else { fatalError("Rendering failed") }
        hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
        guard let png = bitmap.representation(using: .png, properties: [:]) else { fatalError("PNG failed") }
        try! png.write(to: URL(fileURLWithPath: path))
    }
}
