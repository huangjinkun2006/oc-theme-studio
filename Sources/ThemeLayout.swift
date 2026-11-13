import AppKit
import CoreText

// MARK: - Visual design layout
//
// OpenCanopy lays its icons out in a fixed row and has no coordinate file, so
// free-form positions are stored as an app-level "design layer" in the theme's
// manifest.json. It drives this app's Boot Picker preview, the visual editor
// and the exported composition. File replacements (images / font assets) are
// real theme resources and are written to the EFI unchanged.

enum DesignKind: String {
    case icon
    case image
    case text
    case selection
}

struct DesignElement {
    var id: String
    var kind: DesignKind
    var asset: String = ""        // manifest-relative path
    var text: String = ""
    var x: Double = 0            // normalized 0...1 within the screen
    var y: Double = 0
    var w: Double = 0.1
    var h: Double = 0.1
    var fontFamily: String = ""
    var fontSize: Double = 24     // design points at a 1280px-wide reference screen
    var colorHex: String = "#FFFFFF"
    var align: String = "center"
    var bold = false
    var opacity: Double = 1
    var hidden = false

    var frame: CGRect {
        get { CGRect(x: x, y: y, width: w, height: h) }
        set {
            x = Double(newValue.origin.x); y = Double(newValue.origin.y)
            w = Double(newValue.width); h = Double(newValue.height)
        }
    }

    var dict: [String: Any] {
        ["id": id, "kind": kind.rawValue, "asset": asset, "text": text,
         "x": x, "y": y, "w": w, "h": h,
         "fontFamily": fontFamily, "fontSize": fontSize, "colorHex": colorHex,
         "align": align, "bold": bold, "opacity": opacity, "hidden": hidden]
    }

    static func from(_ d: [String: Any]) -> DesignElement? {
        guard let id = d["id"] as? String,
              let k = d["kind"] as? String,
              let kind = DesignKind(rawValue: k) else { return nil }
        var e = DesignElement(id: id, kind: kind)
        e.asset = d["asset"] as? String ?? ""
        e.text = d["text"] as? String ?? ""
        e.x = d["x"] as? Double ?? 0
        e.y = d["y"] as? Double ?? 0
        e.w = d["w"] as? Double ?? 0.1
        e.h = d["h"] as? Double ?? 0.1
        e.fontFamily = d["fontFamily"] as? String ?? ""
        e.fontSize = d["fontSize"] as? Double ?? 24
        e.colorHex = d["colorHex"] as? String ?? "#FFFFFF"
        e.align = d["align"] as? String ?? "center"
        e.bold = d["bold"] as? Bool ?? false
        e.opacity = d["opacity"] as? Double ?? 1
        e.hidden = d["hidden"] as? Bool ?? false
        return e
    }
}

struct ThemeLayout {
    var aspect: Double = 16.0 / 9.0
    var snap = true
    var grid: Double = 8          // design points at 1280px reference width
    var fontAsset: String = ""    // real font file inside the theme (ttf/otf)
    var elements: [DesignElement] = []

    var dict: [String: Any] {
        ["version": 1, "aspect": aspect, "snap": snap, "grid": grid,
         "fontAsset": fontAsset, "elements": elements.map { $0.dict }]
    }

    static func load(from manifest: [String: Any]) -> ThemeLayout? {
        guard let d = manifest["layout"] as? [String: Any],
              let raw = d["elements"] as? [[String: Any]] else { return nil }
        var l = ThemeLayout()
        l.aspect = d["aspect"] as? Double ?? 16.0 / 9.0
        l.snap = d["snap"] as? Bool ?? true
        l.grid = d["grid"] as? Double ?? 8
        l.fontAsset = d["fontAsset"] as? String ?? ""
        l.elements = raw.compactMap { DesignElement.from($0) }
        return l
    }

