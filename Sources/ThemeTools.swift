import AppKit

// MARK: - Bundled presets
//
// A small curated icon pool ships inside the .app so a new theme can start
// with real boot icons instead of an empty canvas the user has to fill by
// dragging files one by one.

struct ThemePreset {
    let id: String
    let name: String
    let desc: String
    let background: String
    let selected: String
    let icons: [(file: String, label: String)]

    static var root: URL? {
        if let r = Bundle.main.resourceURL?
            .appendingPathComponent("Presets", isDirectory: true),
           FileManager.default.fileExists(atPath: r.path) { return r }
        // Dev fallback when the binary is run straight from the build dir.
        let dev = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("SwiftApp/Presets", isDirectory: true)
        return FileManager.default.fileExists(atPath: dev.path) ? dev : nil
    }

    static var iconsDir: URL? { root?.appendingPathComponent("icons", isDirectory: true) }

    static func all() -> [ThemePreset] {
        guard let r = root,
              let data = try? Data(contentsOf: r.appendingPathComponent("presets.json")),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let list = obj["presets"] as? [[String: Any]] else { return [] }
        return list.compactMap { d in
            guard let id = d["id"] as? String, let name = d["name"] as? String else { return nil }
            let icons = (d["icons"] as? [[String: Any]] ?? []).compactMap { i -> (String, String)? in
                guard let f = i["file"] as? String else { return nil }
                return (f, i["label"] as? String ?? (f as NSString).deletingPathExtension)
            }
            return ThemePreset(id: id, name: name,
                               desc: d["desc"] as? String ?? "",
                               background: d["background"] as? String ?? "",
                               selected: d["selected"] as? String ?? "",
                               icons: icons)
        }
    }

    static func icon(_ stem: String) -> URL? {
        guard let dir = iconsDir else { return nil }
        let u = dir.appendingPathComponent("\(stem).icns")
        return FileManager.default.fileExists(atPath: u.path) ? u : nil
    }
}

private let tvFontExt: Set<String> = ["ttf", "otf", "bin", "pf2"]
private let tvLabelExt: Set<String> = ["label", "lbl", "l2x", "txt", "strings"]

private func tvStr(_ v: Any?) -> String {
    if let s = v as? String { return s }
    if let n = v as? NSNumber { return n.stringValue }
    return ""
}

/// Copy the bundled default UI chrome (background / selector / cursor / dot /
/// focus) into a new theme so its variant directory is never empty.
private func copyDefaults(into dest: URL) {
    guard let d = ThemePreset.root?.appendingPathComponent("defaults"), isDir(d) else { return }
    let fm = FileManager.default
    guard let items = try? fm.contentsOfDirectory(at: d, includingPropertiesForKeys: nil) else { return }
    for it in items where !isDir(it) {
        let dst = dest.appendingPathComponent(it.lastPathComponent)
        if !fm.fileExists(atPath: dst.path) { try? fm.copyItem(at: it, to: dst) }
    }
}

/// Fallback font for a brand-new theme when no EFI is mounted. OpenCanopy
/// requires a real TrueType font to render entry labels; without one the picker
/// silently falls back to the built-in text menu. We copy a system font the user
/// is already licensed to use (kept out of the app bundle / DMG so we never
/// redistribute a copyrighted font). The EFI font from `seedFromEFI` always
/// wins when present.
private let systemFontCandidates = [
    "/System/Library/Fonts/Geneva.ttf",
    "/System/Library/Fonts/NewYork.ttf",
    "/System/Library/Fonts/SFCompact.ttf",
    "/System/Library/Fonts/Supplemental/Arial.ttf",
    "/System/Library/Fonts/Supplemental/Verdana.ttf",
]
private func seedSystemFont(into dir: URL) {
    let fm = FileManager.default
    guard let items = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { return }
    // Already has a font (e.g. copied from EFI)? Nothing to do.
    if items.contains(where: { tvFontExt.contains($0.pathExtension.lowercased()) }) { return }
    for c in systemFontCandidates {
        let src = URL(fileURLWithPath: c)
        guard fm.fileExists(atPath: src.path) else { continue }
        let dst = dir.appendingPathComponent("Font.ttf")
        try? fm.copyItem(at: src, to: dst)
        if fm.fileExists(atPath: dst.path) { return }
    }
}

