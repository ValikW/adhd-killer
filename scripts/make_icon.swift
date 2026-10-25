// Draws the app icon: a red crosshair on a dark rounded square.
//   swift scripts/make_icon.swift && iconutil -c icns build/AppIcon.iconset -o Resources/AppIcon.icns
import AppKit

func render(_ size: CGFloat) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size),
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let s = size / 1024
    let ctx = NSGraphicsContext.current!.cgContext

    // Rounded square with the standard macOS margin.
    let tile = CGRect(x: 100 * s, y: 100 * s, width: 824 * s, height: 824 * s)
    let shape = CGPath(roundedRect: tile, cornerWidth: 185 * s, cornerHeight: 185 * s, transform: nil)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -10 * s), blur: 30 * s,
                  color: NSColor.black.withAlphaComponent(0.45).cgColor)
    ctx.addPath(shape); ctx.setFillColor(NSColor.black.cgColor); ctx.fillPath()
    ctx.restoreGState()
    ctx.saveGState()
    ctx.addPath(shape); ctx.clip()
    let bg = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                        colors: [NSColor(red: 0.16, green: 0.17, blue: 0.24, alpha: 1).cgColor,
                                 NSColor(red: 0.05, green: 0.05, blue: 0.09, alpha: 1).cgColor] as CFArray,
                        locations: [0, 1])!
    ctx.drawLinearGradient(bg, start: CGPoint(x: 512 * s, y: 924 * s), end: CGPoint(x: 512 * s, y: 100 * s), options: [])

    let c = CGPoint(x: 512 * s, y: 512 * s)
    // Red glow behind the scope.
    let glow = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                          colors: [NSColor(red: 1, green: 0.23, blue: 0.19, alpha: 0.45).cgColor,
                                   NSColor(red: 1, green: 0.23, blue: 0.19, alpha: 0).cgColor] as CFArray,
                          locations: [0, 1])!
    ctx.drawRadialGradient(glow, startCenter: c, startRadius: 0, endCenter: c, endRadius: 400 * s, options: [])

    let red = NSColor(red: 1, green: 0.27, blue: 0.23, alpha: 1).cgColor
    ctx.setStrokeColor(red)
    ctx.setLineCap(.round)
    // Outer and inner rings.
    ctx.setLineWidth(44 * s)
    ctx.strokeEllipse(in: CGRect(x: c.x - 270 * s, y: c.y - 270 * s, width: 540 * s, height: 540 * s))
    ctx.setLineWidth(30 * s)
    ctx.strokeEllipse(in: CGRect(x: c.x - 135 * s, y: c.y - 135 * s, width: 270 * s, height: 270 * s))
    // Crosshair ticks crossing the outer ring.
    ctx.setLineWidth(40 * s)
    for (dx, dy) in [(0.0, 1.0), (0.0, -1.0), (1.0, 0.0), (-1.0, 0.0)] {
        ctx.move(to: CGPoint(x: c.x + dx * 190 * s, y: c.y + dy * 190 * s))
        ctx.addLine(to: CGPoint(x: c.x + dx * 345 * s, y: c.y + dy * 345 * s))
    }
    ctx.strokePath()
    // Center dot.
    ctx.setFillColor(NSColor.white.cgColor)
    ctx.fillEllipse(in: CGRect(x: c.x - 34 * s, y: c.y - 34 * s, width: 68 * s, height: 68 * s))
    ctx.restoreGState()

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

let dir = URL(fileURLWithPath: "build/AppIcon.iconset")
try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = scale == 1 ? "icon_\(base)x\(base).png" : "icon_\(base)x\(base)@2x.png"
        let data = render(CGFloat(base * scale)).representation(using: .png, properties: [:])!
        try! data.write(to: dir.appendingPathComponent(name))
    }
}
try! render(1024).representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "build/icon-preview.png"))
print("ok")
