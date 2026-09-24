import AppKit

let output = CommandLine.arguments.dropFirst().first ?? "Lumine/Assets.xcassets/AppIcon.appiconset/icon_1024.png"
let size = 1024
guard let bitmap = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: size,
    pixelsHigh: size,
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0,
    bitsPerPixel: 0
), let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
    fatalError("无法建立图标绘图上下文")
}

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = context
context.imageInterpolation = .high

let bounds = NSRect(x: 64, y: 64, width: 896, height: 896)
let background = NSBezierPath(roundedRect: bounds, xRadius: 190, yRadius: 190)
background.addClip()
NSGradient(starting: NSColor(calibratedRed: 0.09, green: 0.06, blue: 0.23, alpha: 1), ending: NSColor(calibratedRed: 0.38, green: 0.18, blue: 0.64, alpha: 1))!.draw(in: bounds, angle: 35)

NSColor(calibratedWhite: 1, alpha: 0.11).setStroke()
background.lineWidth = 4
background.stroke()

let center = NSPoint(x: 512, y: 512)
let ring = NSBezierPath()
ring.appendArc(withCenter: center, radius: 272, startAngle: 0, endAngle: 360)
ring.lineWidth = 52
NSColor(calibratedWhite: 1, alpha: 0.10).setStroke()
ring.stroke()

let progress = NSBezierPath()
progress.appendArc(withCenter: center, radius: 272, startAngle: 100, endAngle: 405)
progress.lineWidth = 52
progress.lineCapStyle = .round
progress.lineJoinStyle = .round
NSColor(calibratedRed: 0.36, green: 0.90, blue: 0.84, alpha: 0.20).setStroke()
progress.lineWidth = 82
progress.stroke()
progress.lineWidth = 52
NSColor(calibratedRed: 0.45, green: 0.97, blue: 0.83, alpha: 1).setStroke()
progress.stroke()

let pulse = NSBezierPath()
pulse.move(to: NSPoint(x: 238, y: 504))
pulse.line(to: NSPoint(x: 364, y: 504))
pulse.line(to: NSPoint(x: 420, y: 624))
pulse.line(to: NSPoint(x: 504, y: 364))
pulse.line(to: NSPoint(x: 576, y: 550))
pulse.line(to: NSPoint(x: 624, y: 504))
pulse.line(to: NSPoint(x: 786, y: 504))
pulse.lineCapStyle = .round
pulse.lineJoinStyle = .round
pulse.lineWidth = 42
NSColor(calibratedRed: 0.60, green: 0.80, blue: 1, alpha: 0.32).setStroke()
pulse.stroke()
pulse.lineWidth = 24
NSColor.white.setStroke()
pulse.stroke()

context.flushGraphics()
NSGraphicsContext.restoreGraphicsState()

guard let data = bitmap.representation(using: .png, properties: [:]) else { fatalError("图标编码失败") }
try data.write(to: URL(fileURLWithPath: output))