/// Seed a brand-new theme from the EFI currently mounted at `efiMount` so the
/// folder is already a complete, loadable OpenCore theme: it inherits the
/// working selection box, the global font and the entry labels. Font / Label
/// are copied as-is; the active variant's images are flattened into the theme
/// root (the app re-nests them under the new PickerVariant when applied).
private func seedFromEFI(_ dir: URL, efiMount: String) {
    let fm = FileManager.default
    let res = URL(fileURLWithPath: efiMount).appendingPathComponent("EFI/OC/Resources", isDirectory: true)
    guard isDir(res) else { return }

    // 1) Global Font + Label, routed by file extension.
    for (bucket, exts) in [("Font", tvFontExt), ("Label", tvLabelExt)] {
        let src = res.appendingPathComponent(bucket, isDirectory: true)
        guard isDir(src) else { continue }
        guard let items = try? fm.contentsOfDirectory(at: src, includingPropertiesForKeys: nil) else { continue }
        for it in items where !isDir(it) {
            guard exts.contains(it.pathExtension.lowercased()) else { continue }
            let dst = dir.appendingPathComponent(it.lastPathComponent)
            if !fm.fileExists(atPath: dst.path) { try? fm.copyItem(at: it, to: dst) }
        }
    }

    // 2) Active variant images, flattened into the theme root.
    let variant = activeVariant(from: res, mount: efiMount)
    let img = res.appendingPathComponent("Image").appendingPathComponent(variant, isDirectory: true)
    guard isDir(img) else { return }
    guard let en = fm.enumerator(at: img, includingPropertiesForKeys: nil) else { return }
    for case let u as URL in en where !isDir(u) {
        let dst = dir.appendingPathComponent(u.lastPathComponent)
        if !fm.fileExists(atPath: dst.path) { try? fm.copyItem(at: u, to: dst) }
    }
}

/// Resolve the variant directory that the EFI's config.plist currently points
/// at. Falls back to the first variant that actually has images.
private func activeVariant(from res: URL, mount: String) -> String {
    let cfg = URL(fileURLWithPath: mount).appendingPathComponent("EFI/OC/config.plist")
    var fallback = "Acidanthera/GoldenGate"
    if let data = try? Data(contentsOf: cfg), let pl = plistRead(data) {
        let boot = (pl["Misc"] as? [String: Any])?["Boot"] as? [String: Any] ?? [:]
        var v = tvStr(boot["PickerVariant"]).replacingOccurrences(of: "\\", with: "/")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if v.isEmpty || v.lowercased() == "auto" { v = fallback }
        let cand = res.appendingPathComponent("Image").appendingPathComponent(v, isDirectory: true)
        if isDir(cand) { return v }
        fallback = v
    }
    let image = res.appendingPathComponent("Image", isDirectory: true)
    guard isDir(image), let subs = try? FileManager.default.contentsOfDirectory(at: image, includingPropertiesForKeys: nil) else { return fallback }
    for s in subs where isDir(s) {
        if let kids = try? FileManager.default.contentsOfDirectory(at: s, includingPropertiesForKeys: nil),
           kids.contains(where: { !isDir($0) }) {
            return String(s.path.dropFirst(image.path.count + 1))
        }
    }
    return fallback
}

