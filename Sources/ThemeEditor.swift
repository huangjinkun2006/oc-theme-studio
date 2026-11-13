import AppKit

// MARK: - Drag & drop helpers (shared with the main window)

let themeDragTypes: [NSPasteboard.PasteboardType] = [
    .fileURL,
    NSPasteboard.PasteboardType("NSFilenamesPboardType"),
]

func draggedFileURLs(_ pb: NSPasteboard) -> [URL] {
    var out: [URL] = []
    let opts: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true]
    if let objs = pb.readObjects(forClasses: [NSURL.self], options: opts) as? [NSURL] {
        out += objs.map { $0 as URL }
    }
    if out.isEmpty,
       let names = pb.propertyList(forType: NSPasteboard.PasteboardType("NSFilenamesPboardType")) as? [String] {
        out += names.map { URL(fileURLWithPath: $0) }
    }
    var seen = Set<String>()
    return out.filter { seen.insert($0.standardizedFileURL.path).inserted }
}

/// Drag-to-install accepts ZIP packages and folders (the same two shapes the
/// import panel supports).
func themeInstallDrops(_ urls: [URL]) -> [URL] {
    urls.filter { u in
        var d: ObjCBool = false
        guard FileManager.default.fileExists(atPath: u.path, isDirectory: &d) else { return false }
        return d.boolValue || u.pathExtension.lowercased() == "zip"
    }
}

/// A small modal dialog with a single text field.
func askForThemeName(_ title: String, _ message: String, _ initial: String,
                     _ okTitle: String, _ done: @escaping (String) -> Void) {
    let a = NSAlert()
    a.messageText = title
    a.informativeText = message
    a.alertStyle = .informational
    let f = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
    f.stringValue = initial
    f.bezelStyle = .roundedBezel
    a.accessoryView = f
    a.addButton(withTitle: okTitle)
    a.addButton(withTitle: "取消")
    if a.runModal() == .alertFirstButtonReturn {
        let s = f.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if !s.isEmpty { done(s) }
    }
}

// MARK: - Editor asset model

struct EditorAsset {
    let relative: String
    let url: URL
    let category: String
    let sizeText: String
    let dims: String
    let isImage: Bool
}

private let editorImageExt: Set<String> = [
    ".png", ".icns", ".jpg", ".jpeg", ".webp", ".bmp", ".tif", ".tiff",
]
private let categoryOrder = ["背景", "选中框", "光标", "界面元素", "启动项图标",
                             "字体", "标签", "声音", "其他"]

func editorAssets(_ dir: URL, manifest: [String: Any]) -> [EditorAsset] {
    let fm = FileManager.default
    var category: [String: String] = [:]
    func put(_ value: Any?, _ cat: String) {
        if let s = value as? String, !s.isEmpty { category[s] = cat }
        if let list = value as? [String] { for s in list { category[s] = cat } }
    }
    put(manifest["background"], "背景")
    put(manifest["selected"], "选中框")
    put(manifest["cursor"], "光标")
    put(manifest["uiAssets"], "界面元素")
    for icon in (manifest["icons"] as? [[String: Any]] ?? []) { put(icon["path"], "启动项图标") }
    put(manifest["fonts"], "字体")
    put(manifest["labels"], "标签")
    put(manifest["sounds"], "声音")
    put(manifest["other"], "其他")

    guard let e = fm.enumerator(at: dir,
                                includingPropertiesForKeys: [.isDirectoryKey],
                                options: [.skipsHiddenFiles]) else { return [] }
    var out: [EditorAsset] = []
    for case let u as URL in e {
        let leaf = u.lastPathComponent
        guard leaf != "manifest.json", !leaf.hasPrefix("."), !leaf.hasPrefix("._") else { continue }
        var d: ObjCBool = false
        guard fm.fileExists(atPath: u.path, isDirectory: &d), !d.boolValue else { continue }
        let base = dir.path.hasSuffix("/") ? dir.path : dir.path + "/"
        let r = u.path.hasPrefix(base) ? String(u.path.dropFirst(base.count)) : leaf
        let isImage = editorImageExt.contains("." + u.pathExtension.lowercased())
        var dims = ""
        if isImage, let img = NSImage(contentsOf: u) {
            var w = 0, h = 0
            for rep in img.representations where rep.pixelsWide * rep.pixelsHigh > w * h {
                w = rep.pixelsWide; h = rep.pixelsHigh
            }
            if w > 0 { dims = "\(w)×\(h)" }
        }
        out.append(EditorAsset(relative: r, url: u,
                               category: category[r] ?? (isImage ? "启动项图标" : "其他"),
                               sizeText: humanSize(fileSize(u)), dims: dims,
                               isImage: isImage))
    }
    return out.sorted { a, b in
        let ia = categoryOrder.firstIndex(of: a.category) ?? 99
        let ib = categoryOrder.firstIndex(of: b.category) ?? 99
        if ia != ib { return ia < ib }
        return a.relative.lowercased() < b.relative.lowercased()
    }
}

