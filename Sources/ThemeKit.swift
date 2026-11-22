import Foundation
import AppKit

// MARK: - Theme package vocabulary (kept in sync with the Python build)

private let imageExt: Set<String> = [".png", ".icns", ".jpg", ".jpeg", ".webp", ".bmp", ".tif", ".tiff"]
private let fontExt: Set<String> = [".bin", ".ttf", ".otf", ".pf2"]
private let labelExt: Set<String> = [".label", ".lbl", ".l2x", ".txt", ".strings"]
private let labelTextExt: Set<String> = [".label", ".txt", ".strings"]
private let soundExt: Set<String> = [".wav", ".aiff", ".aif", ".mp3", ".caf", ".flac"]
private let skipNames: Set<String> = ["__MACOSX", ".DS_Store", "Thumbs.db", "desktop.ini"]

private let uiKeywords = [
    "background", "wallpaper", "bg", "logo", "banner", "selected", "selector",
    "selection", "cursor", "pointer", "dot", "divider", "separator", "progress",
    "frame", "bar", "arrow", "left", "right", "scroll", "mask", "shadow",
    "highlight", "font", "lock", "password", "btn", "button", "focus",
    "setdefault", "enter",
]

private let entryOrder = [
    "apple", "macos", "mac", "osx", "windows", "win10", "win11", "linux",
    "ubuntu", "debian", "arch", "fedora", "recovery", "harddrive", "hdd",
    "external", "usb", "tool", "shell", "reset", "restart", "shutdown",
    "boot", "memtest", "opencore", "other",
]

private let entryLabels: [(String, String)] = [
    ("apple", "macOS"), ("macos", "macOS"), ("mac", "macOS"), ("osx", "macOS"),
    ("windows", "Windows"), ("win10", "Windows 10"), ("win11", "Windows 11"),
    ("linux", "Linux"), ("ubuntu", "Ubuntu"), ("debian", "Debian"),
    ("arch", "Arch Linux"), ("fedora", "Fedora"), ("recovery", "Recovery"),
    ("harddrive", "Hard Drive"), ("hdd", "Hard Drive"), ("external", "External"),
    ("usb", "USB Drive"), ("tool", "Tools"), ("shell", "UEFI Shell"),
    ("reset", "Reset NVRAM"), ("restart", "Restart"), ("shutdown", "Shut Down"),
    ("boot", "Boot"), ("opencore", "OpenCore"), ("memtest", "MemTest86"),
    ("other", "Other"),
    ("applerecv", "Recovery"), ("extapplerecv", "Recovery (USB)"),
    ("appletm", "Time Machine"), ("extappletm", "Time Machine (USB)"),
    ("extharddrive", "External Disk"), ("efiboot", "EFI Boot"),
    ("resetnvram", "Reset NVRAM"), ("harddisk", "Hard Drive"),
    ("extwindows", "Windows (USB)"), ("extlinux", "Linux (USB)"),
]
private let exactLabels: [String: String] = Dictionary(uniqueKeysWithValues: entryLabels)

private func norm(_ s: String) -> String {
    s.lowercased()
        .replacingOccurrences(of: " ", with: "")
        .replacingOccurrences(of: "_", with: "")
        .replacingOccurrences(of: "-", with: "")
}

private func isUI(_ name: String) -> Bool {
    let n = name.lowercased()
    return uiKeywords.contains { n.contains($0) }
}

/// Exposed to the asset library so its「界面元素」filter matches exactly how
/// buildManifest() will classify the very same file name once it is written
/// into a theme. Keeping one source of truth avoids categories drifting apart.
func isUIAssetName(_ name: String) -> Bool { isUI(name) }

private func entryRank(_ name: String) -> Int {
    let n = norm(name)
    for (i, key) in entryOrder.enumerated() where n == key { return i }
    for (i, key) in entryOrder.enumerated() where n.hasPrefix(key) { return i }
    return entryOrder.count + 10
}

private func displayLabel(_ name: String) -> String {
    let n = norm(name)
    if let exact = exactLabels[n] { return exact }
    // "Flavours" icon packs: Apple10_15 / Apple13_Dark / Apple12_Light ...
    if n.hasPrefix("apple") {
        let rest = String(n.dropFirst(5))
        let digits = rest.prefix { $0.isNumber }
        if !digits.isEmpty {
            let tail = String(rest.dropFirst(digits.count))
            let ver: String
            if digits.hasPrefix("10") && digits.count > 2 {
                ver = "10." + digits.dropFirst(2)
            } else {
                ver = String(digits)
            }
            let extra = tail.contains("dark") ? " · 深色"
                      : tail.contains("light") ? " · 亮色" : ""
            return "macOS \(ver)\(extra)"
        }
    }
    for (key, value) in entryLabels where n.hasPrefix(key) { return value }
    return name.replacingOccurrences(of: "_", with: " ")
               .replacingOccurrences(of: "-", with: " ")
               .trimmingCharacters(in: .whitespaces)
}