/// Create a theme. A nil preset creates an empty canvas; a preset pre-fills
/// bundled icons + background. `efiMount` (the currently mounted EFI) lets the
/// new theme inherit that EFI's working selection box, font and labels so the
/// folder is already a complete, loadable OpenCore theme instead of an asset-
/// less one that makes OpenCanopy fall back to the built-in text picker.
@discardableResult
func makeTheme(name: String, preset: ThemePreset? = nil, efiMount: String? = nil) throws -> Theme {
    Paths.ensure()
    let fm = FileManager.default
    let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
    let finalName = String((trimmed.isEmpty ? "我的主题" : trimmed).prefix(60))

    var dest = Paths.themes.appendingPathComponent(slugId(finalName), isDirectory: true)
    var n = 2
    while fm.fileExists(atPath: dest.path) {
        dest = Paths.themes.appendingPathComponent("\(slugId(finalName))-\(n)", isDirectory: true)
        n += 1
    }
    try fm.createDirectory(at: dest, withIntermediateDirectories: true)

    // 1) Bundled default UI chrome: guarantees a non-empty variant even when no
    //    EFI is mounted (a blank variant makes OpenCanopy fail to load).
    copyDefaults(into: dest)
    // 2) Seed from the mounted EFI so the folder is a complete theme: it keeps
    //    the working selection box (Selected), font and labels. EFI assets win
    //    over the bundled defaults on name collision.
    if let mount = efiMount, !mount.isEmpty { seedFromEFI(dest, efiMount: mount) }
    // 3) No EFI font available? Pull a system font so OpenCanopy still loads a
    //    graphical picker (with a selection box) instead of the text menu.
    seedSystemFont(into: dest)

    var overrides: [String: String] = [:]
    if let p = preset, let iconDir = ThemePreset.iconsDir {
        for item in p.icons {
            let src = iconDir.appendingPathComponent(item.file)
            guard fm.fileExists(atPath: src.path) else { continue }
            let dst = dest.appendingPathComponent(item.file)
            try? fm.copyItem(at: src, to: dst)
            overrides[(item.file as NSString).deletingPathExtension] = item.label
        }
        for f in [p.background, p.selected] where !f.isEmpty {
            let src = iconDir.appendingPathComponent(f)
            if fm.fileExists(atPath: src.path) {
                try? fm.copyItem(at: src, to: dest.appendingPathComponent(f))
            }
        }
    }

    let source = preset.map { "主题编辑器 · 预设「\($0.name)」" } ?? "主题编辑器 · 新建"
    var mf = buildManifest(dest, name: finalName, source: source)
    mf["created"] = stamp("yyyy-MM-dd HH:mm")
    mf["pickerVariant"] = "Custom/OCThemeStudio"
    if !overrides.isEmpty {
        mf["labelOverrides"] = overrides
        var icons = mf["icons"] as? [[String: Any]] ?? []
        for i in icons.indices {
            if let stem = icons[i]["name"] as? String, let l = overrides[stem] {
                icons[i]["label"] = l
            }
        }
        mf["icons"] = icons
    }
    let manifest = dest.appendingPathComponent("manifest.json")
    try jsonWrite(mf, to: manifest)

    ThemeLibrary.shared.reload()
    guard let t = Theme(dir: dest) else { throw AppError.message("无法新建主题") }
    if !t.icons.isEmpty {
        let l = ThemeLayout.defaults(for: t)
        try? ThemeLayout.save(l, to: dest)
        ThemeLibrary.shared.reload()
    }
    return Theme(dir: dest) ?? t
}

// MARK: - Rename

@discardableResult
func renameTheme(_ theme: Theme, to newName: String) throws -> String {
    let clean = String(newName.trimmingCharacters(in: .whitespacesAndNewlines).prefix(60))
    guard !clean.isEmpty else { throw AppError.message("主题名不能为空") }
    let manifest = theme.dir.appendingPathComponent("manifest.json")
    guard var mf = jsonRead(manifest) else {
        throw AppError.message("主题缺少 manifest.json")
    }
    mf["name"] = clean
    try jsonWrite(mf, to: manifest)
    ThemeLibrary.shared.reload()
    return clean
}

// MARK: - Directory repair

struct RepairReport {
    var flattened = false
    var rebuilt = false
    var removedElements = 0
    var regeneratedLayout = false
    var setVariant = false
    var notes: [String] = []

    var changed: Bool {
        flattened || rebuilt || removedElements > 0 || regeneratedLayout || setVariant
    }

    var summary: String {
        if notes.isEmpty { return "主题目录结构正常，无需修复。" }
        return notes.map { "• " + $0 }.joined(separator: "\n")
    }
}