// MARK: - Small views

/// Translucent dashed overlay shown while a drag hovers over a drop target.
final class DropHintView: NSView {
    var text = "松开以安装主题\n支持 ZIP 包 / 文件夹"
    override func draw(_ dirtyRect: NSRect) {
        NSColor.controlAccentColor.withAlphaComponent(0.10).setFill()
        NSBezierPath(rect: bounds).fill()
        let p = NSBezierPath(roundedRect: bounds.insetBy(dx: 6, dy: 6),
                             xRadius: 9, yRadius: 9)
        NSColor.controlAccentColor.withAlphaComponent(0.9).setStroke()
        p.lineWidth = 2
        let dash: [CGFloat] = [8, 5]
        p.setLineDash(dash, count: dash.count, phase: 0)
        p.stroke()
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 15, weight: .semibold),
            .foregroundColor: NSColor.labelColor,
        ]
        for (i, line) in text.split(separator: "\n").enumerated() {
            let s = NSAttributedString(string: String(line), attributes: attrs)
            let sz = s.size()
            s.draw(at: NSPoint(x: (bounds.width - sz.width) / 2,
                               y: bounds.height / 2 + 12 - CGFloat(i) * 24))
        }
    }
}

final class EditorAssetRowView: NSTableCellView {
    override var isFlipped: Bool { true }
    private let thumb = NSImageView()
    private let nameF = UI.label("", size: 11.5, weight: .medium)
    private let subF = UI.label("", size: 10, color: .secondaryLabelColor)

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        thumb.imageScaling = .scaleProportionallyUpOrDown
        for v in [thumb, nameF, subF] { addSubview(v) }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) unsupported") }

    func configure(_ a: EditorAsset) {
        thumb.image = a.isImage
            ? NSImage(contentsOf: a.url)
            : NSWorkspace.shared.icon(forFileType: a.url.pathExtension)
        nameF.stringValue = (a.relative as NSString).lastPathComponent
        subF.stringValue = a.category + (a.dims.isEmpty ? "" : " · " + a.dims) + " · " + a.sizeText
    }

    override func layout() {
        super.layout()
        thumb.frame = NSRect(x: 8, y: 4, width: 30, height: 30)
        let x: CGFloat = 46
        let w = bounds.width - x - 8
        nameF.frame = NSRect(x: x, y: 4, width: w, height: 16)
        subF.frame = NSRect(x: x, y: 20, width: w, height: 14)
    }
}

/// Left pane of the editor: resource list + actions + its own drop target.
final class AssetPaneView: NSView {
    override var isFlipped: Bool { true }
    var onFiles: (([URL]) -> Void)?
    let header = UI.section("主题资源")
    let scroll: NSScrollView
    let table: NSTableView
    let addBtn = UI.button("＋ 添加资源", height: 26)
    let replaceBtn = UI.button("替换…", height: 26)
    let removeBtn = UI.button("删除", height: 26)
    let hint = UI.label("也可把图片 / .icns / 字体直接拖进来添加",
                        size: 10, color: .secondaryLabelColor)
    private let overlay = DropHintView()

    override init(frame frameRect: NSRect) {
        let p = makeTable(rowHeight: 38)
        scroll = p.0; table = p.1
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        layer?.cornerRadius = 8
        layer?.borderColor = NSColor.separatorColor.cgColor
        layer?.borderWidth = 1
        overlay.text = "松开以添加资源\n图片 / 字体 / 标签 / 声音均可"
        overlay.isHidden = true
        for v in [header, scroll, addBtn, replaceBtn, removeBtn, hint, overlay] as [NSView] {
            addSubview(v)
        }
        hint.lineBreakMode = .byWordWrapping
        registerForDraggedTypes(themeDragTypes)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) unsupported") }

