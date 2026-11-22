import AppKit

// MARK: - Design window root view

/// The visual design workspace: a direct-manipulation canvas on the left and
/// an inspector on the right. Coordinates, text, fonts and colour live in the
/// theme's `layout` manifest key; image / font file replacements are real theme
/// resources that get written to the EFI by the existing apply pipeline.
final class DesignRootView: NSView {
    override var isFlipped: Bool { true }

    let title = UI.label("", size: 13, weight: .semibold)
    let aspectCtrl = NSSegmentedControl(labels: ["16:9", "16:10", "4:3"],
                                        trackingMode: .selectOne,
                                        target: nil, action: nil)
    let saveBtn = UI.button("保存设计", height: 28, accent: true)
    let libraryBtn = UI.button("🎨 素材库选图", height: 28)
    let pngBtn = UI.button("导出合成 PNG…", height: 28)
    let icnsBtn = UI.button("导出背景 ICNS…", height: 28)
    let resetBtn = UI.button("恢复默认排版", height: 28)
    let doneBtn = UI.button("完成", height: 28)
    let topLine = UI.hLine()
    let canvas = DesignCanvasView()
    let inspector = DesignInspectorView()
    let status = UI.label("", size: 10.5, color: .secondaryLabelColor)
    let bottomLine = UI.hLine()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        aspectCtrl.selectedSegment = 0
        aspectCtrl.segmentStyle = .rounded
        aspectCtrl.font = .systemFont(ofSize: 11)
        canvas.wantsLayer = true
        status.lineBreakMode = .byTruncatingTail
        for v in [title, aspectCtrl, libraryBtn, saveBtn, pngBtn, icnsBtn, resetBtn,
                  doneBtn, topLine, canvas, inspector, bottomLine, status] as [NSView] {
            addSubview(v)
        }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) unsupported") }

    override func layout() {
        super.layout()
        let pad: CGFloat = 14
        let w = bounds.width
        // .fullSizeContentView puts content under the title bar; keep the
        // toolbar below the ~28pt title-bar strip.
        let top: CGFloat = 30

        title.frame = NSRect(x: pad, y: top + 12, width: 150, height: 20)
        aspectCtrl.frame = NSRect(x: pad + 158, y: top + 10, width: 120, height: 24)

        let by: CGFloat = top + 8
        let doneX = w - pad - 76
        doneBtn.frame = NSRect(x: doneX, y: by, width: 76, height: 28)
        resetBtn.frame = NSRect(x: doneX - 8 - 108, y: by, width: 108, height: 28)
        icnsBtn.frame = NSRect(x: resetBtn.frame.minX - 8 - 146, y: by,
                               width: 146, height: 28)
        pngBtn.frame = NSRect(x: icnsBtn.frame.minX - 8 - 130, y: by,
                              width: 130, height: 28)
        saveBtn.frame = NSRect(x: pngBtn.frame.minX - 8 - 86, y: by,
                               width: 86, height: 28)
        libraryBtn.frame = NSRect(x: saveBtn.frame.minX - 8 - 118, y: by,
                                  width: 118, height: 28)

        topLine.frame = NSRect(x: pad, y: top + 48, width: w - pad * 2, height: 1)
        bottomLine.frame = NSRect(x: pad, y: bounds.height - 34,
                                  width: w - pad * 2, height: 1)

        let bodyTop: CGFloat = top + 58
        let bodyH = max(240, bounds.height - bodyTop - 40)
        let inspW: CGFloat = 254
        inspector.frame = NSRect(x: w - pad - inspW, y: bodyTop,
                                 width: inspW, height: bodyH)
        canvas.frame = NSRect(x: pad, y: bodyTop,
                              width: max(240, w - pad * 2 - inspW - 12),
                              height: bodyH)
        status.frame = NSRect(x: pad, y: bounds.height - 26,
                              width: w - pad * 2, height: 16)
    }
}

// MARK: - Design window controller

final class DesignWindowController: NSWindowController, NSWindowDelegate {

    private var root: DesignRootView { window!.contentView as! DesignRootView }