// MARK: - Filesystem helpers

private let fm = FileManager.default

private func isDir(_ url: URL) -> Bool {
    var d: ObjCBool = false
    return fm.fileExists(atPath: url.path, isDirectory: &d) && d.boolValue
}

private func rel(_ base: URL, _ file: URL) -> String {
    let b = base.path.hasSuffix("/") ? base.path : base.path + "/"
    return file.path.hasPrefix(b) ? String(file.path.dropFirst(b.count)) : file.lastPathComponent
}

private func iterFiles(_ base: URL) -> [URL] {
    guard let e = fm.enumerator(at: base,
                                includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
                                options: [.skipsHiddenFiles]) else { return [] }
    var out: [URL] = []
    for case let u as URL in e {
        let r = rel(base, u)
        let parts = r.split(separator: "/").map(String.init)
        if parts.contains(where: { $0.hasPrefix(".") || skipNames.contains($0) }) { continue }
        if u.lastPathComponent.hasPrefix("._") { continue }
        // The manifest is generated metadata, never a theme asset.
        if u.lastPathComponent == "manifest.json" { continue }
        if isDir(u) || fileSize(u) == 0 { continue }
        out.append(u)
    }
    return out.sorted { $0.path < $1.path }
}

private func allDirs(_ base: URL) -> [URL] {
    var out: [URL] = [base]
    guard let e = fm.enumerator(at: base,
                                includingPropertiesForKeys: [.isDirectoryKey],
                                options: [.skipsHiddenFiles]) else { return out }
    for case let u as URL in e where isDir(u) {
        let parts = rel(base, u).split(separator: "/").map(String.init)
        if parts.contains(where: { $0.hasPrefix(".") || skipNames.contains($0) }) { continue }
        out.append(u)
    }
    return out
}

private func directImages(_ dir: URL) -> [URL] {
    let items = (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
    return items.filter { !isDir($0) && imageExt.contains("." + $0.pathExtension.lowercased()) }
}

private func ext(_ url: URL) -> String { "." + url.pathExtension.lowercased() }

/// Dimensions of a theme image. NSImage reads .icns natively (including the
/// large embedded PNG representations), so no manual ICNS parsing is needed.
private func imageSize(_ url: URL) -> (Int, Int) {
    if url.pathExtension.lowercased() == "png" {
        if let h = try? FileHandle(forReadingFrom: url),
           let head = try? h.read(upToCount: 24), head.count >= 24 {
            try? h.close()
            let png: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]
            if Array(head[0..<8]) == png {
                let w = head[16..<20].reduce(0) { ($0 << 8) + Int($1) }
                let hgt = head[20..<24].reduce(0) { ($0 << 8) + Int($1) }
                return (w, hgt)
            }
        }
    }
    if let img = NSImage(contentsOf: url) {
        var w = 0, h = 0
        for r in img.representations where r.pixelsWide * r.pixelsHigh > w * h {
            w = r.pixelsWide; h = r.pixelsHigh
        }
        if w > 0 && h > 0 { return (w, h) }
        return (Int(img.size.width), Int(img.size.height))
    }
    return (0, 0)
}

/// Only .label/.txt/.strings are plain text. .lbl/.l2x are pre-rendered
/// bitmap labels - decoding them yields control-character garbage.
private func findLabelText(_ base: URL, stem: String) -> String? {
    for p in iterFiles(base) {
        if !labelTextExt.contains(ext(p)) || p.deletingPathExtension().lastPathComponent.lowercased() != stem.lowercased() {
            continue
        }
        guard let d = try? Data(contentsOf: p), d.count <= 8192, !d.prefix(512).contains(0) else { continue }
        for encoding in [String.Encoding.utf8, .utf16, .utf16LittleEndian, .isoLatin1] {
            guard var text = String(data: d, encoding: encoding) else { continue }
            text = text.trimmingCharacters(in: CharacterSet(charactersIn: "\u{feff}\u{0}")
                .union(.whitespacesAndNewlines))
            guard let line = text.split(separator: "\n").first.map(String.init)?.trimmingCharacters(in: .whitespaces),
                  !line.isEmpty else { continue }
            if line.hasPrefix("<?xml") || line.hasPrefix("{") || line.hasPrefix("bplist") { continue }
            if line.unicodeScalars.contains(where: { $0.value < 32 }) { continue }
            return String(line.prefix(40))
        }
    }
    return nil
}