    override func layout() {
        super.layout()
        let pad: CGFloat = 10
        let w = bounds.width - pad * 2
        header.frame = NSRect(x: pad, y: 10, width: w, height: 15)
        let bottom: CGFloat = 62
        scroll.frame = NSRect(x: pad - 2, y: 30, width: w + 4,
                              height: max(60, bounds.height - 30 - bottom))
        let bw = (w - 12) / 3
        addBtn.frame = NSRect(x: pad, y: bounds.height - 54, width: bw, height: 26)
        replaceBtn.frame = NSRect(x: pad + bw + 6, y: bounds.height - 54, width: bw, height: 26)
        removeBtn.frame = NSRect(x: pad + (bw + 6) * 2, y: bounds.height - 54, width: bw, height: 26)
        hint.frame = NSRect(x: pad, y: bounds.height - 24, width: w, height: 16)
        overlay.frame = bounds
    }

    private func files(_ sender: NSDraggingInfo) -> [URL] {
        draggedFileURLs(sender.draggingPasteboard)
    }
    private func highlight(_ on: Bool) { overlay.isHidden = !on }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard !files(sender).isEmpty else { return [] }
        highlight(true)
        return .copy
    }
    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        files(sender).isEmpty ? [] : .copy
    }
    override func draggingExited(_ sender: NSDraggingInfo?) { highlight(false) }
    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
        !files(sender).isEmpty
    }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        highlight(false)
        let urls = files(sender)
        guard !urls.isEmpty else { return false }
        onFiles?(urls)
        return true
    }
    override func concludeDragOperation(_ sender: NSDraggingInfo?) { highlight(false) }
}

final class EditorRootView: NSView {
    override var isFlipped: Bool { true }

    let nameLabel = UI.label("主题名称", size: 11, color: .secondaryLabelColor)
    let nameField = UI.field("主题名称")
    let variantLabel = UI.label("PICKERVARIANT", size: 11, color: .secondaryLabelColor)
    let variantField = UI.field("Custom/OCThemeStudio")
    let stats = UI.label("", size: 10.5, color: .secondaryLabelColor, align: .right)
    let topLine = UI.hLine()

    let pane = AssetPaneView()
    let previewBox = NSView()
    let previewImage = NSImageView()
    let previewEmpty = UI.label("选择左侧资源以预览", size: 13,
                                color: .secondaryLabelColor, align: .center)
    let info = UI.label("", size: 10.5, color: .secondaryLabelColor)
    let labelTitle = UI.label("启动项显示名（本软件预览用）", size: 11, weight: .medium)
    let labelField = UI.field("例如 macOS / Windows / Recovery")
    let labelBtn = UI.button("应用名称", height: 26)
    let note = UI.label("", size: 10, color: .secondaryLabelColor)

    let bottomLine = UI.hLine()
    let finderBtn = UI.button("在 Finder 显示", height: 28)
    let exportBtn = UI.button("导出 ZIP…", height: 28)
    let duplicateBtn = UI.button("另存为副本…", height: 28)
    let icnsBtn = UI.button("⇄ 图片转 ICNS", height: 28)
    let doneBtn = UI.button("完成", height: 28, accent: true)
    let status = UI.label("", size: 10.5, color: .secondaryLabelColor)

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        previewBox.wantsLayer = true
        previewBox.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        previewBox.layer?.cornerRadius = 8
        previewBox.layer?.borderColor = NSColor.separatorColor.cgColor
        previewBox.layer?.borderWidth = 1
        previewImage.imageScaling = .scaleProportionallyUpOrDown
        previewImage.imageAlignment = .alignCenter
        previewImage.isHidden = true
        previewBox.addSubview(previewImage)
        previewBox.addSubview(previewEmpty)
        note.stringValue = """
        说明：OpenCanopy 菜单上的真实文字来自 Label 目录下的 .lbl / .l2x 位图，\
        可用「添加资源 / 替换…」更换。此处修改的是本软件预览与主题包内记录的显示名。\
        背景、选中框、光标与图标文件的替换都会同步更新安装清单，应用主题时会真实写入 EFI。
        """
        note.lineBreakMode = .byWordWrapping
        note.maximumNumberOfLines = 4