    /// A row of icons + labels + the selection frame, in normalized coords.
    ///
    /// `x/w` are fractions of the screen width while `y/h` are fractions of the
    /// screen height, so a square icon needs `h = w * aspect`. Using the same
    /// number for both was what made icons look horizontally squashed.
    static func defaults(for theme: Theme, aspect: Double = 16.0 / 9.0) -> ThemeLayout {
        var l = ThemeLayout()
        l.aspect = max(0.6, min(3.0, aspect))
        let icons = theme.icons
        let n = max(1, icons.count)
        // total = cell * (n + 0.22*(n-1)); solve so the row always fits in 0.92.
        let cell = min(0.115, 0.92 / (1.22 * Double(n) - 0.22))
        let gap = cell * 0.22
        let total = Double(n) * cell + Double(n - 1) * gap
        var x = (1 - total) / 2
        let side = cell * 0.78            // width fraction
        let sideH = side * l.aspect       // height fraction → square on screen
        let iconY = 0.47 - sideH / 2

        if let sel = theme.selected {
            let padW = 0.008
            let padH = 0.008 * l.aspect
            l.elements.append(DesignElement(id: "sel-1", kind: .selection,
                                            asset: sel,
                                            x: x + (cell - side) / 2 - padW,
                                            y: iconY - padH,
                                            w: side + padW * 2, h: sideH + padH * 2))
        }
        for (i, icon) in icons.enumerated() {
            let stem = (icon.path as NSString).deletingPathExtension
                .replacingOccurrences(of: "/", with: "-")
            l.elements.append(DesignElement(id: "icon-\(i)-\(stem)", kind: .icon,
                                            asset: icon.path,
                                            x: x + (cell - side) / 2,
                                            y: iconY, w: side, h: sideH))
            l.elements.append(DesignElement(id: "label-\(i)-\(stem)", kind: .text,
                                            text: icon.label,
                                            x: x, y: iconY + sideH + 0.012,
                                            w: cell, h: 0.04,
                                            fontSize: 20, colorHex: "#FFFFFF"))
            x += cell + gap
        }
        return l
    }

    /// True when the layout is only the generated icon row — no text or image
    /// element the user added. Used to safely rebuild stale defaults.
    var isAutoGenerated: Bool {
        elements.allSatisfy { e in
            e.id == "sel-1" || e.id.hasPrefix("icon-") || e.id.hasPrefix("label-")
        }
    }

    /// Any element spilling outside the screen. The v1 default row overflowed
    /// once a theme had more than ~9 icons (negative x / past the right edge).
    var overflows: Bool {
        elements.contains {
            $0.x < -0.002 || $0.y < -0.002 ||
            $0.x + $0.w > 1.002 || $0.y + $0.h > 1.002
        }
    }

    /// Icons / selection frames that are not square on screen. The v1 default
    /// used the same fraction for width and height, which stretched them.
    var distorted: Bool {
        let a = aspect
        return elements.contains { e in
            guard e.kind == .icon || e.kind == .selection else { return false }
            return abs(e.h - e.w * a) > 0.02
        }
    }

    /// Save the design layer without touching any other manifest key.
    static func save(_ layout: ThemeLayout, to dir: URL) throws {
        guard var mf = jsonRead(manifestURLForLayout(dir)) else {
            throw AppError.message("主题缺少 manifest.json，无法保存布局")
        }
        mf["layout"] = layout.dict
        try jsonWrite(mf, to: manifestURLForLayout(dir))
    }

    static func clear(_ dir: URL) throws {
        guard var mf = jsonRead(manifestURLForLayout(dir)) else { return }
        mf.removeValue(forKey: "layout")
        try jsonWrite(mf, to: manifestURLForLayout(dir))
    }

    private static func manifestURLForLayout(_ dir: URL) -> URL {
        dir.appendingPathComponent("manifest.json")
    }
}

extension Theme {
    var layout: ThemeLayout? {
        guard let l = ThemeLayout.load(from: raw) else { return nil }
        // Rebuild auto-generated layouts that used the v1 formula (overflowed
        // past the screen and/or stretched icons out of square).
        if l.isAutoGenerated && (l.overflows || l.distorted) { return nil }
        return l
    }
}

// MARK: - Colour / font helpers

enum DesignStyle {
    static func color(_ hex: String, fallback: NSColor = .white) -> NSColor {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let v = UInt32(s, radix: 16) else { return fallback }
        return NSColor(calibratedRed: CGFloat((v >> 16) & 0xff) / 255,
                       green: CGFloat((v >> 8) & 0xff) / 255,
                       blue: CGFloat(v & 0xff) / 255, alpha: 1)
    }

    static func hex(_ color: NSColor) -> String {
        guard let c = color.usingColorSpace(.deviceRGB) else { return "#FFFFFF" }
        func b(_ v: CGFloat) -> Int { max(0, min(255, Int((v * 255).rounded()))) }
        return String(format: "#%02X%02X%02X",
                      b(c.redComponent), b(c.greenComponent), b(c.blueComponent))
    }