// MARK: - Manifest construction

func buildManifest(_ themeDir: URL, name: String, source: String) -> [String: Any] {
    let files = iterFiles(themeDir)
    var backgrounds: [String] = [], uiAssets: [String] = [], icons: [String] = []
    var fonts: [String] = [], labels: [String] = [], sounds: [String] = [], other: [String] = []

    for p in files {
        let r = rel(themeDir, p)
        let low = p.deletingPathExtension().lastPathComponent.lowercased()
        let e = ext(p)
        if imageExt.contains(e) {
            if low.contains("background") || ["bg", "wallpaper", "backdrop"].contains(low) {
                backgrounds.append(r)
            } else if isUI(low) {
                uiAssets.append(r)
            } else {
                icons.append(r)
            }
        } else if fontExt.contains(e) {
            fonts.append(r)
        } else if labelExt.contains(e) {
            labels.append(r)
        } else if soundExt.contains(e) {
            sounds.append(r)
        } else {
            other.append(r)
        }
    }

    // One representative per stem, prefer the highest-resolution variant.
    var chosen: [String: (Int64, String)] = [:]
    for r in icons {
        let stem = (r as NSString).lastPathComponent
        let base = (stem as NSString).deletingPathExtension.lowercased()
        let s = fileSize(themeDir.appendingPathComponent(r))
        if chosen[base] == nil || s > chosen[base]!.0 { chosen[base] = (s, r) }
    }
    var iconList: [[String: Any]] = []
    for (_, value) in chosen {
        let r = value.1
        let stem = ((r as NSString).lastPathComponent as NSString).deletingPathExtension
        iconList.append([
            "path": r,
            "name": stem,
            "label": findLabelText(themeDir, stem: stem) ?? displayLabel(stem),
            "rank": entryRank(stem),
        ])
    }
    iconList.sort {
        let a = $0["rank"] as? Int ?? 999
        let b = $1["rank"] as? Int ?? 999
        if a != b { return a < b }
        return ($0["name"] as? String ?? "").lowercased() < ($1["name"] as? String ?? "").lowercased()
    }
    if iconList.count > 24 { iconList = Array(iconList.prefix(24)) }

    backgrounds.sort { fileSize(themeDir.appendingPathComponent($0)) > fileSize(themeDir.appendingPathComponent($1)) }
    let background = backgrounds.first
    let selected = uiAssets.first { ($0 as NSString).lastPathComponent.lowercased().contains("select") }
    let cursor = uiAssets.first {
        let n = ($0 as NSString).lastPathComponent.lowercased()
        return n.contains("cursor") || n.contains("pointer")
    }

    var bw = 0, bh = 0
    if let b = background { (bw, bh) = imageSize(themeDir.appendingPathComponent(b)) }
    let total = files.reduce(Int64(0)) { $0 + fileSize($1) }

    return [
        "name": name,
        "source": source,
        "demo": false,
        "created": stamp("yyyy-MM-dd HH:mm"),
        "background": background ?? NSNull(),
        "backgroundSize": [bw, bh],
        "selected": selected ?? NSNull(),
        "cursor": cursor ?? NSNull(),
        "icons": iconList,
        "uiAssets": uiAssets,
        "fonts": fonts,
        "labels": labels,
        "sounds": sounds,
        "other": other,
        "stats": [
            "files": files.count,
            "size": total,
            "sizeText": humanSize(total),
            "images": backgrounds.count + uiAssets.count + icons.count,
            "iconCount": iconList.count,
        ] as [String: Any],
        "install": [
            "image": ([background].compactMap { $0 }) + uiAssets + icons,
            "font": fonts,
            "label": labels,
            "sound": sounds,
        ] as [String: Any],
    ]
}

// MARK: - Theme model

struct IconItem {
    let path: String
    let name: String
    let label: String
}

final class Theme {
    let id: String
    let dir: URL
    let raw: [String: Any]
    private var cache: [String: NSImage] = [:]

    init?(dir: URL) {
        guard let raw = jsonRead(dir.appendingPathComponent("manifest.json")) else { return nil }
        self.id = dir.lastPathComponent
        self.dir = dir
        self.raw = raw
    }