        for v in [nameLabel, nameField, variantLabel, variantField, stats, topLine,
                  pane, previewBox, info, labelTitle, labelField, labelBtn, note,
                  bottomLine, finderBtn, exportBtn, duplicateBtn, icnsBtn,
                  doneBtn, status] as [NSView] {
            addSubview(v)
        }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) unsupported") }

    override func layout() {
        super.layout()
        let pad: CGFloat = 16
        nameLabel.frame = NSRect(x: pad, y: 14, width: 70, height: 16)
        nameField.frame = NSRect(x: pad + 74, y: 10, width: 230, height: 24)
        variantLabel.frame = NSRect(x: pad + 326, y: 14, width: 110, height: 16)
        variantField.frame = NSRect(x: pad + 440, y: 10, width: 230, height: 24)
        stats.frame = NSRect(x: bounds.width - pad - 240, y: 14, width: 240, height: 16)
        topLine.frame = NSRect(x: pad, y: 48, width: bounds.width - pad * 2, height: 1)

        let bodyTop: CGFloat = 60
        let bodyH = max(220, bounds.height - bodyTop - 64)
        pane.frame = NSRect(x: pad, y: bodyTop, width: 340, height: bodyH)

        let rx = pad + 340 + 16
        let rw = bounds.width - rx - pad
        let previewH = max(150, bodyH - 156)
        previewBox.frame = NSRect(x: rx, y: bodyTop, width: rw, height: previewH)
        previewImage.frame = previewBox.bounds.insetBy(dx: 12, dy: 12)
        previewEmpty.frame = NSRect(x: 12, y: (previewBox.bounds.height - 20) / 2,
                                    width: previewBox.bounds.width - 24, height: 20)
        var y = bodyTop + previewH + 8
        info.frame = NSRect(x: rx + 4, y: y, width: rw - 8, height: 15)
        y += 23
        labelTitle.frame = NSRect(x: rx + 4, y: y, width: 240, height: 16)
        y += 20
        labelField.frame = NSRect(x: rx + 4, y: y, width: rw - 8 - 96, height: 24)
        labelBtn.frame = NSRect(x: rx + 4 + rw - 8 - 90, y: y, width: 90, height: 24)
        y += 30
        note.frame = NSRect(x: rx + 4, y: y, width: rw - 8, height: 52)

        bottomLine.frame = NSRect(x: pad, y: bounds.height - 60,
                                  width: bounds.width - pad * 2, height: 1)
        let by = bounds.height - 48
        finderBtn.frame = NSRect(x: pad, y: by, width: 124, height: 28)
        exportBtn.frame = NSRect(x: pad + 132, y: by, width: 110, height: 28)
        duplicateBtn.frame = NSRect(x: pad + 250, y: by, width: 124, height: 28)
        icnsBtn.frame = NSRect(x: pad + 382, y: by, width: 136, height: 28)
        doneBtn.frame = NSRect(x: bounds.width - pad - 96, y: by, width: 96, height: 28)
        let statusX = pad + 526
        status.frame = NSRect(x: statusX, y: by + 6,
                              width: max(40, doneBtn.frame.origin.x - statusX - 8), height: 16)
    }
}

// MARK: - Editor window controller