    static var availableFamilies: [String] {
        NSFontManager.shared.availableFontFamilies.sorted()
    }

    /// Font for a design text element. A real .ttf/.otf inside the theme wins,
    /// then an explicit family, then the system font.
    static func font(for e: DesignElement, themeDir: URL?, fontAsset: String,
                     scale: CGFloat) -> NSFont {
        let size = max(6, CGFloat(e.fontSize) * scale)
        if !fontAsset.isEmpty, let dir = themeDir,
           let u = designFontURL(dir, fontAsset),
           let f = loadFont(u, size: size) { return f }
        if !e.fontFamily.isEmpty,
           let f = NSFont(name: e.fontFamily, size: size) { return f }
        return e.bold ? NSFont.boldSystemFont(ofSize: size)
                      : NSFont.systemFont(ofSize: size)
    }

    static func designFontURL(_ dir: URL, _ relative: String) -> URL? {
        guard !relative.isEmpty else { return nil }
        let u = dir.appendingPathComponent(relative).standardizedFileURL
        guard u.path.hasPrefix(dir.standardizedFileURL.path + "/"),
              FileManager.default.fileExists(atPath: u.path) else { return nil }
        return ["ttf", "otf", "ttc"].contains(u.pathExtension.lowercased()) ? u : nil
    }

    /// Load a font file directly through CoreText (no installation needed).
    static func loadFont(_ url: URL, size: CGFloat) -> NSFont? {
        guard let data = try? Data(contentsOf: url),
              let provider = CGDataProvider(data: data as CFData),
              let cg = CGFont(provider) else { return nil }
        let ct = CTFontCreateWithGraphicsFont(cg, size, nil, nil)
        return ct as NSFont
    }

    static func paragraph(_ align: String) -> NSMutableParagraphStyle {
        let p = NSMutableParagraphStyle()
        p.alignment = align == "left" ? .left : align == "right" ? .right : .center
        p.lineBreakMode = .byWordWrapping
        return p
    }
}

// MARK: - Layout-aware rendering shared by the canvas and the Boot Picker

enum DesignRenderer {
    /// Draw an image scaled to fit inside `rect` without distorting it. Icons
    /// and logos keep their own aspect ratio; the leftover area is transparent.
    static func drawFit(_ img: NSImage, in rect: NSRect, alpha: CGFloat = 1) {
        let s = img.size
        guard s.width > 0, s.height > 0, rect.width > 0, rect.height > 0 else { return }
        let scale = min(rect.width / s.width, rect.height / s.height)
        let w = s.width * scale, h = s.height * scale
        img.draw(in: NSRect(x: rect.midX - w / 2, y: rect.midY - h / 2,
                            width: w, height: h),
                 from: .zero, operation: .sourceOver, fraction: alpha,
                 respectFlipped: true,
                 hints: [.interpolation: NSImageInterpolation.high])
    }

    static func drawCover(_ img: NSImage, in rect: NSRect) {
        let s = img.size
        guard s.width > 0, s.height > 0 else { return }
        let scale = max(rect.width / s.width, rect.height / s.height)
        let w = s.width * scale, h = s.height * scale
        img.draw(in: NSRect(x: rect.midX - w / 2, y: rect.midY - h / 2,
                            width: w, height: h),
                 from: .zero, operation: .sourceOver, fraction: 1,
                 respectFlipped: true,
                 hints: [.interpolation: NSImageInterpolation.high])
    }

    /// The whole composed screen, used both by the editor canvas and by PNG /
    /// ICNS export so what the user sees is exactly what gets written out.
    static func drawScreen(_ layout: ThemeLayout, theme: Theme?, themeDir: URL?,
                           in screen: NSRect) {
        NSColor.black.setFill()
        screen.fill()
        if let bg = theme?.backgroundImage {
            drawCover(bg, in: screen)
        } else {
            NSGradient(starting: NSColor(calibratedRed: 0.10, green: 0.14,
                                         blue: 0.24, alpha: 1),
                       ending: NSColor(calibratedRed: 0.03, green: 0.05,
                                       blue: 0.10, alpha: 1))?
                .draw(in: screen, angle: -35)
        }
        let scrim = NSRect(x: screen.minX, y: screen.maxY - screen.height * 0.28,
                           width: screen.width, height: screen.height * 0.28)
        NSGradient(starting: NSColor.clear,
                   ending: NSColor(calibratedWhite: 0, alpha: 0.22))?
            .draw(in: scrim, angle: 90)
        drawAll(layout, in: screen, theme: theme, themeDir: themeDir)
    }

