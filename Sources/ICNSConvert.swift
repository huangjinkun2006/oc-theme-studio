import AppKit

// MARK: - OpenCore .icns conversion
//
// OpenCanopy does NOT use a full macOS .iconset. The .icns files shipped with
// real OpenCore themes contain exactly two PNG entries:
//
//   ic07  ->  1x bitmap, e.g. 128x128 for an icon, 2560x1440 for a wallpaper
//   ic13  ->  2x bitmap, exactly twice the 1x dimensions
//
// Crucially, these bitmaps keep the source aspect ratio (backgrounds are 16:9).
// Running `iconutil` would force a square canvas and add a dozen useless
// entries, so the container is written directly here.

enum ICNSSpec: String, CaseIterable {
    case auto
    case icon
    case wallpaper
    case original

    var title: String {
        switch self {
        case .auto: return "自动判断（按图片比例）"
        case .icon: return "启动项图标 · 128×128 / 256×256"
        case .wallpaper: return "背景 / 宽屏 · 保持原始比例"
        case .original: return "保持原始像素尺寸 · 1x / 2x"
        }
    }
}

enum ICNSFit: String, CaseIterable {
    case contain
    case cover

    var title: String {
        switch self {
        case .contain: return "完整保留（透明留白）"
        case .cover: return "居中裁切铺满"
        }
    }
}

struct ICNSConvertInfo {
    let sourcePixels: (Int, Int)
    let spec: ICNSSpec
    let size1x: (Int, Int)
    let size2x: (Int, Int)
    let bytes: Int64
}

enum ICNSConverter {

    struct Source {
        let url: URL
        let image: NSImage
        let pixels: (Int, Int)
    }

    static let readableExtensions: Set<String> = [
        "png", "jpg", "jpeg", "jpe", "gif", "bmp", "tif", "tiff", "webp", "heic", "heif",
    ]

    static func isImage(_ url: URL) -> Bool {
        readableExtensions.contains(url.pathExtension.lowercased())
    }

    static func load(_ url: URL) throws -> Source {
        var image: NSImage?
        var pixels: (Int, Int) = (0, 0)

        if let data = try? Data(contentsOf: url), let rep = NSBitmapImageRep(data: data) {
            pixels = (rep.pixelsWide, rep.pixelsHigh)
            let img = NSImage(size: NSSize(width: rep.pixelsWide, height: rep.pixelsHigh))
            img.addRepresentation(rep)
            image = img
        } else if let img = NSImage(contentsOf: url) {
            image = img
            for r in img.representations where r.pixelsWide * r.pixelsHigh > pixels.0 * pixels.1 {
                pixels = (r.pixelsWide, r.pixelsHigh)
            }
            if pixels.0 == 0 { pixels = (Int(img.size.width), Int(img.size.height)) }
        }
        guard let image = image, pixels.0 > 0, pixels.1 > 0 else {
            throw AppError.message("无法读取图片：\(url.lastPathComponent)")
        }
        return Source(url: url, image: image, pixels: pixels)
    }

    /// Wide / tall images are treated as backgrounds, near-square ones as icons.
    static func resolve(_ spec: ICNSSpec, pixels: (Int, Int)) -> ICNSSpec {
        guard spec == .auto else { return spec }
        let r = Double(pixels.0) / Double(max(1, pixels.1))
        return (r > 1.35 || r < 0.74) ? .wallpaper : .icon
    }

    /// 1x dimensions of the bitmap stored in ic07.
    static func size1x(_ spec: ICNSSpec, pixels sw: Int, _ sh: Int) -> (Int, Int) {
        let real = resolve(spec, pixels: (sw, sh))
        var w: Int, h: Int
        switch real {
        case .icon:
            w = 128; h = 128
        case .wallpaper:
            w = min(2560, max(320, sw))
            h = max(1, Int((Double(w) * Double(sh) / Double(sw)).rounded()))
        case .original:
            w = sw; h = sh
        case .auto:
            w = sw; h = sh   // unreachable: resolve() always returns a concrete spec
        }
        // ic13 is always exactly 2x, so keep the 2x bitmap within a sane bound.
        let limit = 4096
        if w > limit || h > limit {
            let s = min(Double(limit) / Double(w), Double(limit) / Double(h))
            w = max(1, Int((Double(w) * s).rounded()))
            h = max(1, Int((Double(h) * s).rounded()))
        }
        return (w, h)
    }

    /// Draw the source into an RGBA bitmap and return PNG bytes.
    static func render(_ image: NSImage, width pxW: Int, height pxH: Int,
                       fit: ICNSFit) throws -> Data {
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil,
                                         pixelsWide: pxW, pixelsHigh: pxH,
                                         bitsPerSample: 8, samplesPerPixel: 4,
                                         hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .deviceRGB,
                                         bytesPerRow: 0, bitsPerPixel: 0),
              let ctx = NSGraphicsContext(bitmapImageRep: rep) else {
            throw AppError.message("无法创建图像画布（\(pxW)×\(pxH)）")
        }
        rep.size = NSSize(width: pxW, height: pxH)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = ctx
        ctx.imageInterpolation = .high
        NSColor.clear.setFill()
        NSBezierPath(rect: NSRect(x: 0, y: 0, width: pxW, height: pxH)).fill()