final class ThemeEditorWindowController: NSWindowController,
        NSTableViewDataSource, NSTableViewDelegate, NSTextFieldDelegate, NSWindowDelegate {

    private let assetRowID = NSUserInterfaceItemIdentifier("EditorAssetRow")
    var themeId = ""
    private var themeDir = URL(fileURLWithPath: "")
    private var themeName = ""
    private var assets: [EditorAsset] = []
    private var selectedAsset: EditorAsset?
    private var currentStem = ""
    private var onSaved: ((String) -> Void)?
    private var changed = false
    private var closing = false
    private var converter: ICNSWindowController?

    private var root: EditorRootView { window!.contentView as! EditorRootView }

    convenience init(theme: Theme, savedHandler: @escaping (String) -> Void) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1000, height: 680),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered, defer: false)
        window.title = "主题编辑器 · \(theme.name)"
        window.minSize = NSSize(width: 880, height: 620)
        window.center()
        window.setFrameAutosaveName("OCThemeStudioSwiftEditor")
        self.init(window: window)
        themeId = theme.id
        themeDir = theme.dir
        themeName = theme.name
        onSaved = savedHandler
        let size = window.contentRect(forFrameRect: window.frame).size
        window.contentView = EditorRootView(frame: NSRect(origin: .zero, size: size))
        window.delegate = self
        setup()
    }

    private func setup() {
        let r = root
        r.nameField.stringValue = themeName
        r.variantField.stringValue = (jsonRead(manifestFile())?["pickerVariant"] as? String ?? "")
            .replacingOccurrences(of: "/", with: "\\")
        r.nameField.delegate = self
        r.variantField.delegate = self

        r.pane.table.dataSource = self
        r.pane.table.delegate = self
        r.pane.table.target = self
        r.pane.table.action = #selector(assetTableClicked)
        r.pane.onFiles = { [weak self] urls in self?.addFiles(urls) }

        for (b, sel) in [(r.pane.addBtn, #selector(addResources)),
                         (r.pane.replaceBtn, #selector(replaceResource)),
                         (r.pane.removeBtn, #selector(removeResource)),
                         (r.labelBtn, #selector(applyLabel)),
                         (r.finderBtn, #selector(revealInFinder)),
                         (r.exportBtn, #selector(exportZIP)),
                         (r.duplicateBtn, #selector(saveCopy)),
                         (r.icnsBtn, #selector(openConverter)),
                         (r.doneBtn, #selector(finish))] as [(NSButton, Selector)] {
            b.target = self; b.action = sel
        }
        r.labelField.isEnabled = false
        r.labelBtn.isEnabled = false
        r.pane.replaceBtn.isEnabled = false
        r.pane.removeBtn.isEnabled = false
        refreshAssets()
    }

    private func manifestFile() -> URL { themeDir.appendingPathComponent("manifest.json") }

    private func refreshAssets(keepRelative: String? = nil) {
        let mf = jsonRead(manifestFile()) ?? [:]
        assets = editorAssets(themeDir, manifest: mf)
        root.pane.table.reloadData()
        root.pane.header.stringValue = "主题资源 · \(assets.count)"
        let icons = mf["icons"] as? [[String: Any]] ?? []
        let total = assets.reduce(Int64(0)) { $0 + fileSize($1.url) }
        root.stats.stringValue = "\(assets.count) 个文件 · \(humanSize(total)) · \(icons.count) 个启动项图标"
        if let keep = keepRelative,
           let i = assets.firstIndex(where: { $0.relative == keep }) {
            root.pane.table.selectRowIndexes(IndexSet(integer: i), byExtendingSelection: false)
            root.pane.table.scrollRowToVisible(i)
            selectedAsset = assets[i]
        } else {
            selectedAsset = nil
        }
        updatePreview()
    }

    private func updatePreview() {
        let r = root
        guard let a = selectedAsset else {
            r.previewImage.isHidden = true
            r.previewEmpty.isHidden = false
            r.info.stringValue = "在左侧选择一个资源即可查看预览与替换。"
            r.labelField.isEnabled = false
            r.labelBtn.isEnabled = false
            r.labelField.stringValue = ""
            currentStem = ""
            r.pane.replaceBtn.isEnabled = false
            r.pane.removeBtn.isEnabled = false
            return
        }
        if a.isImage, let img = NSImage(contentsOf: a.url) {
            r.previewImage.image = img
            r.previewImage.isHidden = false
            r.previewEmpty.isHidden = true
        } else {
            r.previewImage.isHidden = true
            r.previewEmpty.isHidden = false
            r.previewEmpty.stringValue = "非图片资源 · \(a.url.pathExtension.uppercased())"
        }
        r.info.stringValue = "\(a.category) · \(a.relative)" +
            (a.dims.isEmpty ? "" : " · \(a.dims)") + " · \(a.sizeText)"
        r.pane.replaceBtn.isEnabled = true
        r.pane.removeBtn.isEnabled = true

        let icons = (jsonRead(manifestFile())?["icons"] as? [[String: Any]] ?? [])
        if let hit = icons.first(where: { ($0["path"] as? String) == a.relative }) {
            currentStem = hit["name"] as? String ?? ""
            r.labelField.stringValue = hit["label"] as? String ?? ""
            r.labelField.isEnabled = true
            r.labelBtn.isEnabled = true
        } else {
            currentStem = ""
            r.labelField.stringValue = ""
            r.labelField.isEnabled = false
            r.labelBtn.isEnabled = false
        }
    }

    private func status(_ text: String) { root.status.stringValue = text }

    private func fail(_ title: String, _ error: Error) {
        let a = NSAlert()
        a.messageText = title
        a.informativeText = error.localizedDescription
        a.alertStyle = .critical
        a.addButton(withTitle: "好")
        if let w = window { a.beginSheetModal(for: w, completionHandler: nil) }
        else { a.runModal() }
    }

    private func markChanged() {
        changed = true
        status("已保存修改 · 应用主题时会使用新的资源清单")
    }

    /// Used only by the build-validation `--debug ... --asset N` mode.
    func debugSelectAsset(_ row: Int) {
        guard row >= 0 && row < assets.count else { return }
        root.pane.table.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        root.pane.table.scrollRowToVisible(row)
        selectedAsset = assets[row]
        updatePreview()
    }

    // MARK: Table

    func numberOfRows(in tableView: NSTableView) -> Int { assets.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let v = (tableView.makeView(withIdentifier: assetRowID, owner: self) as? EditorAssetRowView)
            ?? EditorAssetRowView()
        v.identifier = assetRowID
        v.configure(assets[row])
        return v
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        let row = root.pane.table.selectedRow
        selectedAsset = (row >= 0 && row < assets.count) ? assets[row] : nil
        updatePreview()
    }

    @objc private func assetTableClicked() {
        let row = root.pane.table.selectedRow
        selectedAsset = (row >= 0 && row < assets.count) ? assets[row] : nil
        updatePreview()
    }

    // MARK: Metadata

    private func commitMeta() {
        let name = root.nameField.stringValue
        let variant = root.variantField.stringValue
        do {
            try updateThemeMeta(themeDir, name: name, variant: variant)
            let newName = jsonRead(manifestFile())?["name"] as? String ?? themeName
            if newName != themeName || changed {
                themeName = newName
                window?.title = "主题编辑器 · \(themeName)"
                changed = true
            }
        } catch {
            fail("保存主题信息失败", error)
        }
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        guard let f = obj.object as? NSTextField else { return }
        if f === root.nameField || f === root.variantField { commitMeta() }
    }

    @objc private func applyLabel() {
        guard !currentStem.isEmpty else { return }
        do {
            try setThemeIconLabel(themeDir, stem: currentStem, label: root.labelField.stringValue)
            markChanged()
            refreshAssets(keepRelative: selectedAsset?.relative)
        } catch {
            fail("修改显示名失败", error)
        }
    }

    // MARK: Asset operations

    private func addFiles(_ urls: [URL]) {
        let fm = FileManager.default
        var files: [URL] = []
        for u in urls {
            var d: ObjCBool = false
            guard fm.fileExists(atPath: u.path, isDirectory: &d) else { continue }
            if d.boolValue {
                guard let e = fm.enumerator(at: u, includingPropertiesForKeys: [.isDirectoryKey],
                                            options: [.skipsHiddenFiles]) else { continue }
                for case let f as URL in e {
                    var fd: ObjCBool = false
                    guard fm.fileExists(atPath: f.path, isDirectory: &fd), !fd.boolValue else { continue }
                    files.append(f)
                }
            } else {
                files.append(u)
            }
        }
        guard !files.isEmpty else { return }
        do {
            let n = try addThemeAssets(themeDir, files: files)
            refreshAssets()
            markChanged()
            status("已添加 \(n) 个资源")
        } catch {
            fail("添加资源失败", error)
        }
    }

    @objc private func addResources() {
        let p = NSOpenPanel()
        p.message = "选择要加入主题的图片 / 图标 / 字体 / 标签 / 声音文件"
        p.canChooseFiles = true
        p.canChooseDirectories = true
        p.allowsMultipleSelection = true
        p.beginSheetModal(for: window!) { [weak self] resp in
            guard resp == .OK else { return }
            self?.addFiles(p.urls)
        }
    }

    @objc private func replaceResource() {
        guard let a = selectedAsset else { return }
        let p = NSOpenPanel()
        p.message = "选择新文件替换「\((a.relative as NSString).lastPathComponent)」"
        p.canChooseFiles = true
        p.canChooseDirectories = false
        p.allowsMultipleSelection = false
        p.beginSheetModal(for: window!) { [weak self] resp in
            guard resp == .OK, let u = p.url else { return }
            guard let self = self else { return }
            do {
                let newRel = try replaceThemeAsset(self.themeDir, relative: a.relative, with: u)
                self.refreshAssets(keepRelative: newRel)
                self.markChanged()
                self.status("已替换资源：\((newRel as NSString).lastPathComponent)")
            } catch {
                self.fail("替换资源失败", error)
            }
        }
    }

    @objc private func removeResource() {
        guard let a = selectedAsset else { return }
        let al = NSAlert()
        al.messageText = "删除资源"
        al.informativeText = "确定从主题中删除「\((a.relative as NSString).lastPathComponent)」？\n该资源将不会再随主题写入 EFI。"
        al.alertStyle = .critical
        al.addButton(withTitle: "删除")
        al.addButton(withTitle: "取消")
        al.beginSheetModal(for: window!) { [weak self] resp in
            guard resp == .alertFirstButtonReturn, let self = self else { return }
            do {
                try removeThemeAsset(self.themeDir, relative: a.relative)
                self.refreshAssets()
                self.markChanged()
                self.status("已删除资源")
            } catch {
                self.fail("删除资源失败", error)
            }
        }
    }

    // MARK: Bottom bar

    /// Convert a JPG / PNG into an OpenCore .icns and put it straight into the
    /// theme that is currently being edited.
    @objc private func openConverter() {
        if let c = converter, c.window?.isVisible == true {
            c.showWindow(nil)
            c.window?.makeKeyAndOrderFront(nil)
            return
        }
        let sel = selectedAsset
        let canReplace = sel?.url.pathExtension.lowercased() == "icns" ? sel?.relative : nil
        let c = ICNSWindowController(themeDir: themeDir, replaceRelative: canReplace) {
            [weak self] keepRelative in
            guard let self = self else { return }
            self.refreshAssets(keepRelative: keepRelative)
            self.markChanged()
            self.status("ICNS 已写入主题，安装清单已更新")
        }
        converter = c
        c.onClose = { [weak self] in self?.converter = nil }
        c.showWindow(nil)
        c.window?.makeKeyAndOrderFront(nil)
    }

    /// Debug hook used by the build-validation snapshot mode.
    func debugOpenConverter(_ image: URL? = nil) {
        openConverter()
        if let u = image { converter?.debugLoad(u) }
    }

    @objc private func revealInFinder() {
        NSWorkspace.shared.activateFileViewerSelecting([themeDir])
    }

    @objc private func exportZIP() {
        let p = NSSavePanel()
        p.title = "导出主题包"
        p.nameFieldStringValue = themeName
            .replacingOccurrences(of: "/", with: "-") + ".zip"
        p.allowedFileTypes = ["zip"]
        p.canCreateDirectories = true
        p.beginSheetModal(for: window!) { [weak self] resp in
            guard resp == .OK, let u = p.url, let self = self else { return }
            do {
                guard let t = Theme(dir: self.themeDir) else { throw AppError.message("主题已损坏") }
                try exportTheme(t, to: u)
                self.status("已导出 \(u.lastPathComponent)")
            } catch {
                self.fail("导出失败", error)
            }
        }
    }

    @objc private func saveCopy() {
        guard let t = Theme(dir: themeDir) else { return }
        askForThemeName("另存为副本", "将复制当前主题的全部资源，生成一套独立主题。",
                        themeName + " 副本", "创建副本") { [weak self] name in
            guard let self = self else { return }
            do {
                let copy = try duplicateTheme(t, name: name)
                self.themeId = copy.id
                self.themeDir = copy.dir
                self.themeName = copy.name
                self.root.nameField.stringValue = copy.name
                self.window?.title = "主题编辑器 · \(copy.name)"
                self.refreshAssets()
                self.markChanged()
                self.status("已切换编辑副本「\(copy.name)」")
                self.onSaved?(copy.id)
            } catch {
                self.fail("创建副本失败", error)
            }
        }
    }

    @objc private func finish() {
        commitMeta()
        closing = true
        window?.close()
    }

    func windowWillClose(_ notification: Notification) {
        guard !closing else {
            onSaved?(themeId)
            return
        }
        commitMeta()
        onSaved?(themeId)
    }
}