    /// Render the composition into a standalone PNG at an arbitrary pixel size.
    ///
    /// A flipped NSView + `cacheDisplay` is used instead of drawing straight
    /// into an NSBitmapImageRep: the canvas is flipped, so a raw bitmap context
    /// would mirror every image and text baseline vertically.
    static func png(_ layout: ThemeLayout, theme: Theme?, themeDir: URL?,
                    pixels: (Int, Int)) -> Data? {
        guard pixels.0 > 1, pixels.1 > 1 else { return nil }
        let v = DesignSnapshotView(frame: NSRect(x: 0, y: 0,
                                                 width: pixels.0, height: pixels.1),
                                   layout: layout, theme: theme, themeDir: themeDir)
        guard let rep = v.bitmapImageRepForCachingDisplay(in: v.bounds) else { return nil }
        v.cacheDisplay(in: v.bounds, to: rep)
        return rep.representation(using: .png, properties: [:])
    }

    /// Draw one element inside `screen` (flipped coordinate system).
    static func draw(_ e: DesignElement, in screen: NSRect, theme: Theme?,
                     themeDir: URL?, fontAsset: String) {
        let r = NSRect(x: screen.minX + CGFloat(e.x) * screen.width,
                       y: screen.minY + CGFloat(e.y) * screen.height,
                       width: CGFloat(e.w) * screen.width,
                       height: CGFloat(e.h) * screen.height)
        guard r.width > 0, r.height > 0 else { return }
        let alpha = CGFloat(max(0, min(1, e.opacity)))
        let scale = screen.width / 1280

        switch e.kind {
        case .icon, .image:
            let img = e.asset.isEmpty ? nil : theme?.image(e.asset)
            if let img = img {
                drawFit(img, in: r, alpha: alpha)
            } else {
                NSColor(calibratedWhite: 1, alpha: 0.18 * alpha).setFill()
                NSBezierPath(ovalIn: r).fill()
            }
        case .selection:
            if !e.asset.isEmpty, let img = theme?.image(e.asset) {
                drawFit(img, in: r, alpha: alpha)
            } else {
                NSColor(calibratedWhite: 1, alpha: 0.16 * alpha).setFill()
                NSBezierPath(roundedRect: r, xRadius: 10, yRadius: 10).fill()
                NSColor(calibratedWhite: 1, alpha: 0.45 * alpha).setStroke()
                NSBezierPath(roundedRect: r, xRadius: 10, yRadius: 10).stroke()
            }
        case .text:
            guard !e.text.isEmpty else { return }
            let f = DesignStyle.font(for: e, themeDir: themeDir,
                                     fontAsset: fontAsset, scale: scale)
            let attrs: [NSAttributedString.Key: Any] = [
                .font: f,
                .foregroundColor: DesignStyle.color(e.colorHex).withAlphaComponent(alpha),
                .paragraphStyle: DesignStyle.paragraph(e.align),
            ]
            (e.text as NSString).draw(in: r, withAttributes: attrs)
        }
    }

    static func drawAll(_ layout: ThemeLayout, in screen: NSRect, theme: Theme?,
                        themeDir: URL?) {
        for e in layout.elements where !e.hidden {
            draw(e, in: screen, theme: theme, themeDir: themeDir,
                 fontAsset: layout.fontAsset)
        }
    }
}

/// Offscreen flipped host used by `DesignRenderer.png` so exports are pixel
/// identical to what the design canvas shows on screen.
private final class DesignSnapshotView: NSView {
    override var isFlipped: Bool { true }
    private let layout: ThemeLayout
    private let theme: Theme?
    private let themeDir: URL?

    init(frame frameRect: NSRect, layout: ThemeLayout, theme: Theme?, themeDir: URL?) {
        self.layout = layout
        self.theme = theme
        self.themeDir = themeDir
        super.init(frame: frameRect)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) unsupported") }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        DesignRenderer.drawScreen(layout, theme: theme, themeDir: themeDir, in: bounds)
    }
}
