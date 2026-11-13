import AppKit

// MARK: - Image -> OpenCore .icns converter window
//
// OpenCanopy reads PNG entries out of .icns files; it does not use a macOS
// .iconset. This window lets the user pick (or drag in) a JPG / PNG, choose
// the target spec, see the resulting 1x bitmap, and either save an .icns file
// or inject it straight into the theme being edited.

/// Checkerboard-backed image surface so transparent padding is visible.
final class ICNSPreviewBox: NSView {
    override var isFlipped: Bool { true }
    var image: NSImage? { didSet { needsDisplay = true } }
    var emptyText = "把 JPG / PNG 图片拖到这里" { didSet { needsDisplay = true } }
    var showDrop = false { didSet { needsDisplay = true } }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 8
        layer?.borderColor = NSColor.separatorColor.cgColor
        layer?.borderWidth = 1
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) unsupported") }

    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds, xRadius: 8, yRadius: 8)
        path.addClip()

        let cell: CGFloat = 16
        NSColor.windowBackgroundColor.setFill()
        NSBezierPath(rect: bounds).fill()
        NSColor.separatorColor.withAlphaComponent(0.30).setFill()
        var row = 0
        var y: CGFloat = 0
        while y < bounds.height {
            var x = (row % 2 == 0) ? CGFloat(0) : cell
            while x < bounds.width {
                NSBezierPath(rect: NSRect(x: x, y: y, width: cell, height: cell)).fill()
                x += cell * 2
            }
            y += cell
            row += 1
        }

        let inset = bounds.insetBy(dx: 14, dy: 14)
        if let img = image, img.size.width > 0, img.size.height > 0 {
            let s = min(inset.width / img.size.width, inset.height / img.size.height)
            let w = img.size.width * s, h = img.size.height * s
            let r = NSRect(x: inset.midX - w / 2, y: inset.midY - h / 2,
                           width: w, height: h)
            img.draw(in: r, from: NSRect(origin: .zero, size: img.size),
                     operation: .sourceOver, fraction: 1.0)
        } else {
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 13, weight: .medium),
                .foregroundColor: NSColor.secondaryLabelColor,
            ]
            let s = NSAttributedString(string: emptyText, attributes: attrs)
            let sz = s.size()
            s.draw(at: NSPoint(x: (bounds.width - sz.width) / 2,
                               y: (bounds.height - sz.height) / 2))
        }

        if showDrop {
            NSColor.controlAccentColor.withAlphaComponent(0.14).setFill()
            NSBezierPath(rect: bounds).fill()
            let p = NSBezierPath(roundedRect: bounds.insetBy(dx: 8, dy: 8),
                                 xRadius: 9, yRadius: 9)
            NSColor.controlAccentColor.setStroke()
            p.lineWidth = 2
            let dash: [CGFloat] = [8, 5]
            p.setLineDash(dash, count: dash.count, phase: 0)
            p.stroke()
        }
    }
}

final class ICNSRootView: NSView {
    override var isFlipped: Bool { true }

    let title = UI.label("图片转 ICNS", size: 17, weight: .semibold)
    let subtitle = UI.label("把 JPG / PNG 转成 OpenCanopy 能读取的 .icns（ic07 = 1x，ic13 = 2x）",
                            size: 11, color: .secondaryLabelColor)
    let topLine = UI.hLine()

    let sourceBox = ICNSPreviewBox()
    let resultBox = ICNSPreviewBox()
    let sourceInfo = UI.label("尚未选择图片", size: 10.5, color: .secondaryLabelColor)
    let resultInfo = UI.label("转换结果将显示在这里", size: 10.5, color: .secondaryLabelColor)
    let sourceTag = UI.section("原图")
    let resultTag = UI.section("IC07 预览（转换结果）")

    let specLabel = UI.label("规格", size: 11, color: .secondaryLabelColor)
    let specPop = NSPopUpButton(frame: .zero, pullsDown: false)
    let fitLabel = UI.label("适配", size: 11, color: .secondaryLabelColor)
    let fitPop = NSPopUpButton(frame: .zero, pullsDown: false)
    let nameLabel = UI.label("文件名", size: 11, color: .secondaryLabelColor)
    let nameField = UI.field("例如 MyIcon.icns")
    let note = UI.label("", size: 10, color: .secondaryLabelColor)

