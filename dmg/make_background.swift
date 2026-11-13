import AppKit

// Draws the drag-install background for the DMG in pure AppKit (no external
// image tooling). All design coordinates use a top-left origin and are
// converted to AppKit's bottom-left coordinate system through `top()`.

let W: CGFloat = 700
let H: CGFloat = 420

func top(_ y: CGFloat) -> CGFloat { H - y }

guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil,
                                 pixelsWide: Int(W), pixelsHigh: Int(H),
                                 bitsPerSample: 8, samplesPerPixel: 4,
                                 hasAlpha: true, isPlanar: false,
                                 colorSpaceName: .deviceRGB,
                                 bytesPerRow: 0, bitsPerPixel: 0) else {
    fatalError("cannot allocate bitmap")
}
rep.size = NSSize(width: W, height: H)

NSGraphicsContext.saveGraphicsState()
guard let ctx = NSGraphicsContext(bitmapImageRep: rep) else {
    fatalError("cannot create graphics context")
}
NSGraphicsContext.current = ctx

// --- Background gradient -------------------------------------------------
let bg = NSGradient(colors: [
    NSColor(calibratedRed: 0.985, green: 0.990, blue: 1.000, alpha: 1),
    NSColor(calibratedRed: 0.895, green: 0.925, blue: 0.970, alpha: 1),
])!
bg.draw(in: NSRect(x: 0, y: 0, width: W, height: H), angle: 90)

// A faint rounded panel keeps the two drop targets visually grouped.
let panel = NSBezierPath(roundedRect: NSRect(x: 46, y: top(300),
                                             width: W - 92, height: 190),
                         xRadius: 18, yRadius: 18)
NSColor.white.withAlphaComponent(0.42).setFill()
panel.fill()
NSColor.white.withAlphaComponent(0.85).setStroke()
panel.lineWidth = 1
panel.stroke()

// --- Text helper ---------------------------------------------------------
func drawText(_ text: String, size: CGFloat, weight: NSFont.Weight,
              color: NSColor, topY: CGFloat) {
    let para = NSMutableParagraphStyle()
    para.alignment = .center
    let attrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: size, weight: weight),
        .foregroundColor: color,
        .paragraphStyle: para,
    ]
    let lineH = size * 1.45
    (text as NSString).draw(in: NSRect(x: 0, y: top(topY + lineH),
                                       width: W, height: lineH),
                            withAttributes: attrs)
}

drawText("安装 OC Theme Studio", size: 25, weight: .semibold,
         color: NSColor(calibratedWhite: 0.16, alpha: 1), topY: 28)
drawText("把左边的应用图标拖到右边的 Applications 文件夹即可完成安装",
         size: 13.5, weight: .regular,
         color: NSColor(calibratedWhite: 0.34, alpha: 1), topY: 330)
drawText("原生 Swift 应用 · 无需 Python 或浏览器 · 卸载时直接移到废纸篓",
         size: 11, weight: .regular,
         color: NSColor(calibratedWhite: 0.50, alpha: 1), topY: 360)

// --- Arrow ---------------------------------------------------------------
let yc = top(195)                 // arrow centre, bottom-left coordinates
let shaft = NSBezierPath(roundedRect: NSRect(x: 258, y: yc - 8,
                                             width: 168, height: 16),
                         xRadius: 8, yRadius: 8)
let head = NSBezierPath()
head.move(to: NSPoint(x: 412, y: yc + 30))
head.line(to: NSPoint(x: 462, y: yc))
head.line(to: NSPoint(x: 412, y: yc - 30))
head.close()

// Fill the two pieces separately. Appending them into a single path makes the
// overlap cancel out under the nonzero winding rule and leaves a white hole.
NSGraphicsContext.saveGraphicsState()
let shadow = NSShadow()
shadow.shadowColor = NSColor(calibratedWhite: 0.15, alpha: 0.22)
shadow.shadowBlurRadius = 9
shadow.shadowOffset = NSSize(width: 0, height: -5)
shadow.set()
NSColor.systemBlue.setFill()
shaft.fill()
head.fill()
NSGraphicsContext.restoreGraphicsState()

// Small caption over the arrow.
drawText("拖过去", size: 12, weight: .medium,
         color: NSColor.systemBlue.withAlphaComponent(0.85), topY: 140)

NSGraphicsContext.restoreGraphicsState()

guard let png = rep.representation(using: .png, properties: [:]) else {
    fatalError("cannot encode PNG")
}
let out = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1] : "background.png"
try png.write(to: URL(fileURLWithPath: out))
print("wrote \(out) \(Int(W))x\(Int(H))")