        let sw = max(1, image.size.width), sh = max(1, image.size.height)
        let sx = CGFloat(pxW) / sw, sy = CGFloat(pxH) / sh
        let scale = fit == .cover ? max(sx, sy) : min(sx, sy)
        let dw = sw * scale, dh = sh * scale
        let rect = NSRect(x: (CGFloat(pxW) - dw) / 2,
                          y: (CGFloat(pxH) - dh) / 2,
                          width: dw, height: dh)
        image.draw(in: rect,
                   from: NSRect(x: 0, y: 0, width: sw, height: sh),
                   operation: .sourceOver, fraction: 1.0)
        NSGraphicsContext.restoreGraphicsState()
        NSGraphicsContext.current = nil

        guard let png = rep.representation(using: .png, properties: [:]) else {
            throw AppError.message("无法编码 PNG（\(pxW)×\(pxH)）")
        }
        return png
    }

    static func container(png1x: Data, png2x: Data) -> Data {
        var d = Data()
        func u32(_ v: UInt32) {
            var be = v.bigEndian
            d.append(Data(bytes: &be, count: 4))
        }
        d.append(Data("icns".utf8))
        let total = 8 + (8 + png1x.count) + (8 + png2x.count)
        u32(UInt32(total))
        d.append(Data("ic07".utf8)); u32(UInt32(8 + png1x.count)); d.append(png1x)
        d.append(Data("ic13".utf8)); u32(UInt32(8 + png2x.count)); d.append(png2x)
        return d
    }

    /// Convert one image into an OpenCore-compatible .icns file.
    @discardableResult
    static func convert(source: URL, to dest: URL,
                        spec: ICNSSpec = .auto,
                        fit: ICNSFit = .contain) throws -> ICNSConvertInfo {
        let src = try load(source)
        let resolved = resolve(spec, pixels: src.pixels)
        let (w1, h1) = size1x(resolved, pixels: src.pixels.0, src.pixels.1)
        let (w2, h2) = (w1 * 2, h1 * 2)
        let png1 = try render(src.image, width: w1, height: h1, fit: fit)
        let png2 = try render(src.image, width: w2, height: h2, fit: fit)
        let data = container(png1x: png1, png2x: png2)
        do {
            try data.write(to: dest, options: .atomic)
        } catch {
            throw AppError.message("写入 \(dest.lastPathComponent) 失败：\(error.localizedDescription)")
        }
        return ICNSConvertInfo(sourcePixels: src.pixels, spec: resolved,
                               size1x: (w1, h1), size2x: (w2, h2),
                               bytes: Int64(data.count))
    }

    /// Small preview of what ic07 will look like (never larger than 320 px).
    static func preview(_ source: URL, spec: ICNSSpec, fit: ICNSFit) -> NSImage? {
        guard let src = try? load(source) else { return nil }
        let (w1, h1) = size1x(spec, pixels: src.pixels.0, src.pixels.1)
        let s = min(1.0, 320.0 / Double(max(w1, h1)))
        let pw = max(1, Int((Double(w1) * s).rounded()))
        let ph = max(1, Int((Double(h1) * s).rounded()))
        guard let data = try? render(src.image, width: pw, height: ph, fit: fit) else { return nil }
        return NSImage(data: data)
    }

    /// Inspect an .icns the way OpenCanopy does: list ic07 / ic13 dimensions.
    static func inspect(_ url: URL) -> [(String, Int, Int)] {
        guard let d = try? Data(contentsOf: url), d.count > 16,
              String(data: d.prefix(4), encoding: .ascii) == "icns" else { return [] }
        var out: [(String, Int, Int)] = []
        var off = 8
        while off + 8 <= d.count {
            let type = String(data: d[off..<off + 4], encoding: .ascii) ?? "?"
            let len = d[off + 4..<off + 8].reduce(0) { ($0 << 8) + Int($1) }
            if len < 8 || off + len > d.count { break }
            let payload = d[off + 8..<off + len]
            if payload.count >= 24, Array(payload.prefix(8)) == [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A] {
                let w = payload[payload.startIndex + 16..<payload.startIndex + 20]
                    .reduce(0) { ($0 << 8) + Int($1) }
                let h = payload[payload.startIndex + 20..<payload.startIndex + 24]
                    .reduce(0) { ($0 << 8) + Int($1) }
                out.append((type, w, h))
            } else {
                out.append((type, 0, 0))
            }
            off += len
        }
        return out
    }
}
