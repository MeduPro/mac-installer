// Zeichnet das App-Symbol (1024×1024 PNG): weißer Bildschirm mit Download-Pfeil auf einer
// Kachel in MeduPro-Violett (#7038d8).
// Aufruf: swift scripts/make-icon.swift <ausgabe.png>
import AppKit

let size: CGFloat = 1024
let output = CommandLine.arguments.dropFirst().first ?? "AppIcon-1024.png"

let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { _ in
    guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
    let space = CGColorSpace(name: CGColorSpace.sRGB)!

    func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
        CGColor(colorSpace: space, components: [r, g, b, a])!
    }
    func hex(_ value: Int, _ a: CGFloat = 1) -> CGColor {
        color(CGFloat((value >> 16) & 0xFF) / 255, CGFloat((value >> 8) & 0xFF) / 255, CGFloat(value & 0xFF) / 255, a)
    }

    // Kachel im macOS-Raster (824 pt, 100 pt Rand) mit weichem Schatten und violettem Verlauf.
    let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
    let tilePath = CGPath(roundedRect: tile, cornerWidth: 185, cornerHeight: 185, transform: nil)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: color(0, 0, 0, 0.28))
    ctx.addPath(tilePath)
    ctx.setFillColor(hex(0x7038D8))
    ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(tilePath)
    ctx.clip()
    let background = CGGradient(colorsSpace: space,
                                colors: [hex(0x8B5CF0), hex(0x7038D8), hex(0x5527AE)] as CFArray,
                                locations: [0, 0.5, 1])!
    ctx.drawLinearGradient(background, start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 100), options: [])
    ctx.restoreGState()

    // Bildschirm: weißes Gehäuse, Standfuß, Anzeige in hellem Violett.
    let white = color(1, 1, 1)
    let display = CGRect(x: 222, y: 370, width: 580, height: 400)
    // Gehäuse, Hals und Fuß als eine Form, damit der Schatten nur außen fällt.
    let monitor = CGMutablePath()
    monitor.addPath(CGPath(roundedRect: display, cornerWidth: 44, cornerHeight: 44, transform: nil))
    monitor.move(to: CGPoint(x: 462, y: 380))
    monitor.addLine(to: CGPoint(x: 444, y: 262))
    monitor.addLine(to: CGPoint(x: 580, y: 262))
    monitor.addLine(to: CGPoint(x: 562, y: 380))
    monitor.closeSubpath()
    monitor.addPath(CGPath(roundedRect: CGRect(x: 372, y: 232, width: 280, height: 44),
                           cornerWidth: 22, cornerHeight: 22, transform: nil))
    ctx.saveGState()
    ctx.beginTransparencyLayer(auxiliaryInfo: nil)
    ctx.setShadow(offset: CGSize(width: 0, height: -14), blur: 30, color: hex(0x2A0F66, 0.45))
    ctx.beginTransparencyLayer(auxiliaryInfo: nil)
    ctx.setShadow(offset: .zero, blur: 0, color: nil)
    ctx.addPath(monitor)
    ctx.setFillColor(white)
    ctx.fillPath(using: .winding)
    ctx.endTransparencyLayer()
    ctx.endTransparencyLayer()
    ctx.restoreGState()

    let screen = display.insetBy(dx: 30, dy: 30)
    ctx.saveGState()
    ctx.addPath(CGPath(roundedRect: screen, cornerWidth: 20, cornerHeight: 20, transform: nil))
    ctx.clip()
    let glass = CGGradient(colorsSpace: space,
                           colors: [hex(0xF1EAFF), hex(0xDCCBFF)] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(glass, start: CGPoint(x: 512, y: screen.maxY), end: CGPoint(x: 512, y: screen.minY), options: [])
    ctx.restoreGState()

    // Download-Pfeil mit Ablage-Linie in MeduPro-Violett.
    let arrow = CGMutablePath()
    arrow.move(to: CGPoint(x: 512, y: 690))
    arrow.addLine(to: CGPoint(x: 512, y: 478))
    arrow.move(to: CGPoint(x: 428, y: 562))
    arrow.addLine(to: CGPoint(x: 512, y: 478))
    arrow.addLine(to: CGPoint(x: 596, y: 562))
    ctx.addPath(arrow)
    ctx.setStrokeColor(hex(0x7038D8))
    ctx.setLineWidth(46)
    ctx.setLineCap(.round)
    ctx.setLineJoin(.round)
    ctx.strokePath()
    ctx.move(to: CGPoint(x: 418, y: 432))
    ctx.addLine(to: CGPoint(x: 606, y: 432))
    ctx.setLineWidth(34)
    ctx.strokePath()
    return true
}

let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size),
                           bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                           colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
image.draw(in: NSRect(x: 0, y: 0, width: size, height: size))
NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(filePath: output))
print("Symbol geschrieben: \(output)")