    var name: String { raw["name"] as? String ?? id }
    var source: String { raw["source"] as? String ?? "" }
    var demo: Bool { raw["demo"] as? Bool ?? false }
    var real: Bool { raw["real"] as? Bool ?? false }
    var fromEfi: Bool { raw["fromEfi"] != nil }
    var pickerVariant: String { raw["pickerVariant"] as? String ?? "" }
    var background: String? { raw["background"] as? String }
    var selected: String? { raw["selected"] as? String }
    var backgroundSize: (Int, Int) {
        let a = raw["backgroundSize"] as? [Int] ?? []
        return (a.first ?? 0, a.count > 1 ? a[1] : 0)
    }
    var sizeText: String { (raw["stats"] as? [String: Any])?["sizeText"] as? String ?? "" }
    var fileCount: Int { (raw["stats"] as? [String: Any])?["files"] as? Int ?? 0 }
    var fontCount: Int { (raw["fonts"] as? [Any])?.count ?? 0 }
    var labelCount: Int { (raw["labels"] as? [Any])?.count ?? 0 }
    var soundCount: Int { (raw["sounds"] as? [Any])?.count ?? 0 }

    var icons: [IconItem] {
        (raw["icons"] as? [[String: Any]] ?? []).map {
            IconItem(path: $0["path"] as? String ?? "",
                     name: $0["name"] as? String ?? "",
                     label: $0["label"] as? String ?? "")
        }
    }

    var tag: String {
        if fromEfi { return "EFI 导入" }
        if real { return "真实主题" }
        if demo { return "示例" }
        return ""
    }

    /// Path-traversal safe lookup of a theme asset.
    func url(_ relative: String) -> URL? {
        guard !relative.isEmpty else { return nil }
        let candidate = dir.appendingPathComponent(relative).standardizedFileURL
        guard candidate.path.hasPrefix(dir.standardizedFileURL.path + "/") else { return nil }
        return fm.fileExists(atPath: candidate.path) ? candidate : nil
    }

    func image(_ relative: String) -> NSImage? {
        if let cached = cache[relative] { return cached }
        guard let u = url(relative), let img = NSImage(contentsOf: u) else { return nil }
        cache[relative] = img
        return img
    }

    var backgroundImage: NSImage? { background.flatMap { image($0) } }
    var selectionImage: NSImage? { selected.flatMap { image($0) } }

    /// The boot logo (e.g. AppleLogo.icns on a real OpenCore EFI theme), shown
    /// centred on black during power-on — distinct from the picker background.
    var logoImage: NSImage? {
        let candidates = (raw["uiAssets"] as? [String] ?? [])
            + (raw["icons"] as? [String] ?? [])
        let logo = candidates.first {
            ($0 as NSString).deletingPathExtension.lowercased().contains("logo")
        }
        return logo.flatMap { image($0) }
    }

    func installList(_ key: String) -> [String] {
        (raw["install"] as? [String: Any])?[key] as? [String] ?? []
    }
}

// MARK: - Package detection

struct RootSpec {
    let dir: URL
    let extras: [URL]
    let files: [URL]
    let name: String
    let pickerVariant: String
}

private func detectThemeRoots(_ base: URL, limit: Int = 12) -> [RootSpec] {
    let dirs = allDirs(base)
    let resDirs = dirs.filter {
        $0.lastPathComponent.lowercased() == "resources" && isDir($0.appendingPathComponent("Image"))
    }

    if !resDirs.isEmpty {
        var specs: [RootSpec] = []
        var seen = Set<String>()
        for res in resDirs {
            let image = res.appendingPathComponent("Image")
            let leaves = allDirs(image).filter { $0 != image && directImages($0).count > 3 }
            let variants = leaves.filter { v in !leaves.contains { $0 != v && v.path.hasPrefix($0.path + "/") } }
            let shared = ["Font", "Label", "Sound", "Audio"]
                .map { res.appendingPathComponent($0) }.filter(isDir)
            if !variants.isEmpty {
                var sharedBG: URL?
                for v in variants {
                    for f in directImages(v) where f.deletingPathExtension().lastPathComponent.lowercased().contains("background") {
                        if sharedBG == nil || fileSize(f) > fileSize(sharedBG!) { sharedBG = f }
                    }
                }
                for v in variants {
                    let label = (v.deletingLastPathComponent() != image)
                        ? "\(v.deletingLastPathComponent().lastPathComponent) · \(v.lastPathComponent)"
                        : v.lastPathComponent
                    if seen.contains(label) { continue }
                    seen.insert(label)
                    let ownBG = directImages(v).contains {
                        $0.deletingPathExtension().lastPathComponent.lowercased().contains("background")
                    }
                    let relPath = rel(image, v)
                    specs.append(RootSpec(
                        dir: v, extras: shared + [image],
                        files: (!ownBG && sharedBG != nil) ? [sharedBG!] : [],
                        name: label, pickerVariant: relPath))
                }
            } else {
                let label = res.deletingLastPathComponent().lastPathComponent
                let finalLabel = label.isEmpty ? "Resources" : label
                if !seen.contains(finalLabel) {
                    seen.insert(finalLabel)
                    specs.append(RootSpec(dir: res, extras: [], files: [],
                                          name: finalLabel, pickerVariant: ""))
                }
            }
            if specs.count >= limit { break }
        }
        if !specs.isEmpty { return Array(specs.prefix(limit)) }
    }

    // Plain theme folders: directories holding a background image.
    var bgDirs: [URL] = []
    for d in dirs {
        if directImages(d).contains(where: {
            let n = $0.deletingPathExtension().lastPathComponent.lowercased()
            return n.contains("background") || ["bg", "wallpaper"].contains(n)
        }) { bgDirs.append(d) }
    }
    var roots: [RootSpec] = []
    for d in bgDirs.sorted(by: { $0.path.count < $1.path.count }) {
        if roots.contains(where: { $0.dir == d || d.path.hasPrefix($0.dir.path + "/") }) { continue }
        roots.append(RootSpec(dir: d, extras: [], files: [],
                              name: d == base ? base.lastPathComponent : d.lastPathComponent,
                              pickerVariant: ""))
    }
    if !roots.isEmpty { return Array(roots.prefix(limit)) }

    // Icon-only packs: directory with the most images.
    var best = base, bestN = 0
    for d in dirs {
        let n = directImages(d).count
        if n > bestN { best = d; bestN = n }
    }
    return [RootSpec(dir: best, extras: [], files: [],
                     name: best == base ? base.lastPathComponent : best.lastPathComponent,
                     pickerVariant: "")]
}