/// Fix a theme whose folder structure or manifest drifted from what OpenCore
/// expects: flatten a dropped `Resources` tree, rebuild the manifest from the
/// real files, drop layout elements that point at missing assets, regenerate a
/// stretched/overflowing auto layout and make sure PickerVariant is set.
func repairTheme(_ theme: Theme) throws -> RepairReport {
    var r = RepairReport()
    let fm = FileManager.default
    let dir = theme.dir
    let manifest = dir.appendingPathComponent("manifest.json")

    r.flattened = flattenResources(dir)
    if r.flattened { r.notes.append("整理嵌套的 Resources 目录") }

    if jsonRead(manifest) != nil {
        try rebuildThemeManifest(dir)
        r.rebuilt = true
    }

    guard var mf = jsonRead(manifest) else {
        throw AppError.message("无法读取 manifest.json")
    }
    if (mf["name"] as? String ?? "").isEmpty {
        mf["name"] = "未命名主题"
        r.notes.append("补全主题名")
    }
    if (mf["pickerVariant"] as? String ?? "").isEmpty {
        mf["pickerVariant"] = "Custom/OCThemeStudio"
        r.setVariant = true
        r.notes.append("设置 PickerVariant = Custom/OCThemeStudio")
    }

    if var lay = ThemeLayout.load(from: mf) {
        let before = lay.elements.count
        lay.elements.removeAll { e in
            guard !e.asset.isEmpty else { return false }
            let u = dir.appendingPathComponent(e.asset).standardizedFileURL
            return !fm.fileExists(atPath: u.path)
        }
        r.removedElements = before - lay.elements.count
        if r.removedElements > 0 {
            r.notes.append("移除 \(r.removedElements) 个指向缺失文件的元素")
        }
        if lay.isAutoGenerated && (lay.overflows || lay.distorted) {
            try jsonWrite(mf, to: manifest)
            ThemeLibrary.shared.reload()
            if let t = Theme(dir: dir) {
                lay = ThemeLayout.defaults(for: t, aspect: lay.aspect)
                r.regeneratedLayout = true
                r.notes.append("重建默认排版（修正图标比例 / 位置）")
            }
        }
        mf["layout"] = lay.dict
    } else {
        // No layout yet — build one from the freshly rebuilt manifest so a
        // theme that only just had its icons flattened also gets a canvas.
        ThemeLibrary.shared.reload()
        if let t = Theme(dir: dir), !t.icons.isEmpty {
            mf["layout"] = ThemeLayout.defaults(for: t).dict
            r.regeneratedLayout = true
            r.notes.append("生成默认排版")
        }
    }

    try jsonWrite(mf, to: manifest)
    ThemeLibrary.shared.reload()
    r.notes.insert("已重建 manifest 索引", at: 0)
    return r
}

/// Move files from a nested `Resources` tree up to the theme root.
private func flattenResources(_ dir: URL) -> Bool {
    let fm = FileManager.default
    let candidates = ["Resources", "EFI/OC/Resources", "OC/Resources"]
        .map { dir.appendingPathComponent($0, isDirectory: true) }
    guard let res = candidates.first(where: { isDir($0) }) else { return false }

    var moved = 0
    func moveFiles(from src: URL) {
        guard let items = try? fm.contentsOfDirectory(at: src,
                                                      includingPropertiesForKeys: nil) else { return }
        for it in items where !isDir(it) {
            var dst = dir.appendingPathComponent(it.lastPathComponent)
            var n = 2
            while fm.fileExists(atPath: dst.path) {
                let stem = it.deletingPathExtension().lastPathComponent
                let ext = it.pathExtension
                dst = dir.appendingPathComponent("\(stem) \(n).\(ext)")
                n += 1
            }
            try? fm.moveItem(at: it, to: dst)
            moved += 1
        }
    }
    for bucket in ["Font", "Label", "Audio", "Sound"] {
        moveFiles(from: res.appendingPathComponent(bucket))
    }
    // Image/<Vendor>/<Variant>/* — take the first variant that has pictures.
    let image = res.appendingPathComponent("Image")
    if let en = fm.enumerator(at: image, includingPropertiesForKeys: nil) {
        for case let u as URL in en
            where ["icns", "png", "jpg", "jpeg"].contains(u.pathExtension.lowercased()) {
            moveFiles(from: u.deletingLastPathComponent())
            break
        }
    }
    moveFiles(from: res)

    if moved > 0 && !hasRegularFiles(res) {
        try? fm.removeItem(at: res)
        for parent in ["EFI/OC", "EFI", "OC"] {
            let p = dir.appendingPathComponent(parent)
            if isEmptyTree(p) { try? fm.removeItem(at: p) }
        }
    }
    return moved > 0
}