    let bottomLine = UI.hLine()
    let pickBtn = UI.button("选择图片…", height: 28)
    let saveBtn = UI.button("保存到文件…", height: 28)
    let addBtn = UI.button("加入当前主题", height: 28)
    let replaceBtn = UI.button("替换选中资源", height: 28)
    let closeBtn = UI.button("关闭", height: 28)
    let status = UI.label("", size: 10.5, color: .secondaryLabelColor)

    var onDropImage: ((URL) -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        specPop.addItems(withTitles: ICNSSpec.allCases.map { $0.title })
        fitPop.addItems(withTitles: ICNSFit.allCases.map { $0.title })
        specPop.font = .systemFont(ofSize: 11.5)
        fitPop.font = .systemFont(ofSize: 11.5)
        resultBox.emptyText = "选择原图后自动预览"
        note.stringValue = """
        自动判断：接近正方形 → 启动项图标 128×128；宽屏 / 竖屏 → 背景（保持原始比例）。\
        「原始尺寸」按图片像素 1x / 2x 输出。生成的 .icns 与真实 OpenCore 主题结构一致。\
        注意：OpenCanopy 按固定文件名读取资源，背景请保持 Background.icns；\
        启动项图标可命名为 Apple.icns、Windows.icns 等，或在编辑器里用「替换选中资源」直接覆盖。
        """
        note.lineBreakMode = .byWordWrapping
        note.maximumNumberOfLines = 4

        for v in [title, subtitle, topLine, sourceTag, resultTag,
                  sourceBox, resultBox, sourceInfo, resultInfo,
                  specLabel, specPop, fitLabel, fitPop,
                  nameLabel, nameField, note, bottomLine,
                  pickBtn, saveBtn, addBtn, replaceBtn, closeBtn, status] as [NSView] {
            addSubview(v)
        }
        registerForDraggedTypes(themeDragTypes)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) unsupported") }

    private func droppedImages(_ sender: NSDraggingInfo) -> [URL] {
        draggedFileURLs(sender.draggingPasteboard).filter { ICNSConverter.isImage($0) }
    }
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard let u = droppedImages(sender).first else { return [] }
        guard (try? ICNSConverter.load(u)) != nil else { return [] }
        sourceBox.showDrop = true
        return .copy
    }
    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        droppedImages(sender).isEmpty ? [] : .copy
    }
    override func draggingExited(_ sender: NSDraggingInfo?) { sourceBox.showDrop = false }
    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
        !droppedImages(sender).isEmpty
    }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        sourceBox.showDrop = false
        guard let u = droppedImages(sender).first else { return false }
        onDropImage?(u)
        return true
    }
    override func concludeDragOperation(_ sender: NSDraggingInfo?) { sourceBox.showDrop = false }

    override func layout() {
        super.layout()
        let pad: CGFloat = 18
        let w = bounds.width - pad * 2
        title.frame = NSRect(x: pad, y: 14, width: w, height: 24)
        subtitle.frame = NSRect(x: pad, y: 42, width: w, height: 16)
        topLine.frame = NSRect(x: pad, y: 60, width: w, height: 1)

        let bodyTop: CGFloat = 78
        let bodyH = max(180, bounds.height - 290)
        let half = (w - 14) / 2
        sourceTag.frame = NSRect(x: pad, y: bodyTop - 14, width: half, height: 14)
        resultTag.frame = NSRect(x: pad + half + 14, y: bodyTop - 14, width: half, height: 14)
        sourceBox.frame = NSRect(x: pad, y: bodyTop, width: half, height: bodyH)
        resultBox.frame = NSRect(x: pad + half + 14, y: bodyTop, width: half, height: bodyH)
        let infoY = bodyTop + bodyH + 6
        sourceInfo.frame = NSRect(x: pad + 2, y: infoY, width: half - 4, height: 16)
        resultInfo.frame = NSRect(x: pad + half + 16, y: infoY, width: half - 4, height: 16)

        let y1 = infoY + 28
        specLabel.frame = NSRect(x: pad, y: y1 + 5, width: 34, height: 16)
        specPop.frame = NSRect(x: pad + 38, y: y1, width: 310, height: 26)
        fitLabel.frame = NSRect(x: pad + 366, y: y1 + 5, width: 34, height: 16)
        fitPop.frame = NSRect(x: pad + 404, y: y1, width: min(260, w - 404), height: 26)

        let y2 = y1 + 36
        nameLabel.frame = NSRect(x: pad, y: y2 + 4, width: 50, height: 18)
        nameField.frame = NSRect(x: pad + 54, y: y2, width: 300, height: 24)
        status.frame = NSRect(x: pad + 366, y: y2 + 4, width: w - 366, height: 18)
        note.frame = NSRect(x: pad, y: y2 + 32, width: w, height: 48)

        bottomLine.frame = NSRect(x: pad, y: bounds.height - 58, width: w, height: 1)
        let by = bounds.height - 48
        closeBtn.frame = NSRect(x: bounds.width - pad - 96, y: by, width: 96, height: 28)
        let row = [pickBtn, saveBtn, addBtn, replaceBtn].filter { !$0.isHidden }
        let gap: CGFloat = 8
        let avail = bounds.width - pad - 96 - 12 - pad
        let bw = (avail - gap * CGFloat(max(1, row.count) - 1)) / CGFloat(max(1, row.count))
        for (i, b) in row.enumerated() {
            b.frame = NSRect(x: pad + CGFloat(i) * (bw + gap), y: by,
                             width: bw, height: 28)
        }
    }
}

