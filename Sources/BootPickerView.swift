import AppKit

/// A native AppKit rendering of the OpenCanopy Boot Picker. It draws the real
/// theme background, selection asset and icon set directly from NSImage, so
/// nothing is faked and no web view is involved.
final class BootPickerView: NSView {
    override var isFlipped: Bool { true }

    var theme: Theme? { didSet { selectedIndex = 0; needsDisplay = true } }
    var aspect: CGFloat = 16.0 / 9.0 { didSet { needsDisplay = true } }
    var showLabels = true { didSet { needsDisplay = true } }
    var selectionVisible = true { didSet { needsDisplay = true } }
    var selectedIndex = 0 { didSet { needsDisplay = true } }

    /// When the theme carries a saved visual design layer, the preview uses
    /// those coordinates instead of OpenCanopy's automatic centred row.
    var designLayout: ThemeLayout? { didSet { needsDisplay = true } }

    private var iconFrames: [NSRect] = []
    var onSelectionChange: ((Int) -> Void)?

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        // Outer stage
        NSColor(calibratedWhite: 0.085, alpha: 1).setFill()
        bounds.fill()

        let avail = bounds.insetBy(dx: 18, dy: 18)
        var sw = avail.width
        var sh = sw / aspect
        if sh > avail.height {
            sh = avail.height
            sw = sh * aspect
        }
        let screen = NSRect(x: bounds.midX - sw / 2, y: bounds.midY - sh / 2,
                            width: sw, height: sh)

        // Rounded screen clip + shadow-ish border
        let path = NSBezierPath(roundedRect: screen, xRadius: 10, yRadius: 10)
        NSGraphicsContext.saveGraphicsState()
        path.addClip()

        if var dl = designLayout {
            dl = adjusted(dl)
            DesignRenderer.drawScreen(dl, theme: theme, themeDir: theme?.dir, in: screen)
            drawBadge(in: screen)
        } else {
            NSColor.black.setFill()
            screen.fill()
            if let bg = theme?.backgroundImage {
                drawCover(bg, in: screen)
            } else {
                let grad = NSGradient(starting: NSColor(calibratedRed: 0.10, green: 0.14,
                                                        blue: 0.24, alpha: 1),
                                      ending: NSColor(calibratedRed: 0.03, green: 0.05,
                                                      blue: 0.10, alpha: 1))
                grad?.draw(in: screen, angle: -35)
                // subtle vignette
                NSColor(calibratedWhite: 1, alpha: 0.035).setFill()
                NSBezierPath(roundedRect: screen.insetBy(dx: 40, dy: 40),
                             xRadius: 120, yRadius: 120).fill()
            }

            // A light bottom scrim keeps labels readable on bright wallpapers.
            let scrim = NSRect(x: screen.minX, y: screen.maxY - sh * 0.28,
                               width: sw, height: sh * 0.28)
            NSGradient(starting: NSColor.clear,
                       ending: NSColor(calibratedWhite: 0, alpha: 0.22))?
                .draw(in: scrim, angle: 90)

            drawBadge(in: screen)
            drawEntries(in: screen)
        }
        NSGraphicsContext.restoreGraphicsState()