// MARK: - Import

private func copyTree(_ src: URL, _ dst: URL) throws {
    try fm.createDirectory(at: dst, withIntermediateDirectories: true)
    for p in iterFiles(src) {
        let target = dst.appendingPathComponent(rel(src, p))
        try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        if !fm.fileExists(atPath: target.path) { try fm.copyItem(at: p, to: target) }
    }
}

private func copyFlat(_ src: URL, _ dst: URL, directOnly: Bool) {
    let candidates = directOnly
        ? ((try? fm.contentsOfDirectory(at: src, includingPropertiesForKeys: nil)) ?? []).filter { !isDir($0) }
        : iterFiles(src)
    for p in candidates {
        if p.lastPathComponent.hasPrefix(".") || p.pathExtension.lowercased() == "json" { continue }
        let target = dst.appendingPathComponent(p.lastPathComponent)
        if !fm.fileExists(atPath: target.path) { try? fm.copyItem(at: p, to: target) }
    }
}

/// Extract a ZIP with /usr/bin/ditto, then repair Windows-style member names
/// (the whole path stored with backslashes as ONE filename). Zip Slip entries
/// are rejected before anything is moved.
func safeExtractZip(_ zip: URL, into dest: URL) throws {
    try fm.createDirectory(at: dest, withIntermediateDirectories: true)
    let r = shellRun("/usr/bin/ditto", ["-x", "-k", zip.path, dest.path], timeout: 240)
    if !r.ok { throw AppError.message("无法解压主题包：\(r.err.isEmpty ? r.out : r.err)") }

    // Windows-made ZIPs may store "EFI\OC\Resources\..." with backslashes as
    // ONE filename. `ditto` keeps them verbatim, and directory entries become
    // zero-byte files whose name ends in a backslash. Collect everything first,
    // create the whole directory skeleton, and only then move the real files.
    // Doing it in one pass lets a directory marker occupy a directory path and
    // breaks every later file with ENOTDIR.
    let root = dest.standardizedFileURL.path
    var dirs = Set<String>()
    var moves: [(URL, URL)] = []
    var drops: [URL] = []

    guard let e = fm.enumerator(at: dest, includingPropertiesForKeys: [.isRegularFileKey]) else { return }
    for case let u as URL in e {
        guard !isDir(u) else { continue }
        let name = u.lastPathComponent
        guard name.contains("\\") else { continue }
        let isMarker = name.hasSuffix("\\") || name.hasSuffix("/")
        var parts = name
            .replacingOccurrences(of: "\\", with: "/")
            .split(separator: "/", omittingEmptySubsequences: true)
            .map(String.init)
        if parts.isEmpty { drops.append(u); continue }
        if parts[0].count == 2 && parts[0].hasSuffix(":") { parts.removeFirst() }  // "C:"
        if parts.contains(where: { $0 == ".." || $0.hasPrefix(".") || skipNames.contains($0) }) {
            drops.append(u)   // Zip Slip / metadata
            continue
        }
        var target = dest
        for c in parts { target.appendPathComponent(c) }
        let normalized = target.standardizedFileURL.path
        guard normalized.hasPrefix(root + "/") else { drops.append(u); continue }
        let rel = String(normalized.dropFirst(root.count + 1))
        let comps = rel.split(separator: "/").map(String.init)
        var acc = ""
        for c in comps.dropLast() {
            acc = acc.isEmpty ? c : acc + "/" + c
            dirs.insert(acc)
        }
        if isMarker {
            dirs.insert(rel)
            drops.append(u)
        } else {
            moves.append((u, target))
        }
    }

    // 1) Directory skeleton. A stray file at a directory path is removed.
    for rel in dirs.sorted(by: { $0.count < $1.count }) {
        let dir = dest.appendingPathComponent(rel)
        if fm.fileExists(atPath: dir.path) && !isDir(dir) { try? fm.removeItem(at: dir) }
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
    }
    // 2) Directory markers and rejected entries.
    for u in drops { try? fm.removeItem(at: u) }
    // 3) Real files.
    for (src, dst) in moves {
        if isDir(dst) { try? fm.removeItem(at: src); continue }  // keep the directory
        if fm.fileExists(atPath: dst.path) { try? fm.removeItem(at: dst) }
        try? fm.moveItem(at: src, to: dst)
    }
}

