// Draws the app icon (a document with syntax-coloured lines on a blue–teal tile, following
// Apple's macOS icon grid) and writes Resources/AppIcon.icns. Run: swift Scripts/make-icon.swift
import AppKit

func color(_ hex: UInt32, alpha: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

func withShadow(blur: CGFloat, offsetY: CGFloat, opacity: CGFloat, _ draw: () -> Void) {
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowBlurRadius = blur
    shadow.shadowOffset = NSSize(width: 0, height: offsetY)
    shadow.shadowColor = NSColor.black.withAlphaComponent(opacity)
    shadow.set()
    draw()
    NSGraphicsContext.restoreGraphicsState()
}

func drawIcon() {
    // Tile: 824pt rounded square centred on the 1024pt canvas.
    let tile = NSBezierPath(roundedRect: NSRect(x: 100, y: 100, width: 824, height: 824), xRadius: 185, yRadius: 185)
    withShadow(blur: 28, offsetY: -12, opacity: 0.28) {
        color(0x2F5BEA).setFill()
        tile.fill()
    }
    NSGradient(starting: color(0x3D63F0), ending: color(0x14B8A6))!.draw(in: tile, angle: -55)

    // Page with a folded top-right corner.
    let page = NSRect(x: 262, y: 196, width: 500, height: 632)
    let fold: CGFloat = 120
    let sheet = NSBezierPath()
    sheet.move(to: NSPoint(x: page.minX, y: page.minY))
    sheet.line(to: NSPoint(x: page.maxX, y: page.minY))
    sheet.line(to: NSPoint(x: page.maxX, y: page.maxY - fold))
    sheet.line(to: NSPoint(x: page.maxX - fold, y: page.maxY))
    sheet.line(to: NSPoint(x: page.minX, y: page.maxY))
    sheet.close()
    withShadow(blur: 24, offsetY: -10, opacity: 0.25) {
        NSColor.white.setFill()
        sheet.fill()
    }
    let corner = NSBezierPath()
    corner.move(to: NSPoint(x: page.maxX - fold, y: page.maxY))
    corner.line(to: NSPoint(x: page.maxX - fold, y: page.maxY - fold))
    corner.line(to: NSPoint(x: page.maxX, y: page.maxY - fold))
    corner.close()
    color(0xD5DDEB).setFill()
    corner.fill()

    // Syntax-coloured "code" lines: (indent, width, colour) segments per row.
    let blue = color(0x2F5BEA), red = color(0xE5484D), purple = color(0x8E4EC6)
    let green = color(0x30A46C), orange = color(0xF76B15), grey = color(0x9AA4B5)
    let rows: [[(x: CGFloat, width: CGFloat, color: NSColor)]] = [
        [(0, 70, blue), (86, 100, red), (202, 96, purple)],
        [(44, 230, green)],
        [(44, 64, blue), (124, 150, orange)],
        [(44, 200, grey)],
        [(44, 120, purple), (180, 80, red)],
        [(0, 90, blue)],
    ]
    let barHeight: CGFloat = 30
    for (index, row) in rows.enumerated() {
        let y = page.maxY - 170 - CGFloat(index) * 68
        for segment in row {
            segment.color.setFill()
            NSBezierPath(roundedRect: NSRect(x: page.minX + 56 + segment.x, y: y, width: segment.width, height: barHeight),
                         xRadius: barHeight / 2, yRadius: barHeight / 2).fill()
        }
    }
}

func png(pixels: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: 1024, height: 1024)  // draw in 1024pt units at any pixel size
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    drawIcon()
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let root = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent().deletingLastPathComponent()
let iconset = FileManager.default.temporaryDirectory.appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for points in [16, 32, 128, 256, 512] {
    try png(pixels: points).write(to: iconset.appendingPathComponent("icon_\(points)x\(points).png"))
    try png(pixels: points * 2).write(to: iconset.appendingPathComponent("icon_\(points)x\(points)@2x.png"))
}
try png(pixels: 1024).write(to: root.appendingPathComponent("Resources/AppIcon.png"))

let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", root.appendingPathComponent("Resources/AppIcon.icns").path]
try iconutil.run()
iconutil.waitUntilExit()
print(iconutil.terminationStatus == 0 ? "Wrote Resources/AppIcon.icns" : "iconutil failed")