// MARK: - Controller

final class ICNSWindowController: NSWindowController, NSWindowDelegate {

    private var sourceURL: URL?
    private var themeDir: URL?
    private var replaceRelative: String?
    private var onApplied: ((String?) -> Void)?
    var onClose: (() -> Void)?
    private var working = false
    /// Last automatically suggested name; used so manual edits are preserved.
    private var autoName = ""
    private var sourceStem = ""
    private var sourcePixels: (Int, Int) = (0, 0)

    private var root: ICNSRootView { window!.contentView as! ICNSRootView }
    private var spec: ICNSSpec { ICNSSpec.allCases[root.specPop.indexOfSelectedItem] }
    private var fit: ICNSFit { ICNSFit.allCases[root.fitPop.indexOfSelectedItem] }

    /// - Parameters:
    ///   - initialFile: an image handed over by Finder / Dock drag-and-drop.
    ///   - themeDir: when opened from the editor, enables "add to theme".
    ///   - replaceRelative: selected .icns asset, enables "replace selected".
    ///   - applied: called after a theme was modified (argument = asset to select).
    convenience init(initialFile: URL? = nil,
                     themeDir: URL? = nil,
                     replaceRelative: String? = nil,
                     applied: ((String?) -> Void)? = nil) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 620),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered, defer: false)
        window.title = "图片转 ICNS · OC Theme Studio"
        window.minSize = NSSize(width: 760, height: 560)
        window.center()
        window.setFrameAutosaveName("OCThemeStudioSwiftICNS")
        self.init(window: window)
        self.themeDir = themeDir
        self.replaceRelative = replaceRelative
        self.onApplied = applied
        let size = window.contentRect(forFrameRect: window.frame).size
        window.contentView = ICNSRootView(frame: NSRect(origin: .zero, size: size))
        window.delegate = self
        setup()
        if let u = initialFile { loadSource(u) }
    }

    private func setup() {
        let r = root
        r.addBtn.isHidden = (themeDir == nil)
        r.replaceBtn.isHidden = (themeDir == nil || replaceRelative == nil)
        r.saveBtn.isEnabled = false
        r.addBtn.isEnabled = false
        r.replaceBtn.isEnabled = false
        r.nameField.isEnabled = false
        r.onDropImage = { [weak self] url in self?.loadSource(url) }
        for (b, sel) in [(r.pickBtn, #selector(pickImage)),
                         (r.saveBtn, #selector(saveToFile)),
                         (r.addBtn, #selector(addToTheme)),
                         (r.replaceBtn, #selector(replaceSelected)),
                         (r.closeBtn, #selector(closeWindow))] as [(NSButton, Selector)] {
            b.target = self; b.action = sel
        }
        r.specPop.target = self
        r.specPop.action = #selector(optionsChanged)
        r.fitPop.target = self
        r.fitPop.action = #selector(optionsChanged)
        r.note.needsLayout = true
    }

    // MARK: Source & preview

    func loadSource(_ url: URL) {
        guard let src = try? ICNSConverter.load(url) else {
            alert("无法读取图片", "「\(url.lastPathComponent)」不是受支持的图片文件。")
            return
        }
        sourceURL = url
        sourceStem = url.deletingPathExtension().lastPathComponent
        sourcePixels = src.pixels
        let r = root
        r.sourceBox.image = src.image
        r.sourceBox.emptyText = ""
        r.sourceInfo.stringValue = "\(url.lastPathComponent) · \(src.pixels.0)×\(src.pixels.1) · " +
            humanSize(fileSize(url))
        let stem = sourceStem
        // Auto spec follows the picture's aspect ratio: select the matching row
        // so the popup always reflects what will actually be produced.
        let resolved = ICNSConverter.resolve(.auto, pixels: src.pixels)
        if let i = ICNSSpec.allCases.firstIndex(of: resolved) {
            r.specPop.selectItem(at: i)
        }
        applyAutoName(stem: stem, pixels: src.pixels)
        r.saveBtn.isEnabled = true
        r.addBtn.isEnabled = !r.addBtn.isHidden
        r.replaceBtn.isEnabled = !r.replaceBtn.isHidden
        r.nameField.isEnabled = true
        updatePreview()
    }

    /// OpenCanopy looks up backgrounds by the fixed name Background.icns, so a
    /// wide picture gets that name by default. A manually typed name wins.
    private func suggestedName(stem: String, pixels: (Int, Int)) -> String {
        let resolved = ICNSConverter.resolve(spec, pixels: pixels)
        if resolved == .wallpaper { return "Background.icns" }
        return cleanOutputName(stem) + ".icns"
    }

    private func applyAutoName(stem: String, pixels: (Int, Int)) {
        let suggested = suggestedName(stem: stem, pixels: pixels)
        if root.nameField.stringValue.isEmpty || root.nameField.stringValue == autoName {
            root.nameField.stringValue = suggested
        }
        autoName = suggested
    }

    private func cleanOutputName(_ s: String) -> String {
        let bad = CharacterSet(charactersIn: "/\\:*?\"<>|")
        let clean = s.components(separatedBy: bad).joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return clean.isEmpty ? "MyIcon" : clean
    }

    private func outputName() -> String {
        var s = root.nameField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.isEmpty { s = "MyIcon.icns" }
        if (s as NSString).pathExtension.lowercased() != "icns" { s += ".icns" }
        return s
    }

    @objc private func optionsChanged() {
        if sourceURL != nil { applyAutoName(stem: sourceStem, pixels: sourcePixels) }
        updatePreview()
    }

    private func updatePreview() {
        let r = root
        guard let u = sourceURL else {
            r.resultBox.image = nil
            r.resultInfo.stringValue = "转换结果将显示在这里"
            return
        }
        r.resultBox.image = ICNSConverter.preview(u, spec: spec, fit: fit)
        r.resultBox.emptyText = "无法预览"
        guard let src = try? ICNSConverter.load(u) else { return }
        let resolved = ICNSConverter.resolve(spec, pixels: src.pixels)
        let (w1, h1) = ICNSConverter.size1x(spec, pixels: src.pixels.0, src.pixels.1)
        r.resultInfo.stringValue = "\(resolved.title) · ic07 \(w1)×\(h1) · ic13 \(w1 * 2)×\(h1 * 2)"
    }

    // MARK: Conversion actions

    private func setWorking(_ on: Bool, _ text: String) {
        working = on
        root.status.stringValue = text
        let r = root
        for b in [r.pickBtn, r.saveBtn, r.addBtn, r.replaceBtn, r.closeBtn] {
            b.isEnabled = !on && (b === r.closeBtn || b === r.pickBtn ||
                                  sourceURL != nil)
            if b === r.addBtn && r.addBtn.isHidden { b.isEnabled = false }
            if b === r.replaceBtn && r.replaceBtn.isHidden { b.isEnabled = false }
        }
    }

    /// Perform the real conversion off the main thread, then run `done` with the
    /// produced .icns URL on the main thread.
    private func produce(_ done: @escaping (URL) -> Void) {
        guard let u = sourceURL, !working else { return }
        let chosenSpec = spec, chosenFit = fit, name = outputName()
        Paths.ensure()
        let tmp = Paths.scratch.appendingPathComponent("icns-" + UUID().uuidString,
                                                       isDirectory: true)
        try? FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        let dest = tmp.appendingPathComponent(name)
        setWorking(true, "正在转换…")
        DispatchQueue.global(qos: .userInitiated).async {
            let result: Result<ICNSConvertInfo, Error>
            do {
                result = .success(try ICNSConverter.convert(source: u, to: dest,
                                                            spec: chosenSpec, fit: chosenFit))
            } catch {
                result = .failure(error)
            }
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.setWorking(false, "")
                switch result {
                case .failure(let e):
                    self.alert("转换失败", e.localizedDescription)
                case .success(let info):
                    self.root.status.stringValue = "完成 · ic07 \(info.size1x.0)×\(info.size1x.1) · " +
                        humanSize(info.bytes)
                    done(dest)
                }
            }
        }
    }

    @objc private func pickImage() {
        let p = NSOpenPanel()
        p.message = "选择要转换的 JPG / PNG 图片（也可直接拖进窗口）"
        p.canChooseFiles = true
        p.canChooseDirectories = false
        p.allowsMultipleSelection = false
        p.allowedFileTypes = Array(ICNSConverter.readableExtensions)
        p.beginSheetModal(for: window!) { [weak self] resp in
            guard resp == .OK, let u = p.url else { return }
            self?.loadSource(u)
        }
    }

    @objc private func saveToFile() {
        produce { [weak self] tmp in
            guard let self = self else { return }
            let p = NSSavePanel()
            p.title = "保存 ICNS"
            p.nameFieldStringValue = self.outputName()
            p.allowedFileTypes = ["icns"]
            p.canCreateDirectories = true
            p.beginSheetModal(for: self.window!) { resp in
                guard resp == .OK, let u = p.url else { return }
                do {
                    if FileManager.default.fileExists(atPath: u.path) {
                        try FileManager.default.removeItem(at: u)
                    }
                    try FileManager.default.copyItem(at: tmp, to: u)
                    self.root.status.stringValue = "已保存 \(u.lastPathComponent)"
                    NSWorkspace.shared.activateFileViewerSelecting([u])
                } catch {
                    self.alert("保存失败", error.localizedDescription)
                }
            }
        }
    }

    @objc private func addToTheme() {
        guard let dir = themeDir else { return }
        produce { [weak self] tmp in
            guard let self = self else { return }
            do {
                _ = try addThemeAssets(dir, files: [tmp])
                self.root.status.stringValue = "已加入当前主题"
                self.onApplied?(nil)
            } catch {
                self.alert("加入主题失败", error.localizedDescription)
            }
        }
    }

    @objc private func replaceSelected() {
        guard let dir = themeDir, let rel = replaceRelative else { return }
        produce { [weak self] tmp in
            guard let self = self else { return }
            do {
                let newRel = try replaceThemeAsset(dir, relative: rel, with: tmp)
                self.root.status.stringValue = "已替换 \((rel as NSString).lastPathComponent)"
                self.onApplied?(newRel)
            } catch {
                self.alert("替换资源失败", error.localizedDescription)
            }
        }
    }

    @objc private func closeWindow() { window?.close() }

    func windowWillClose(_ notification: Notification) {
        let cb = onClose
        onClose = nil
        cb?()
    }

    private func alert(_ title: String, _ text: String) {
        let a = NSAlert()
        a.messageText = title
        a.informativeText = text
        a.alertStyle = .critical
        a.addButton(withTitle: "好")
        if let w = window { a.beginSheetModal(for: w, completionHandler: nil) }
        else { a.runModal() }
    }

    // Debug hook used by the build-validation snapshot mode.
    func debugLoad(_ url: URL) { loadSource(url) }
}