        // Screen border on top of everything
        NSColor(calibratedWhite: 1, alpha: 0.16).setStroke()
        path.lineWidth = 1
        path.stroke()
    }

    /// Make the stored selection frame follow the clicked boot entry, and
    /// honour the "显示标签 / 选中框" toggles on auto-generated label elements.
    private func adjusted(_ l: ThemeLayout) -> ThemeLayout {
        var out = l
        let iconFrames = out.elements.filter { $0.kind == .icon }
        if let si = out.elements.firstIndex(where: { $0.kind == .selection }) {
            if !selectionVisible {
                out.elements[si].hidden = true
            } else if selectedIndex >= 0 && selectedIndex < iconFrames.count {
                let t = iconFrames[selectedIndex]
                let pad = 0.008
                out.elements[si].x = t.x - pad
                out.elements[si].y = t.y - pad
                out.elements[si].w = t.w + pad * 2
                out.elements[si].h = t.h + pad * 2
                out.elements[si].hidden = false
            }
        }
        if !showLabels {
            for i in out.elements.indices where out.elements[i].id.hasPrefix("label-") {
                out.elements[i].hidden = true
            }
        }
        return out
    }

    private func drawCover(_ img: NSImage, in rect: NSRect) {
        let s = img.size
        guard s.width > 0, s.height > 0 else { return }
        let scale = max(rect.width / s.width, rect.height / s.height)
        let w = s.width * scale, h = s.height * scale
        let dest = NSRect(x: rect.midX - w / 2, y: rect.midY - h / 2,
                          width: w, height: h)
        img.draw(in: dest, from: .zero, operation: .sourceOver, fraction: 1,
                 respectFlipped: true, hints: [.interpolation: NSImageInterpolation.high])
    }

    private func drawBadge(in screen: NSRect) {
        let variant = theme?.pickerVariant ?? ""
        let text = theme == nil ? "OpenCore · Boot Picker 预览"
            : (variant.isEmpty ? (theme?.demo == true ? "内置示例主题" : theme?.source ?? "")
                               : "Variant: " + variant)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 10.5, weight: .medium),
            .foregroundColor: NSColor.white.withAlphaComponent(0.85),
        ]
        let size = (text as NSString).size(withAttributes: attrs)
        let box = NSRect(x: screen.minX + 16, y: screen.minY + 14,
                         width: min(size.width + 18, screen.width - 32), height: 21)
        NSColor(calibratedWhite: 0, alpha: 0.38).setFill()
        NSBezierPath(roundedRect: box, xRadius: 6, yRadius: 6).fill()
        (text as NSString).draw(in: NSRect(x: box.minX + 9, y: box.minY + 3,
                                           width: box.width - 18, height: 15),
                                withAttributes: attrs)
    }

    private func drawEntries(in screen: NSRect) {
        iconFrames = []
        let icons = theme?.icons ?? []
        guard !icons.isEmpty else {
            let t = "导入主题包后，这里会显示真实的启动项图标"
            (t as NSString).draw(at: NSPoint(x: screen.midX - 145, y: screen.midY - 8),
                                 withAttributes: [
                                    .font: NSFont.systemFont(ofSize: 13),
                                    .foregroundColor: NSColor.white.withAlphaComponent(0.6)])
            return
        }

        let n = icons.count
        let budget = screen.width * 0.94
        func rowWidth(_ i: CGFloat) -> CGFloat {
            CGFloat(n) * (i + 22) + CGFloat(n - 1) * (i * 0.22)
        }
        var icon = min(104, screen.height * 0.17)
        while rowWidth(icon) > budget && icon > 26 { icon -= 2 }
        let cellW = icon + 22
        let gap = icon * 0.22
        let totalW = CGFloat(n) * cellW + CGFloat(n - 1) * gap
        var x = screen.midX - totalW / 2
        let centerY = screen.midY + screen.height * 0.015
        let labelH: CGFloat = 15

        for (i, item) in icons.enumerated() {
            let cell = NSRect(x: x, y: centerY - icon / 2 - 10,
                              width: cellW, height: icon + (showLabels ? 34 : 20))

            if selectionVisible && i == selectedIndex {
                if let sel = theme?.selectionImage {
                    let pad: CGFloat = 10
                    sel.draw(in: NSRect(x: cell.minX - pad / 2,
                                        y: centerY - icon / 2 - pad / 2,
                                        width: icon + pad, height: icon + pad),
                             from: .zero, operation: .sourceOver, fraction: 1,
                             respectFlipped: true, hints: nil)
                } else {
                    let hi = NSRect(x: cell.minX, y: centerY - icon / 2 - 7,
                                    width: cellW, height: icon + (showLabels ? 29 : 14))
                    NSColor(calibratedWhite: 1, alpha: 0.16).setFill()
                    NSBezierPath(roundedRect: hi, xRadius: 10, yRadius: 10).fill()
                    NSColor(calibratedWhite: 1, alpha: 0.45).setStroke()
                    NSBezierPath(roundedRect: hi, xRadius: 10, yRadius: 10).stroke()
                }
            }

            if let img = theme?.image(item.path) {
                let r = NSRect(x: cell.midX - icon / 2, y: centerY - icon / 2,
                               width: icon, height: icon)
                DesignRenderer.drawFit(img, in: r)
            } else {
                NSColor(calibratedWhite: 1, alpha: 0.22).setFill()
                NSBezierPath(ovalIn: NSRect(x: cell.midX - icon / 2,
                                            y: centerY - icon / 2,
                                            width: icon, height: icon)).fill()
            }

            if showLabels {
                let para = NSMutableParagraphStyle()
                para.alignment = .center
                para.lineBreakMode = .byTruncatingTail
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: NSFont.systemFont(ofSize: 11, weight: .medium),
                    .foregroundColor: NSColor.white.withAlphaComponent(0.94),
                    .paragraphStyle: para,
                ]
                let lr = NSRect(x: cell.minX, y: centerY + icon / 2 + 7,
                                width: cellW, height: labelH)
                (item.label as NSString).draw(in: lr, withAttributes: attrs)
            }

            iconFrames.append(cell)
            x += cellW + gap
        }

        // Hint for icon-only packs
        if theme?.background == nil {
            let hint = "仅图标包 · 该主题没有背景图，预览使用默认底色"
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 10.5),
                .foregroundColor: NSColor.white.withAlphaComponent(0.6),
            ]
            let s = (hint as NSString).size(withAttributes: attrs)
            (hint as NSString).draw(at: NSPoint(x: screen.midX - s.width / 2,
                                                y: screen.maxY - 30),
                                    withAttributes: attrs)
        }
    }

    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        if let l = designLayout {
            let s = screenRect(in: bounds)
            guard s.contains(p) else { return }
            let nx = Double((p.x - s.minX) / s.width)
            let ny = Double((p.y - s.minY) / s.height)
            let icons = l.elements.filter { $0.kind == .icon && !$0.hidden }
            for (i, e) in icons.enumerated() {
                let r = CGRect(x: e.x, y: e.y, width: e.w, height: e.h)
                if r.insetBy(dx: -0.01, dy: -0.01).contains(CGPoint(x: nx, y: ny)) {
                    selectedIndex = i
                    onSelectionChange?(i)
                    return
                }
            }
            return
        }
        for (i, r) in iconFrames.enumerated() where r.contains(p) {
            selectedIndex = i
            onSelectionChange?(i)
            return
        }
    }

    private func screenRect(in b: NSRect) -> NSRect {
        let avail = b.insetBy(dx: 18, dy: 18)
        var sw = avail.width
        var sh = sw / aspect
        if sh > avail.height {
            sh = avail.height
            sw = sh * aspect
        }
        return NSRect(x: b.midX - sw / 2, y: b.midY - sh / 2, width: sw, height: sh)
    }
}