    var themeId = ""
    private var themeDir = URL(fileURLWithPath: "")
    private var theme: Theme?
    private var layout = ThemeLayout()
    private var themeName = ""
    private var onSaved: ((String) -> Void)?
    private var saveWork: DispatchWorkItem?
    private var dirty = false
    private var closing = false
    private var library: AssetLibraryWindowController?

    /// Live preview sync (no library reload needed for every drag).
    var onLayoutChange: ((String, ThemeLayout) -> Void)?
    var onClosed: (() -> Void)?

    convenience init(theme: Theme, savedHandler: @escaping (String) -> Void) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1240, height: 820),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered, defer: false)
        window.title = "可视化设计 · \(theme.name)"
        window.minSize = NSSize(width: 1060, height: 700)
        window.center()
        window.setFrameAutosaveName("OCThemeStudioSwiftDesign")
        self.init(window: window)
        themeId = theme.id
        themeDir = theme.dir
        themeName = theme.name
        self.theme = theme
        onSaved = savedHandler
        let loaded = theme.layout
        layout = loaded ?? ThemeLayout.defaults(for: theme)
        let size = window.contentRect(forFrameRect: window.frame).size
        window.contentView = DesignRootView(frame: NSRect(origin: .zero, size: size))
        window.delegate = self
        setup()
        // A stale / overflowing default layout was rebuilt — persist the fix so
        // the main preview and the manifest agree from now on.
        if loaded == nil { persist() }
    }

    private func setup() {
        let r = root
        r.title.stringValue = "✎ \(themeName)"
        r.aspectCtrl.selectedSegment = aspectIndex(layout.aspect)
        r.canvas.theme = theme
        r.canvas.layout = layout
        r.inspector.configure(nil)
        r.inspector.configureSnap(layout.snap, layout.grid)

        for (b, sel) in [(r.saveBtn, #selector(saveNow)),
                         (r.libraryBtn, #selector(openAssetLibrary)),
                         (r.pngBtn, #selector(exportPNG)),
                         (r.icnsBtn, #selector(exportICNS)),
                         (r.resetBtn, #selector(resetLayout)),
                         (r.doneBtn, #selector(finish))] as [(NSButton, Selector)] {
            b.target = self; b.action = sel
        }
        r.aspectCtrl.target = self
        r.aspectCtrl.action = #selector(aspectChanged)

        let c = r.canvas, i = r.inspector
        c.onChange = { [weak self] in self?.changed() }
        c.onSelect = { [weak self] e in self?.root.inspector.configure(e) }
        c.onReplaceAsset = { [weak self] e in self?.replaceAsset(e) }
        c.onFontFile = { [weak self] in self?.chooseFontFile() }
        c.onAddText = { [weak self] in self?.addText() }
        c.onAddImage = { [weak self] in self?.addImage() }
        c.onFontStyle = { [weak self] _ in self?.root.inspector.focusFontStyle() }
        c.onResetAll = { [weak self] in self?.resetLayout() }
        c.onStatus = { [weak self] s in
            self?.root.status.stringValue = s.isEmpty ? Self.defaultHint : s
        }
        i.onUpdate = { [weak self] e in self?.root.canvas.apply(e) }
        i.onReplaceAsset = { [weak self] in
            guard let self = self, let e = self.root.canvas.selectedId
                .flatMap({ id in self.root.canvas.layout.elements.first { $0.id == id } }) else { return }
            self.replaceAsset(e)
        }
        i.onFontFile = { [weak self] in self?.chooseFontFile() }
        i.onAddText = { [weak self] in self?.addText() }
        i.onAddImage = { [weak self] in self?.addImage() }
        i.onSnapChange = { [weak self] snap, grid in
            guard let self = self else { return }
            self.root.canvas.layout.snap = snap
            self.root.canvas.layout.grid = grid
            self.changed()
        }
        r.status.stringValue = Self.defaultHint
    }

    private static let defaultHint =
        "拖动元素移动 · 拖白点缩放 · 双击改文字 / 换图 · 右键更多 · 方向键微调（Shift 加速）· 设计自动保存"

    // MARK: Change / persistence

    private func changed() {
        // The canvas owns a copy of the struct, so read it back before saving.
        layout = root.canvas.layout
        root.inspector.configureSnap(layout.snap, layout.grid)
        dirty = true
        onLayoutChange?(themeId, layout)
        saveWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.persist() }
        saveWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45, execute: work)
    }

    private func persist() {
        saveWork?.cancel()
        saveWork = nil
        do {
            try ThemeLayout.save(root.canvas.layout, to: themeDir)
            layout = root.canvas.layout
            dirty = false
            root.status.stringValue = "设计已保存到主题 manifest · 主窗口预览已同步"
        } catch {
            alert("保存失败", error.localizedDescription)
        }
    }

    @objc private func saveNow() {
        persist()
        reloadTheme()
        onSaved?(themeId)
        root.status.stringValue = "已保存「\(themeName)」的设计"
    }

    private func reloadTheme() {
        ThemeLibrary.shared.reload()
        theme = Theme(dir: themeDir)
        root.canvas.theme = theme
    }

    func windowWillClose(_ notification: Notification) {
        guard !closing else { return }
        closing = true
        saveWork?.cancel()
        if dirty { persist() }
        onSaved?(themeId)
        DispatchQueue.main.async { [weak self] in self?.onClosed?() }
    }

    @objc private func finish() { window?.close() }

    // MARK: Aspect / reset

    private func aspectIndex(_ a: Double) -> Int {
        if abs(a - 4.0 / 3.0) < 0.02 { return 2 }
        if abs(a - 16.0 / 10.0) < 0.02 { return 1 }
        return 0
    }

    @objc private func aspectChanged() {
        let vals = [16.0 / 9.0, 16.0 / 10.0, 4.0 / 3.0]
        let i = max(0, min(2, root.aspectCtrl.selectedSegment))
        root.canvas.layout.aspect = vals[i]
        changed()
    }

    @objc private func resetLayout() {
        guard let t = theme else { return }
        let a = NSAlert()
        a.messageText = "恢复默认排版"
        a.informativeText = "将按当前主题的图标数量重新生成一行默认布局。已添加的文字 / 图片元素会被移除，字体设置与吸附选项保留。"
        a.addButton(withTitle: "恢复默认")
        a.addButton(withTitle: "取消")
        guard a.runModal() == .alertFirstButtonReturn else { return }
        var l = ThemeLayout.defaults(for: t, aspect: root.canvas.layout.aspect)
        l.snap = root.canvas.layout.snap
        l.grid = root.canvas.layout.grid
        l.fontAsset = root.canvas.layout.fontAsset
        root.canvas.layout = l
        root.canvas.selectedId = nil
        root.inspector.configure(nil)
        changed()
        root.status.stringValue = "已恢复默认排版"
    }

    // MARK: Elements

    @objc private func addText() {
        var e = DesignElement(id: "txt-" + String(UUID().uuidString.prefix(8)), kind: .text)
        e.text = "双击编辑文字"
        e.x = 0.36; e.y = 0.44; e.w = 0.28; e.h = 0.07
        e.fontSize = 30; e.colorHex = "#FFFFFF"; e.align = "center"
        root.canvas.layout.elements.append(e)
        root.canvas.selectedId = e.id
        root.inspector.configure(e)
        changed()
        root.status.stringValue = "已新增文字元素 · 双击画布可就地编辑"
    }

    @objc private func addImage() {
        guard let src = pickFile(title: "选择图片元素",
                                 types: ["icns", "png", "jpg", "jpeg", "tif", "tiff",
                                         "gif", "bmp", "webp"]) else { return }
        do {
            let rel = try importAsset(src)
            var e = DesignElement(id: "img-" + String(UUID().uuidString.prefix(8)),
                                  kind: .image)
            e.asset = rel
            e.x = 0.43; e.y = 0.38; e.w = 0.14
            e.h = min(0.6, 0.14 * root.canvas.layout.aspect)
            reloadTheme()
            root.canvas.layout.elements.append(e)
            root.canvas.selectedId = e.id
            root.inspector.configure(e)
            changed()
            root.status.stringValue = "已加入图片元素 \((rel as NSString).lastPathComponent)"
        } catch {
            alert("添加图片失败", error.localizedDescription)
        }
    }

    // MARK: Asset library

    /// Pick a bundled / imported wallpaper or icon and add it to the canvas as
    /// a real theme resource. The local-file flow above stays untouched.
    @objc private func openAssetLibrary() {
        if let c = library, c.window?.isVisible == true {
            c.showWindow(nil)
            c.window?.makeKeyAndOrderFront(nil)
            return
        }
        let c = AssetLibraryWindowController(mode: .add(.icon))
        library = c
        c.onClose = { [weak self] in self?.library = nil }
        c.onChoose = { [weak self] item, role in
            self?.addImageFromLibrary(item, role: role)
        }
        c.showWindow(nil)
        c.window?.makeKeyAndOrderFront(nil)
    }

    private func addImageFromLibrary(_ item: AssetItem, role: AssetRole) {
        var scratchDir: URL?
        defer { if let d = scratchDir { try? FileManager.default.removeItem(at: d) } }
        do {
            let stem = role.stem ?? item.name
            let staged = try AssetLibraryStore.stage(
                item, destStem: stem,
                preferredExt: AssetLibraryStore.preferredExt(item, role: role))
            scratchDir = staged.deletingLastPathComponent()
            // rebuildThemeManifest preserves the on-disk layout, so flush first.
            try? ThemeLayout.save(root.canvas.layout, to: themeDir)
            let leaf = staged.lastPathComponent
            let rel: String
            if FileManager.default.fileExists(atPath: themeDir.appendingPathComponent(leaf).path) {
                rel = try replaceThemeAsset(themeDir, relative: leaf, with: staged)
            } else {
                rel = try importAsset(staged)
            }
            var e = DesignElement(id: "img-" + String(UUID().uuidString.prefix(8)),
                                  kind: .image)
            e.asset = rel
            e.x = 0.43; e.y = 0.38; e.w = 0.14
            e.h = min(0.6, 0.14 * root.canvas.layout.aspect)
            reloadTheme()
            root.canvas.layout.elements.append(e)
            root.canvas.selectedId = e.id
            root.inspector.configure(e)
            changed()
            root.status.stringValue = "已从素材库加入 \((rel as NSString).lastPathComponent)"
        } catch {
            alert("从素材库添加失败", error.localizedDescription)
        }
    }

    /// Right-click / inspector "替换图片资源…". Writes a REAL theme file and
    /// points every element that used the old asset at the new one.
    private func replaceAsset(_ e: DesignElement) {
        guard let src = pickFile(title: "替换图片资源",
                                 message: "新图片会写入主题目录并更新安装清单，应用主题时真实写入 EFI。",
                                 types: ["icns", "png", "jpg", "jpeg", "tif", "tiff",
                                         "gif", "bmp", "webp"]) else { return }
        do {
            // rebuildThemeManifest preserves the on-disk layout, so flush first.
            try? ThemeLayout.save(root.canvas.layout, to: themeDir)
            let old = e.asset
            let newRel: String
            if !old.isEmpty, theme?.url(old) != nil {
                newRel = try replaceThemeAsset(themeDir, relative: old, with: src)
            } else {
                newRel = try importAsset(src)
            }
            for i in root.canvas.layout.elements.indices
                where root.canvas.layout.elements[i].asset == old {
                root.canvas.layout.elements[i].asset = newRel
            }
            reloadTheme()
            changed()
            root.status.stringValue = "已替换 \((newRel as NSString).lastPathComponent)"
        } catch {
            alert("替换失败", error.localizedDescription)
        }
    }

    /// A real .ttf / .otf / .ttc inside the theme, loaded via CoreText without
    /// installing it into the system.
    private func chooseFontFile() {
        guard let src = pickFile(title: "替换主题字体文件",
                                 message: "选择 .ttf / .otf / .ttc。字体文件会作为真实资源写入主题，设计层文字立即用它渲染。",
                                 types: ["ttf", "otf", "ttc"]) else { return }
        do {
            try? ThemeLayout.save(root.canvas.layout, to: themeDir)
            let rel = try importAsset(src)
            root.canvas.layout.fontAsset = rel
            reloadTheme()
            changed()
            root.status.stringValue = "主题字体已设为 \((rel as NSString).lastPathComponent)"
        } catch {
            alert("替换字体失败", error.localizedDescription)
        }
    }

    private func importAsset(_ src: URL) throws -> String {
        let fm = FileManager.default
        var dst = themeDir.appendingPathComponent(src.lastPathComponent)
        var n = 2
        while fm.fileExists(atPath: dst.path) {
            let stem = src.deletingPathExtension().lastPathComponent
            let e = src.pathExtension
            dst = themeDir.appendingPathComponent(e.isEmpty ? "\(stem) \(n)" : "\(stem) \(n).\(e)")
            n += 1
        }
        try fm.copyItem(at: src, to: dst)
        try rebuildThemeManifest(themeDir)
        return dst.lastPathComponent
    }

    // MARK: Export

    private func exportPixels() -> (Int, Int) {
        let w = 1920
        return (w, max(320, Int((Double(w) / max(0.6, layout.aspect)).rounded())))
    }

    @objc private func exportPNG() {
        let p = exportPixels()
        guard let data = DesignRenderer.png(root.canvas.layout, theme: theme,
                                            themeDir: themeDir, pixels: p) else {
            alert("导出失败", "无法生成 \(p.0)×\(p.1) 的合成图")
            return
        }
        guard let dest = savePanel(name: clean(themeName) + "-设计稿.png",
                                   types: ["png"], title: "导出合成图 PNG") else { return }
        do {
            try data.write(to: dest, options: Data.WritingOptions.atomic)
            root.status.stringValue = "已导出合成图 \(p.0)×\(p.1)：\(dest.lastPathComponent)"
        } catch {
            alert("导出失败", error.localizedDescription)
        }
    }

    /// OpenCanopy reads a fixed `Background.icns`. Two modes are offered:
    /// background-only (safe as a real wallpaper) and the full composition
    /// (a design proof that intentionally includes the icons).
    @objc private func exportICNS() {
        let a = NSAlert()
        a.messageText = "导出背景 ICNS"
        a.informativeText = "生成 ic07(1x) + ic13(2x) 的真实 OpenCore 容器。\n\n「仅背景」适合作为 OpenCanopy 背景图（不会重复绘制图标）；「含元素合成稿」是设计效果图。"
        a.addButton(withTitle: "仅背景")
        a.addButton(withTitle: "含元素合成稿")
        a.addButton(withTitle: "取消")
        let choice = a.runModal()
        guard choice != .alertThirdButtonReturn else { return }

        var l = root.canvas.layout
        if choice == .alertFirstButtonReturn {
            for i in l.elements.indices { l.elements[i].hidden = true }
        }
        let p = exportPixels()
        let (w1, h1) = ICNSConverter.size1x(.wallpaper, pixels: p.0, p.1)
        let (w2, h2) = (w1 * 2, h1 * 2)
        guard let png1 = DesignRenderer.png(l, theme: theme, themeDir: themeDir,
                                            pixels: (w1, h1)),
              let png2 = DesignRenderer.png(l, theme: theme, themeDir: themeDir,
                                            pixels: (w2, h2)) else {
            alert("导出失败", "无法生成 \(w1)×\(h1) / \(w2)×\(h2) 位图")
            return
        }
        let data = ICNSConverter.container(png1x: png1, png2x: png2)
        guard let dest = savePanel(name: "Background.icns", types: ["icns"],
                                   title: "保存 ICNS") else { return }
        do {
            try data.write(to: dest, options: Data.WritingOptions.atomic)
            root.status.stringValue = "已导出 \((choice == .alertFirstButtonReturn ? "仅背景" : "合成稿")) ICNS · ic07 \(w1)×\(h1) / ic13 \(w2)×\(h2)"
        } catch {
            alert("导出失败", error.localizedDescription)
        }
    }

    // MARK: Panels / helpers

    private func clean(_ s: String) -> String {
        let bad = CharacterSet(charactersIn: "/\\:*?\"<>|")
        return s.components(separatedBy: bad).joined(separator: "-")
    }

    private func pickFile(title: String, message: String? = nil,
                          types: [String]) -> URL? {
        let p = NSOpenPanel()
        p.title = title
        p.message = message ?? ""
        p.allowedFileTypes = types
        p.allowsMultipleSelection = false
        p.canChooseDirectories = false
        return p.runModal() == .OK ? p.url : nil
    }

    private func savePanel(name: String, types: [String], title: String) -> URL? {
        let p = NSSavePanel()
        p.title = title
        p.nameFieldStringValue = name
        p.allowedFileTypes = types
        p.canCreateDirectories = true
        return p.runModal() == .OK ? p.url : nil
    }

    private func alert(_ title: String, _ text: String) {
        let a = NSAlert()
        a.messageText = title
        a.informativeText = text
        a.alertStyle = .warning
        a.runModal()
    }

    // MARK: Debug hooks (build validation)

    func debugSelect(_ id: String) {
        root.canvas.selectedId = id
        root.inspector.configure(root.canvas.layout.elements.first { $0.id == id })
    }

    func debugMoveSelected(dx: Double, dy: Double) {
        guard let id = root.canvas.selectedId,
              let i = root.canvas.layout.elements.firstIndex(where: { $0.id == id }) else { return }
        root.canvas.layout.elements[i].x += dx
        root.canvas.layout.elements[i].y += dy
        changed()
    }

    func debugAddText(_ text: String) {
        addText()
        guard let id = root.canvas.selectedId,
              let i = root.canvas.layout.elements.firstIndex(where: { $0.id == id }) else { return }
        root.canvas.layout.elements[i].text = text
        root.inspector.configure(root.canvas.layout.elements[i])
        changed()
    }

    func debugResizeSelected(dw: Double, dh: Double) {
        guard let id = root.canvas.selectedId,
              let i = root.canvas.layout.elements.firstIndex(where: { $0.id == id }) else { return }
        root.canvas.layout.elements[i].w = max(0.012, root.canvas.layout.elements[i].w + dw)
        root.canvas.layout.elements[i].h = max(0.02, root.canvas.layout.elements[i].h + dh)
        root.inspector.configure(root.canvas.layout.elements[i])
        changed()
    }

    func debugFontSelected(_ family: String, size: Double) {
        guard let id = root.canvas.selectedId,
              let i = root.canvas.layout.elements.firstIndex(where: { $0.id == id }) else { return }
        root.canvas.layout.elements[i].fontFamily = family
        root.canvas.layout.elements[i].fontSize = size
        root.inspector.configure(root.canvas.layout.elements[i])
        changed()
    }

    /// Snapshot of the currently persisted layout, used by the build probe.
    func debugLayoutDump() -> String {
        let l = root.canvas.layout
        var out = "aspect=\(l.aspect) snap=\(l.snap) grid=\(l.grid) fontAsset=\(l.fontAsset)\n"
        for e in l.elements {
            out += String(format: "%@ id=%@ x=%.4f y=%.4f w=%.4f h=%.4f font=%@ size=%.1f text=%@\n",
                          e.kind.rawValue, e.id, e.x, e.y, e.w, e.h,
                          e.fontFamily.isEmpty ? "-" : e.fontFamily, e.fontSize, e.text)
        }
        return out
    }

    /// Render the composition exactly like the "导出合成图" button, but to a
    /// known path so the build probe can inspect the pixels.
    func debugExportPNG(to path: String) {
        let p = exportPixels()
        guard let data = DesignRenderer.png(root.canvas.layout, theme: theme,
                                            themeDir: themeDir, pixels: p) else { return }
        try? data.write(to: URL(fileURLWithPath: path))
    }

    func debugPersist() { persist() }
}