func importFromDir(_ base: URL, wantedName: String?, source: String) throws -> [Theme] {
    let specs = detectThemeRoots(base)
    var created: [Theme] = []
    for spec in specs {
        let rawName = (wantedName?.isEmpty == false && specs.count == 1) ? wantedName! : spec.name
        let cleaned = rawName
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "/", with: " ")
            .replacingOccurrences(of: "\\", with: " ")
            .replacingOccurrences(of: ":", with: " ")
            .trimmingCharacters(in: .whitespaces)
        let name = String((cleaned.isEmpty ? "未命名主题" : cleaned).prefix(60))
        let tid = slugId(name)
        let dest = Paths.themes.appendingPathComponent(tid, isDirectory: true)
        try fm.createDirectory(at: dest, withIntermediateDirectories: true)
        try copyTree(spec.dir, dest)
        for extra in spec.extras {
            copyFlat(extra, dest, directOnly: extra.lastPathComponent.lowercased() == "image")
        }
        for f in spec.files where !fm.fileExists(atPath: dest.appendingPathComponent(f.lastPathComponent).path) {
            try? fm.copyItem(at: f, to: dest.appendingPathComponent(f.lastPathComponent))
        }
        var mf = buildManifest(dest, name: name, source: source)
        if !spec.pickerVariant.isEmpty { mf["pickerVariant"] = spec.pickerVariant }
        try jsonWrite(mf, to: dest.appendingPathComponent("manifest.json"))
        if let t = Theme(dir: dest) { created.append(t) }
    }
    if created.isEmpty { throw AppError.message("没有在主题包中识别到可用的主题文件") }
    return created
}

// MARK: - Library

final class ThemeLibrary {
    static let shared = ThemeLibrary()
    private(set) var themes: [Theme] = []

