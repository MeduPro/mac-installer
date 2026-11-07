// Zeichnet das App-Symbol (1024×1024 PNG): Tomate mit Download-Pfeil auf hellem Grund.
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

    // Grundfläche im macOS-Raster (824 pt Kachel, 100 pt Rand) mit weichem Schatten.
    let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
    let tilePath = CGPath(roundedRect: tile, cornerWidth: 185, cornerHeight: 185, transform: nil)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: color(0, 0, 0, 0.28))
    ctx.addPath(tilePath)
    ctx.setFillColor(color(1, 1, 1))
    ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(tilePath)
    ctx.clip()
    let background = CGGradient(colorsSpace: space,
                                colors: [color(1.00, 0.97, 0.93), color(0.98, 0.89, 0.83)] as CFArray,
                                locations: [0, 1])!
    ctx.drawLinearGradient(background, start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 100), options: [])
    ctx.restoreGState()

    // Tomate: leicht gestauchter Kreis mit Kugel-Verlauf.
    let body = CGRect(x: 232, y: 212, width: 560, height: 500)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -14), blur: 30, color: color(0.55, 0.08, 0.04, 0.35))
    ctx.addEllipse(in: body)
    ctx.setFillColor(color(0.85, 0.22, 0.16))
    ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addEllipse(in: body)
    ctx.clip()
    let shine = CGGradient(colorsSpace: space,
                           colors: [color(1.00, 0.45, 0.33), color(0.90, 0.25, 0.18), color(0.70, 0.13, 0.10)] as CFArray,
                           locations: [0, 0.55, 1])!
    ctx.drawRadialGradient(shine, startCenter: CGPoint(x: 420, y: 560), startRadius: 0,
                           endCenter: CGPoint(x: 512, y: 462), endRadius: 330, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    // Glanzlicht
    ctx.setFillColor(color(1, 1, 1, 0.28))
    ctx.fillEllipse(in: CGRect(x: 320, y: 545, width: 150, height: 85))
    ctx.restoreGState()

    // Kelchblätter: fünf spitze Blätter um den Stiel.
    let center = CGPoint(x: 512, y: 690)
    let leaves = CGMutablePath()
    for i in 0..<5 {
        let angle = CGFloat(i) / 5 * 2 * .pi + .pi / 2
        let tip = CGPoint(x: center.x + cos(angle) * 150, y: center.y + sin(angle) * 62)
        let left = CGPoint(x: center.x + cos(angle - 0.55) * 46, y: center.y + sin(angle - 0.55) * 30)
        let right = CGPoint(x: center.x + cos(angle + 0.55) * 46, y: center.y + sin(angle + 0.55) * 30)
        leaves.move(to: center)
        leaves.addQuadCurve(to: tip, control: left)
        leaves.addQuadCurve(to: center, control: right)
    }
    ctx.addPath(leaves)
    ctx.setFillColor(color(0.20, 0.58, 0.27))
    ctx.fillPath()
    // Stiel
    let stem = CGMutablePath()
    stem.move(to: CGPoint(x: 498, y: 700))
    stem.addQuadCurve(to: CGPoint(x: 548, y: 790), control: CGPoint(x: 500, y: 770))
    ctx.addPath(stem)
    ctx.setStrokeColor(color(0.16, 0.48, 0.22))
    ctx.setLineWidth(26)
    ctx.setLineCap(.round)
    ctx.strokePath()

    // Download-Pfeil in Weiß.
    let arrow = CGMutablePath()
    arrow.move(to: CGPoint(x: 512, y: 590))
    arrow.addLine(to: CGPoint(x: 512, y: 340))
    arrow.move(to: CGPoint(x: 412, y: 440))
    arrow.addLine(to: CGPoint(x: 512, y: 340))
    arrow.addLine(to: CGPoint(x: 612, y: 440))
    ctx.addPath(arrow)
    ctx.setStrokeColor(color(1, 1, 1, 0.96))
    ctx.setLineWidth(52)
    ctx.setLineCap(.round)
    ctx.setLineJoin(.round)
    ctx.strokePath()
    // Ablage-Linie
    ctx.move(to: CGPoint(x: 400, y: 285))
    ctx.addLine(to: CGPoint(x: 624, y: 285))
    ctx.setLineWidth(40)
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