private func isDir(_ url: URL) -> Bool {
    var d: ObjCBool = false
    return FileManager.default.fileExists(atPath: url.path, isDirectory: &d) && d.boolValue
}

private func hasRegularFiles(_ url: URL) -> Bool {
    let fm = FileManager.default
    guard let en = fm.enumerator(at: url, includingPropertiesForKeys: nil) else { return false }
    for case let u as URL in en where !isDir(u) { return true }
    return false
}

private func isEmptyTree(_ url: URL) -> Bool {
    guard isDir(url) else { return false }
    return !hasRegularFiles(url)
}

// MARK: - Boot entry detection

struct DetectedEntry {
    let name: String
    let kind: String
    let iconStem: String
    let detail: String
}

enum BootScanner {

    /// Look at the running system volume, every mounted volume and any mounted
    /// EFI partition for boot loaders that already exist on this machine.
    static func detect() -> [DetectedEntry] {
        let fm = FileManager.default
        var out: [DetectedEntry] = []
        var seen = Set<String>()

        func add(_ name: String, _ kind: String, _ stem: String, _ detail: String) {
            let key = name.lowercased()
            guard !key.isEmpty, !seen.contains(key) else { return }
            seen.insert(key)
            out.append(DetectedEntry(name: name, kind: kind, iconStem: stem, detail: detail))
        }

        var roots: [URL] = [URL(fileURLWithPath: "/")]
        if let vols = try? fm.contentsOfDirectory(at: URL(fileURLWithPath: "/Volumes"),
                                                  includingPropertiesForKeys: nil) {
            roots += vols.filter { !$0.lastPathComponent.hasPrefix(".") }
        }

        for v in roots {
            // macOS
            let sv = v.appendingPathComponent("System/Library/CoreServices/SystemVersion.plist")
            if let data = try? Data(contentsOf: sv), let pl = plistRead(data) {
                let name = pl["ProductName"] as? String ?? "macOS"
                let ver = pl["ProductVersion"] as? String ?? ""
                add(ver.isEmpty ? name : "\(name) \(ver)", "macOS", "Apple", v.path)
                continue
            }
            // Linux root
            let osr = v.appendingPathComponent("etc/os-release")
            if let text = try? String(contentsOf: osr, encoding: .utf8) {
                let pretty = osValue(text, "PRETTY_NAME") ?? osValue(text, "NAME") ?? "Linux"
                let id = (osValue(text, "ID") ?? "").lowercased()
                add(pretty.replacingOccurrences(of: "\"", with: ""),
                    "Linux", distroStem(id), v.path)
                continue
            }
            // Windows data volume
            if fm.fileExists(atPath: v.appendingPathComponent("Windows/System32").path) {
                add("Windows", "Windows", "Windows", v.path)
                continue
            }
        }

        for v in roots {
            let efi = v.appendingPathComponent("EFI")
            guard isDir(efi) else { continue }

            if fm.fileExists(atPath: efi.appendingPathComponent("Microsoft/Boot/bootmgfw.efi").path) {
                add("Windows Boot Manager", "Windows", "Windows", efi.path)
            }
            if isDir(efi.appendingPathComponent("Apple")) {
                add("Apple EFI", "macOS", "Apple", efi.path)
            }
            let dirs = (try? fm.contentsOfDirectory(at: efi, includingPropertiesForKeys: nil)) ?? []
            for d in dirs where isDir(d) {
                let n = d.lastPathComponent
                let low = n.lowercased()
                if ["boot", "microsoft", "apple", "oc", "opencore"].contains(low) { continue }
                let files = (try? fm.contentsOfDirectory(at: d, includingPropertiesForKeys: nil))?
                    .map { $0.lastPathComponent.lowercased() } ?? []
                let linux = files.contains {
                    $0.hasPrefix("grub") || $0.hasPrefix("shim") ||
                    $0.hasPrefix("vmlinuz") || $0.hasPrefix("linux") || $0.hasPrefix("initrd")
                }
                let anyEfi = files.contains { $0.hasSuffix(".efi") }
                let pretty = n.prefix(1).uppercased() + String(n.dropFirst())
                if linux {
                    add(pretty, "Linux", distroStem(low), d.path)
                } else if anyEfi {
                    add(pretty, "EFI", "Tool", d.path)
                }
            }
            if fm.fileExists(atPath: efi.appendingPathComponent("BOOT/BOOTx64.efi").path) {
                add("Fallback (EFI/BOOT)", "EFI", "Bootloader",
                    efi.appendingPathComponent("BOOT").path)
            }
        }
        return out
    }