    func reload() {
        let items = (try? fm.contentsOfDirectory(at: Paths.themes,
                                                 includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        let sorted = items.filter { $0.lastPathComponent.hasPrefix("t_") }.sorted { a, b in
            let da = (try? a.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
            let db = (try? b.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
            return da > db
        }
        themes = sorted.compactMap { Theme(dir: $0) }
    }

    @discardableResult
    func importPackage(_ url: URL, name: String?) throws -> [Theme] {
        Paths.ensure()
        let isZip = url.pathExtension.lowercased() == "zip"
        try? fm.createDirectory(at: Paths.scratch, withIntermediateDirectories: true)
        let temp = Paths.scratch.appendingPathComponent("octheme_\(UUID().uuidString)", isDirectory: true)
        defer { try? fm.removeItem(at: temp) }
        let base: URL
        if isZip {
            base = temp.appendingPathComponent("extracted", isDirectory: true)
            try safeExtractZip(url, into: base)
        } else {
            guard isDir(url) else { throw AppError.message("文件夹不存在：\(url.path)") }
            base = url
        }
        let result = try importFromDir(base, wantedName: name,
                                       source: isZip ? "ZIP 主题包" : "本地文件夹")
        reload()
        return result
    }

    func remove(_ theme: Theme) throws {
        try fm.removeItem(at: theme.dir)
        reload()
    }

    /// Read-only copy of the theme currently installed on a mounted EFI.
    @discardableResult
    func importCurrentTheme(mount: String, device: String, name: String?) throws -> Theme {
        let base = URL(fileURLWithPath: mount).appendingPathComponent("EFI/OC/Resources", isDirectory: true)
        guard isDir(base) else { throw AppError.message("该 EFI 分区没有 EFI/OC/Resources 目录") }
        let subdirs = ["Image", "Font", "Label", "Audio", "Sound"]
        var sources: [URL] = []
        for sub in subdirs {
            let d = base.appendingPathComponent(sub)
            sources += iterFiles(d)
        }
        let images = sources.filter { imageExt.contains(ext($0)) }
        guard !images.isEmpty else { throw AppError.message("该 EFI 上没有可预览的主题图片") }
        let dev = device.isEmpty ? "EFI" : device
        let finalName = name ?? "当前 OC 主题 · \(dev)"
        let dest = Paths.themes.appendingPathComponent(slugId(finalName), isDirectory: true)
        try fm.createDirectory(at: dest, withIntermediateDirectories: true)
        for p in sources {
            let target = dest.appendingPathComponent(p.lastPathComponent)
            if !fm.fileExists(atPath: target.path) { try? fm.copyItem(at: p, to: target) }
        }
        var mf = buildManifest(dest, name: finalName, source: "EFI/OC/Resources · \(dev)")
        mf["fromEfi"] = ["device": dev, "mountPoint": mount, "imported": stamp("yyyy-MM-dd HH:mm")]
        try jsonWrite(mf, to: dest.appendingPathComponent("manifest.json"))
        reload()
        guard let t = Theme(dir: dest) else { throw AppError.message("无法生成主题快照") }
        return t
    }
}

// MARK: - Theme editing (used by the native theme editor)

private func manifestURL(_ dir: URL) -> URL { dir.appendingPathComponent("manifest.json") }

private func cleanThemeName(_ s: String) -> String {
    let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
    return String((t.isEmpty ? "未命名主题" : t).prefix(60))
}

/// Resolve a manifest-relative asset path without allowing path traversal.
private func themeAssetURL(_ dir: URL, _ relative: String) -> URL? {
    guard !relative.isEmpty, relative != "manifest.json",
          !relative.hasSuffix("/manifest.json") else { return nil }
    let c = dir.appendingPathComponent(relative).standardizedFileURL
    guard c.path.hasPrefix(dir.standardizedFileURL.path + "/") else { return nil }
    return c
}

/// Rebuild the derived parts of manifest.json after files changed. Everything
/// the editor lets the user set (name, PickerVariant, icon labels, provenance)
/// is preserved; the install buckets, icon list and stats are recomputed so
/// changes really reach EFI on the next "apply".
func rebuildThemeManifest(_ dir: URL) throws {
    guard let old = jsonRead(manifestURL(dir)) else {
        throw AppError.message("主题缺少 manifest.json，无法重建资源索引")
    }
    let name = old["name"] as? String ?? dir.lastPathComponent
    let source = old["source"] as? String ?? "主题编辑器"
    var mf = buildManifest(dir, name: name, source: source)
    for key in ["demo", "real", "fromEfi", "origin", "pickerVariant", "created", "layout"] {
        if let v = old[key] { mf[key] = v }
    }
    let overrides = old["labelOverrides"] as? [String: String] ?? [:]
    if !overrides.isEmpty {
        mf["labelOverrides"] = overrides
        var icons = mf["icons"] as? [[String: Any]] ?? []
        for i in icons.indices {
            let stem = icons[i]["name"] as? String ?? ""
            if let label = overrides[stem] { icons[i]["label"] = label }
        }
        mf["icons"] = icons
    }
    try jsonWrite(mf, to: manifestURL(dir))
}

func updateThemeMeta(_ dir: URL, name: String, variant: String) throws {
    guard var mf = jsonRead(manifestURL(dir)) else {
        throw AppError.message("主题缺少 manifest.json")
    }
    mf["name"] = cleanThemeName(name)
    let v = variant.trimmingCharacters(in: .whitespacesAndNewlines)
    if v.isEmpty { mf.removeValue(forKey: "pickerVariant") }
    else { mf["pickerVariant"] = v.replacingOccurrences(of: "\\", with: "/") }
    try jsonWrite(mf, to: manifestURL(dir))
}

/// Icon display names are the app's preview labels. OpenCanopy itself renders
/// menu text from the .lbl/.l2x bitmaps in Resources/Label.
func setThemeIconLabel(_ dir: URL, stem: String, label: String) throws {
    guard var mf = jsonRead(manifestURL(dir)) else {
        throw AppError.message("主题缺少 manifest.json")
    }
    var overrides = mf["labelOverrides"] as? [String: String] ?? [:]
    let clean = label.trimmingCharacters(in: .whitespacesAndNewlines)
    if clean.isEmpty { overrides.removeValue(forKey: stem) }
    else { overrides[stem] = clean }
    mf["labelOverrides"] = overrides
    var icons = mf["icons"] as? [[String: Any]] ?? []
    for i in icons.indices where (icons[i]["name"] as? String ?? "") == stem {
        icons[i]["label"] = clean.isEmpty ? displayLabel(stem) : clean
    }
    mf["icons"] = icons
    try jsonWrite(mf, to: manifestURL(dir))
}

@discardableResult
func makeBlankTheme(name: String) throws -> Theme {
    Paths.ensure()
    let clean = cleanThemeName(name)
    let dest = Paths.themes.appendingPathComponent(slugId(clean), isDirectory: true)
    try fm.createDirectory(at: dest, withIntermediateDirectories: true)
    var mf = buildManifest(dest, name: clean, source: "主题编辑器 · 新建")
    mf["created"] = stamp("yyyy-MM-dd HH:mm")
    // A custom variant keeps a new theme away from Acidanthera/GoldenGate.
    mf["pickerVariant"] = "Custom/OCThemeStudio"
    try jsonWrite(mf, to: manifestURL(dest))
    ThemeLibrary.shared.reload()
    guard let t = Theme(dir: dest) else { throw AppError.message("无法新建主题") }
    return t
}

@discardableResult
func duplicateTheme(_ theme: Theme, name: String) throws -> Theme {
    Paths.ensure()
    let clean = cleanThemeName(name)
    let dest = Paths.themes.appendingPathComponent(slugId(clean), isDirectory: true)
    try fm.copyItem(at: theme.dir, to: dest)
    guard var mf = jsonRead(manifestURL(dest)) else {
        throw AppError.message("副本缺少 manifest.json")
    }
    mf["name"] = clean
    mf["source"] = "主题编辑器 · 副本"
    mf["created"] = stamp("yyyy-MM-dd HH:mm")
    mf.removeValue(forKey: "fromEfi")
    mf.removeValue(forKey: "origin")
    try jsonWrite(mf, to: manifestURL(dest))
    ThemeLibrary.shared.reload()
    guard let t = Theme(dir: dest) else { throw AppError.message("无法生成副本") }
    return t
}

func exportTheme(_ theme: Theme, to zip: URL) throws {
    if fm.fileExists(atPath: zip.path) { try fm.removeItem(at: zip) }
    let r = shellRun("/usr/bin/ditto",
                     ["-c", "-k", "--keepParent", "--norsrc", "--noextattr",
                      theme.dir.path, zip.path], timeout: 240)
    if !r.ok {
        throw AppError.message("导出失败：\(r.err.isEmpty ? r.out : r.err)")
    }
}

@discardableResult
func addThemeAssets(_ dir: URL, files: [URL]) throws -> Int {
    var added = 0
    for src in files {
        let leaf = src.lastPathComponent
        guard !leaf.hasPrefix("."), leaf != "manifest.json" else { continue }
        var dst = dir.appendingPathComponent(leaf)
        var n = 2
        while fm.fileExists(atPath: dst.path) {
            let stem = src.deletingPathExtension().lastPathComponent
            let e = src.pathExtension
            dst = dir.appendingPathComponent(e.isEmpty ? "\(stem) \(n)" : "\(stem) \(n).\(e)")
            n += 1
        }
        try fm.copyItem(at: src, to: dst)
        added += 1
    }
    if added > 0 { try rebuildThemeManifest(dir) }
    return added
}

@discardableResult
func replaceThemeAsset(_ dir: URL, relative: String, with src: URL) throws -> String {
    guard let dst = themeAssetURL(dir, relative), fm.fileExists(atPath: dst.path) else {
        throw AppError.message("找不到要替换的资源：\(relative)")
    }
    let newExt = src.pathExtension
    let target = (newExt.lowercased() == dst.pathExtension.lowercased() || newExt.isEmpty)
        ? dst : dst.deletingPathExtension().appendingPathExtension(newExt)
    try fm.removeItem(at: dst)
    if target != dst && fm.fileExists(atPath: target.path) { try fm.removeItem(at: target) }
    try fm.copyItem(at: src, to: target)
    try rebuildThemeManifest(dir)
    return rel(dir, target)
}

func removeThemeAsset(_ dir: URL, relative: String) throws {
    guard let dst = themeAssetURL(dir, relative), fm.fileExists(atPath: dst.path) else {
        throw AppError.message("资源不存在：\(relative)")
    }
    try fm.removeItem(at: dst)
    try rebuildThemeManifest(dir)
}