    private static func osValue(_ text: String, _ key: String) -> String? {
        for line in text.split(separator: "\n") {
            let parts = line.split(separator: "=", maxSplits: 1).map(String.init)
            if parts.count == 2, parts[0] == key {
                return parts[1].trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            }
        }
        return nil
    }

    private static func distroStem(_ id: String) -> String {
        let map: [String: String] = [
            "ubuntu": "Ubuntu", "kubuntu": "Ubuntu", "xubuntu": "Ubuntu",
            "lubuntu": "Ubuntu", "ubuntu-mate": "Ubuntu",
            "fedora": "Fedora", "debian": "Debian", "arch": "Arch",
            "manjaro": "Manjaro", "linuxmint": "Mint", "mint": "Mint",
            "opensuse": "openSUSE", "opensuse-leap": "openSUSE",
            "rhel": "RHEL", "centos": "Centos", "gentoo": "Gentoo",
            "kali": "Kali", "pop": "PopOS", "elementary": "ElementaryOS",
            "zorin": "Zorin", "deepin": "Deepin", "void": "Void",
            "freebsd": "FreeBSD", "android": "Android",
        ]
        let key = id.lowercased()
        if let s = map[key] { return s }
        for (k, v) in map where key.contains(k) { return v }
        return "Linux"
    }
}

struct BootAddResult {
    let added: Int
    let layoutUpdated: Bool
}

/// Copy a matching icon into the theme for every detected entry and record the
/// display label. If the layout is auto-generated it is rebuilt so the new
/// icons actually show up on the canvas.
@discardableResult
func addBootEntries(_ entries: [DetectedEntry], to theme: Theme) throws -> BootAddResult {
    let fm = FileManager.default
    let dir = theme.dir
    let manifest = dir.appendingPathComponent("manifest.json")
    guard var mf = jsonRead(manifest) else {
        throw AppError.message("主题缺少 manifest.json")
    }
    var overrides = mf["labelOverrides"] as? [String: String] ?? [:]
    var used = Set<String>()
    var added = 0

    for e in entries {
        var stem = e.iconStem.isEmpty ? "Linux" : e.iconStem
        if used.contains(stem.lowercased()) {
            var n = 2
            while used.contains("\(stem) \(n)".lowercased()) { n += 1 }
            stem = "\(stem) \(n)"
        }
        used.insert(stem.lowercased())

        let dst = dir.appendingPathComponent("\(stem).icns")
        if !fm.fileExists(atPath: dst.path) {
            if let src = ThemePreset.icon(stem) {
                try? fm.copyItem(at: src, to: dst)
            } else if let src = ThemePreset.icon("Linux") {
                try? fm.copyItem(at: src, to: dst)
            }
        }
        overrides[stem] = e.name
        added += 1
    }

    mf["labelOverrides"] = overrides
    try jsonWrite(mf, to: manifest)
    try rebuildThemeManifest(dir)
    ThemeLibrary.shared.reload()

    var layoutUpdated = false
    if let t = Theme(dir: dir), let existing = ThemeLayout.load(from: t.raw) {
        if existing.isAutoGenerated {
            let l = ThemeLayout.defaults(for: t, aspect: existing.aspect)
            try? ThemeLayout.save(l, to: dir)
            layoutUpdated = true
        }
    } else if let t = Theme(dir: dir), !t.icons.isEmpty {
        let l = ThemeLayout.defaults(for: t)
        try? ThemeLayout.save(l, to: dir)
        layoutUpdated = true
    }
    ThemeLibrary.shared.reload()
    return BootAddResult(added: added, layoutUpdated: layoutUpdated)
}
