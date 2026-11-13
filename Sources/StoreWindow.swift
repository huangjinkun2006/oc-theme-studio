import AppKit

// MARK: - Theme store window
//
// A simple two-pane store: a scrolling list of theme cards on the left and a
// detail / actions panel on the right. Themes come from a self-hosted HTTP
// backend (StoreClient) or, when no server is reachable, a bundled offline
// catalog of demo themes. "下载主题" imports the package into the local library;
// "应用主题" hands the imported Theme back to the main window's apply flow.

private let storeCardID = NSUserInterfaceItemIdentifier("StoreCard")

private func loadRemoteImage(_ url: URL, into iv: NSImageView) {
    if url.scheme == "http" || url.scheme == "https" {
        URLSession.shared.dataTask(with: url) { data, _, _ in
            if let data = data, let img = NSImage(data: data) {
                DispatchQueue.main.async { iv.image = img }
            }
        }.resume()
    } else if let img = NSImage(contentsOf: url) {
        iv.image = img
    }
}

final class StoreCardView: NSTableCellView {
    override var isFlipped: Bool { true }
    private let thumb = NSImageView()
    private let nameF = UI.label("", size: 13, weight: .semibold)
    private let authorF = UI.label("", size: 11, color: .secondaryLabelColor)
    private let tagF = UI.label("", size: 9.5, weight: .semibold)
    private let stateF = UI.label("", size: 10, color: .systemGreen, align: .right)

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        for v in [thumb, nameF, authorF, tagF, stateF] { addSubview(v) }
        thumb.imageScaling = .scaleProportionallyUpOrDown
        thumb.wantsLayer = true
        thumb.layer?.cornerRadius = 6
        thumb.layer?.masksToBounds = true
        tagF.wantsLayer = true
        tagF.layer?.cornerRadius = 3
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) unsupported") }

    func configure(_ t: StoreTheme, image: NSImage?, downloaded: Bool) {
        nameF.stringValue = t.name
        authorF.stringValue = "by \(t.author)" + (t.sizeText.map { " · \($0)" } ?? "")
        tagF.isHidden = false
        let bits = [t.categoryDisplay] + Array(t.tags.prefix(2))
        tagF.stringValue = " " + bits.joined(separator: " · ") + " "
        tagF.textColor = .controlAccentColor
        tagF.layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.14).cgColor
        stateF.stringValue = downloaded ? "已下载 ✓" : (t.localDemo ? "示例" : "")
        stateF.textColor = downloaded ? .systemGreen : .tertiaryLabelColor
        if let img = image { thumb.image = img }
        else if let u = StoreClient.thumbnailURL(for: t) { loadRemoteImage(u, into: thumb) }
    }

    override func layout() {
        super.layout()
        let pad: CGFloat = 12
        thumb.frame = NSRect(x: pad, y: 10, width: 52, height: 52)
        let x = pad + 52 + 12
        let w = bounds.width - x - pad
        nameF.frame = NSRect(x: x, y: 11, width: w, height: 18)
        authorF.frame = NSRect(x: x, y: 32, width: w, height: 14)
        tagF.frame = NSRect(x: x, y: 49, width: min(140, w), height: 14)
        stateF.frame = NSRect(x: bounds.width - 90, y: 11, width: 78, height: 16)
    }
}

final class StoreDetailView: NSView {
    override var isFlipped: Bool { true }
    let header = UI.section("主题详情")
    let thumb = NSImageView()
    let nameF = UI.label("", size: 17, weight: .semibold)
    let authorF = UI.label("", size: 12, color: .secondaryLabelColor)
    let tagsF = UI.label("", size: 11, color: .controlAccentColor)
    let descF = UI.label("", size: 12)
    let downloadBtn = UI.button("下载主题", height: 32, accent: true)
    let applyBtn = UI.button("应用主题", height: 32)
    let busy = NSProgressIndicator()
    let hint = UI.label("", size: 10.5, color: .secondaryLabelColor)

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        descF.lineBreakMode = .byWordWrapping
        descF.maximumNumberOfLines = 12
        thumb.imageScaling = .scaleProportionallyUpOrDown
        thumb.wantsLayer = true
        thumb.layer?.cornerRadius = 8
        thumb.layer?.masksToBounds = true
        thumb.layer?.borderWidth = 1
        thumb.layer?.borderColor = NSColor.separatorColor.cgColor
        busy.style = .spinning
        busy.controlSize = .small
        busy.isDisplayedWhenStopped = false
        for v in [header, thumb, nameF, authorF, tagsF, descF, downloadBtn,
                  applyBtn, busy, hint] as [NSView] { addSubview(v) }
        applyBtn.isEnabled = false
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) unsupported") }

    var theme: StoreTheme? { didSet { refresh() } }
    var localTheme: Theme? { didSet { applyBtn.isEnabled = localTheme != nil } }

    private func refresh() {
        guard let t = theme else {
            nameF.stringValue = ""; authorF.stringValue = ""; tagsF.stringValue = ""
            descF.stringValue = "从左侧选择一个主题查看详情。"
            thumb.image = nil; downloadBtn.isEnabled = false; applyBtn.isEnabled = false
            return
        }
        nameF.stringValue = t.name
        authorF.stringValue = "by \(t.author)" + (t.updated.map { " · 更新于 \($0)" } ?? "")
        let cat = "类型：" + t.categoryDisplay
        tagsF.stringValue = t.tags.isEmpty ? cat : cat + "   #" + t.tags.joined(separator: "  #")
        descF.stringValue = t.description
        downloadBtn.isEnabled = true
        if let u = StoreClient.thumbnailURL(for: t) { loadRemoteImage(u, into: thumb) }
    }

    override func layout() {
        super.layout()
        let pad: CGFloat = 18
        let w = bounds.width - pad * 2
        header.frame = NSRect(x: pad, y: 14, width: w, height: 15)
        thumb.frame = NSRect(x: pad, y: 38, width: w, height: min(220, w * 0.5))
        nameF.frame = NSRect(x: pad, y: thumb.frame.maxY + 14, width: w, height: 22)
        authorF.frame = NSRect(x: pad, y: nameF.frame.maxY + 4, width: w, height: 16)
        tagsF.frame = NSRect(x: pad, y: authorF.frame.maxY + 4, width: w, height: 15)
        descF.frame = NSRect(x: pad, y: tagsF.frame.maxY + 8, width: w, height: 150)
        let bw: CGFloat = (w - 10) / 2
        downloadBtn.frame = NSRect(x: pad, y: bounds.height - 44, width: bw, height: 32)
        applyBtn.frame = NSRect(x: pad + bw + 10, y: bounds.height - 44, width: bw, height: 32)
        busy.frame = NSRect(x: bounds.width / 2 - 12, y: bounds.height - 46, width: 24, height: 24)
        hint.frame = NSRect(x: pad, y: bounds.height - 66, width: w, height: 16)
    }
}

final class StoreView: NSView {
    override var isFlipped: Bool { true }
    let addrField = UI.field("主题商店服务器地址（留空使用内置示例）")
    let refreshBtn = UI.button("刷新", height: 26)
    let uploadBtn = UI.button("上传主题…", height: 26)
    let listScroll: NSScrollView
    let listTable: NSTableView
    let detail = StoreDetailView()
    let status = UI.label("就绪", size: 11, color: .secondaryLabelColor)
    let spinner = NSProgressIndicator()
    let titleF = UI.label("主题商店", size: 15, weight: .semibold)
    let catLabel = UI.label("分类", size: 11, color: .secondaryLabelColor)
    let categoryPop = NSPopUpButton()

    var onApplyTheme: ((Theme) -> Void)?
    fileprivate var themes: [StoreTheme] = []
    fileprivate var selected: StoreTheme?
    fileprivate var downloaded: [String: Theme] = [:]
    private var busy = false
    private var selectedCategory: StoreCategory = .all
    private var categoryCounts: [StoreCategory: Int] = [:]

    override init(frame frameRect: NSRect) {
        let p = makeTable(rowHeight: 74); listScroll = p.0; listTable = p.1
        super.init(frame: frameRect)
        spinner.style = .spinning; spinner.controlSize = .small; spinner.isDisplayedWhenStopped = false
        categoryPop.font = .systemFont(ofSize: 11.5)
        categoryPop.target = self
        categoryPop.action = #selector(categoryChanged)
        updateCategoryTitles()
        if let u = StoreClient.baseURL { addrField.stringValue = u.absoluteString }
        for v in [titleF, addrField, refreshBtn, uploadBtn, catLabel, categoryPop,
                  listScroll, detail, status, spinner] as [NSView] { addSubview(v) }
        listTable.target = self
        listTable.action = #selector(cardClicked)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) unsupported") }

    var controller: StoreWindowController?

    private func syncAddress() {
        StoreClient.saveBaseURL(addrField.stringValue.trimmingCharacters(in: .whitespaces))
    }

    /// 分类下拉标题附带服务端返回的数量；旧服务器没有 /api/categories 时只显示名称。
    private func updateCategoryTitles() {
        let current = selectedCategory
        categoryPop.removeAllItems()
        for c in StoreCategory.selectable {
            let suffix = categoryCounts[c].map { " (\($0))" } ?? ""
            categoryPop.addItem(withTitle: c.label + suffix)
        }
        if let idx = StoreCategory.selectable.firstIndex(of: current) {
            categoryPop.selectItem(at: idx)
        }
    }

    func refreshCategories() {
        StoreClient.categories { [weak self] counts in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.categoryCounts = counts
                self.updateCategoryTitles()
            }
        }
    }

    @objc private func categoryChanged() {
        let idx = categoryPop.indexOfSelectedItem
        guard idx >= 0, idx < StoreCategory.selectable.count else { return }
        selectedCategory = StoreCategory.selectable[idx]
        load()
    }

    func load() {
        syncAddress()
        setBusy(true, "正在获取主题列表…")
        let cat = selectedCategory
        StoreClient.list(category: cat) { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.setBusy(false)
                switch result {
                case .success(let ts):
                    self.themes = ts
                    self.listTable.reloadData()
                    let scope = cat == .all ? "" : " · \(cat.label)"
                    self.status.stringValue = "共 \(ts.count) 项" + scope +
                        (StoreClient.baseURL == nil ? "（离线示例，未连接服务器）" : "")
                    if let first = ts.first {
                        self.select(first)
                    } else {
                        self.selected = nil
                        self.detail.theme = nil
                        self.detail.localTheme = nil
                    }
                case .failure(let err):
                    self.status.stringValue = "加载失败：\(err.localizedDescription)"
                }
            }
        }
    }

    @objc func refresh() {
        refreshCategories()
        load()
    }

    @objc func cardClicked() {
        let row = listTable.selectedRow
        guard row >= 0, row < themes.count else { return }
        select(themes[row])
    }

    private func select(_ t: StoreTheme) {
        selected = t
        detail.theme = t
        detail.localTheme = downloaded[t.id]
        detail.downloadBtn.action = #selector(downloadSelected)
        detail.downloadBtn.target = self
        detail.applyBtn.action = #selector(applySelected)
        detail.applyBtn.target = self
    }

    @objc func downloadSelected() {
        guard let t = selected else { return }
        setBusy(true, "正在下载「\(t.name)」…")
        detail.downloadBtn.isEnabled = false
        StoreClient.download(t) { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.setBusy(false)
                self.detail.downloadBtn.isEnabled = true
                switch result {
                case .success(let r):
                    self.finishDownload(t, result: r)
                case .failure(let err):
                    self.status.stringValue = "下载失败：\(err.localizedDescription)"
                    self.detail.hint.stringValue = err.localizedDescription
                }
            }
        }
    }

    private func finishDownload(_ t: StoreTheme, result: StoreDownloadResult) {
        do {
            let theme: Theme
            switch result {
            case .local(let pid):
                guard let preset = ThemePreset.all().first(where: { $0.id == pid }) else {
                    throw StoreError.message("找不到示例预设 \(pid)")
                }
                theme = try makeTheme(name: t.name, preset: preset)
            case .remote(let zip):
                let created = try ThemeLibrary.shared.importPackage(zip, name: t.name)
                guard let first = created.first else {
                    throw StoreError.message("压缩包中没有识别到可用主题")
                }
                theme = first
            }
            downloaded[t.id] = theme
            detail.localTheme = theme
            listTable.reloadData()
            status.stringValue = "已下载「\(theme.name)」到主题库，可点「应用主题」。"
            detail.hint.stringValue = "已加入本机主题库，点「应用主题」写入 EFI。"
        } catch {
            status.stringValue = "下载处理失败：\(error.localizedDescription)"
            detail.hint.stringValue = error.localizedDescription
        }
    }

    @objc func applySelected() {
        guard let t = selected, let lt = downloaded[t.id] else {
            status.stringValue = "请先下载该主题，再应用。"
            return
        }
        onApplyTheme?(lt)
    }

    @objc func openUpload() { controller?.openUpload(from: self) }

    private func setBusy(_ on: Bool, _ text: String? = nil) {
        busy = on
        status.stringValue = text ?? (on ? "处理中…" : "就绪")
        spinner.isHidden = !on
        if on { spinner.startAnimation(nil) } else { spinner.stopAnimation(nil) }
        refreshBtn.isEnabled = !on
        uploadBtn.isEnabled = !on
    }

    override func layout() {
        super.layout()
        let pad: CGFloat = 16
        titleF.frame = NSRect(x: pad, y: 12, width: 160, height: 20)
        let toolbarY: CGFloat = 38
        let tfW: CGFloat = bounds.width - pad * 2 - 200
        addrField.frame = NSRect(x: pad, y: toolbarY, width: max(160, tfW), height: 26)
        refreshBtn.frame = NSRect(x: bounds.width - pad - 188, y: toolbarY, width: 90, height: 26)
        uploadBtn.frame = NSRect(x: bounds.width - pad - 90, y: toolbarY, width: 90, height: 26)
        let catY = toolbarY + 32
        catLabel.frame = NSRect(x: pad, y: catY + 5, width: 32, height: 16)
        categoryPop.frame = NSRect(x: pad + 36, y: catY, width: 160, height: 26)
        let top = catY + 34
        let leftW: CGFloat = 320
        listScroll.frame = NSRect(x: pad - 2, y: top, width: leftW,
                                  height: bounds.height - top - 28)
        detail.frame = NSRect(x: pad + leftW + 8, y: top,
                              width: bounds.width - pad * 2 - leftW - 8,
                              height: bounds.height - top - 28)
        spinner.frame = NSRect(x: pad, y: 6, width: 16, height: 16)
        status.frame = NSRect(x: pad + 22, y: 6, width: bounds.width - pad * 2 - 22, height: 16)
    }
}

final class StoreWindowController: NSWindowController, NSTableViewDataSource, NSTableViewDelegate {
    private var view: StoreView { window!.contentView as! StoreView }
    private var upload: StoreUploadWindowController?
    private var configured = false

    convenience init() {
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 980, height: 660),
                         styleMask: [.titled, .closable, .miniaturizable, .resizable],
                         backing: .buffered, defer: false)
        w.title = "主题商店"
        w.minSize = NSSize(width: 760, height: 580)
        w.center()
        let size = w.contentRect(forFrameRect: w.frame).size
        w.contentView = StoreView(frame: NSRect(origin: .zero, size: size))
        self.init(window: w)
        configure()
    }

    /// 纯代码 `init(window:)` 创建的 NSWindowController 不会触发 `windowDidLoad()`，
    /// 因此 dataSource / 按钮 target / 首次加载必须在这里显式完成。
    /// configure 幂等，避免 windowDidLoad 万一被调用时重复加载。
    private func configure() {
        guard !configured else { return }
        configured = true
        let v = view
        v.controller = self
        v.listTable.dataSource = self
        v.listTable.delegate = self
        v.refreshBtn.target = v; v.refreshBtn.action = #selector(StoreView.refresh)
        v.uploadBtn.target = v; v.uploadBtn.action = #selector(StoreView.openUpload)
        v.onApplyTheme = { [weak self] theme in
            self?.applyTheme(theme)
        }
        v.refreshCategories()
        v.load()
    }

    override func windowDidLoad() {
        super.windowDidLoad()
        configure()
    }

    func applyTheme(_ theme: Theme) {
        // Hand the imported theme to the main window's apply flow.
        AppDelegate.shared?.applyThemeFromStore(theme)
        window?.orderOut(nil)
    }

    func openUpload(from storeView: StoreView) {
        guard let w = window else { return }
        let u = StoreUploadWindowController()
        u.onSubmitted = { [weak self, weak storeView] in
            storeView?.refresh()
            self?.upload = nil
        }
        u.onCancel = { [weak self] in self?.upload = nil }
        upload = u   // 强引用：否则 sheet 控制器在函数返回后就被释放，回调失效
        u.showSheet(on: w)
    }

    func numberOfRows(in tableView: NSTableView) -> Int { view.themes.count }
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let t = view.themes[row]
        let v = (tableView.makeView(withIdentifier: storeCardID, owner: self) as? StoreCardView)
            ?? StoreCardView()
        v.identifier = storeCardID
        let img = view.downloaded[t.id].flatMap { $0.backgroundImage }
        v.configure(t, image: img, downloaded: view.downloaded[t.id] != nil)
        return v
    }
}

// MARK: - Upload sheet

final class StoreUploadView: NSView {
    override var isFlipped: Bool { true }
    let nameF = UI.field("主题名称")
    let authorF = UI.field("作者 / 昵称")
    let versionF = UI.field("版本（可选）")
    let tagsF = UI.field("标签，逗号分隔（如：macOS, 暗色, 极简）")
    let catLabel = UI.label("资源类型", size: 11, color: .secondaryLabelColor)
    let categoryPop = NSPopUpButton()
    let categoryHint = UI.label("", size: 10.5, color: .secondaryLabelColor)
    let descField = NSTextView(frame: .zero)
    let pkgBtn = UI.button("选择资源包（ZIP 或本机主题）…", height: 26)
    let pkgLabel = UI.label("未选择", size: 11, color: .secondaryLabelColor)
    let prevBtn = UI.button("添加预览图…", height: 26)
    let prevLabel = UI.label("未选择", size: 11, color: .secondaryLabelColor)
    let uploadBtn = UI.button("上传", height: 30, accent: true)
    let cancelBtn = UI.button("取消", height: 30)
    let status = UI.label("", size: 11, color: .secondaryLabelColor)

    var onUpload: ((StoreClient.UploadSpec) -> Void)?
    var onCancel: (() -> Void)?
    private var package: URL?
    private var previews: [URL] = []

    private var selectedCategory: StoreCategory {
        let idx = categoryPop.indexOfSelectedItem
        guard idx >= 0, idx < StoreCategory.uploadable.count else { return .theme }
        return StoreCategory.uploadable[idx]
    }

    private func updateCategoryHint() {
        switch selectedCategory {
        case .theme:
            categoryHint.stringValue = "完整主题：背景 + 启动项图标，可在 App 中直接应用。"
        case .icons:
            categoryHint.stringValue = "图标区：把 .icns 启动项图标打包成 .zip，App 会识别为仅图标包。"
        case .background:
            categoryHint.stringValue = "背景区：把 Background*.png / .icns 打包成 .zip。"
        case .fonts:
            categoryHint.stringValue = "字体区：把 .ttf / .otf 打包成 .zip；纯字体包下载后手动取用。"
        case .all:
            categoryHint.stringValue = ""
        }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        descField.isEditable = true
        descField.isRichText = false
        descField.font = .systemFont(ofSize: 12)
        descField.textContainerInset = NSSize(width: 4, height: 4)
        categoryPop.font = .systemFont(ofSize: 11.5)
        categoryPop.addItems(withTitles: StoreCategory.uploadable.map { $0.label })
        categoryPop.target = self; categoryPop.action = #selector(categoryChanged)
        categoryHint.lineBreakMode = .byWordWrapping
        categoryHint.maximumNumberOfLines = 2
        updateCategoryHint()
        let box = NSScrollView(frame: .zero)
        box.hasVerticalScroller = true
        box.documentView = descField
        box.wantsLayer = true
        box.layer?.borderWidth = 1
        box.layer?.borderColor = NSColor.separatorColor.cgColor
        box.layer?.cornerRadius = 5
        addSubview(box)
        for v in [nameF, authorF, versionF, tagsF, catLabel, categoryPop,
                  categoryHint, pkgBtn, pkgLabel, prevBtn,
                  prevLabel, uploadBtn, cancelBtn, status] as [NSView] { addSubview(v) }
        (self as StoreUploadView).scrollBox = box
        pkgBtn.target = self; pkgBtn.action = #selector(choosePkg)
        prevBtn.target = self; prevBtn.action = #selector(choosePrev)
        uploadBtn.target = self; uploadBtn.action = #selector(doUpload)
        cancelBtn.target = self; cancelBtn.action = #selector(doCancel)
    }
    var scrollBox: NSScrollView?
    required init?(coder: NSCoder) { fatalError("init(coder:) unsupported") }

    override func layout() {
        super.layout()
        let pad: CGFloat = 18
        let w = bounds.width - pad * 2
        var y: CGFloat = 14
        for (f, h) in [(nameF, 24), (authorF, 24), (versionF, 24), (tagsF, 24)] as [(NSTextField, CGFloat)] {
            f.frame = NSRect(x: pad, y: y, width: w, height: h); y += h + 8
        }
        catLabel.frame = NSRect(x: pad, y: y + 5, width: 60, height: 16)
        categoryPop.frame = NSRect(x: pad + 64, y: y, width: 170, height: 26)
        y += 26 + 4
        categoryHint.frame = NSRect(x: pad, y: y, width: w, height: 28)
        y += 28 + 8
        scrollBox?.frame = NSRect(x: pad, y: y, width: w, height: 70); y += 70 + 8
        pkgBtn.frame = NSRect(x: pad, y: y, width: 240, height: 26)
        pkgLabel.frame = NSRect(x: pad + 248, y: y + 5, width: w - 248, height: 16); y += 26 + 8
        prevBtn.frame = NSRect(x: pad, y: y, width: 120, height: 26)
        prevLabel.frame = NSRect(x: pad + 128, y: y + 5, width: w - 128, height: 16); y += 26 + 12
        let bw: CGFloat = (w - 10) / 2
        uploadBtn.frame = NSRect(x: pad, y: y, width: bw, height: 30)
        cancelBtn.frame = NSRect(x: pad + bw + 10, y: y, width: bw, height: 30); y += 30 + 6
        status.frame = NSRect(x: pad, y: y, width: w, height: 16)
    }

    @objc private func categoryChanged() {
        updateCategoryHint()
    }

    @objc private func choosePkg() {
        let p = NSOpenPanel()
        p.message = "选择资源包：.zip 资源包，或本机主题所在文件夹"
        p.canChooseFiles = true; p.canChooseDirectories = true
        p.allowedFileTypes = ["zip"]
        p.allowsMultipleSelection = false
        guard p.runModal() == .OK, let u = p.url else { return }
        package = u
        pkgLabel.stringValue = u.lastPathComponent
        pkgLabel.textColor = .labelColor
    }

    @objc private func choosePrev() {
        let p = NSOpenPanel()
        p.message = "添加预览图（可多选）"
        p.canChooseFiles = true; p.canChooseDirectories = false
        p.allowedFileTypes = ["png", "jpg", "jpeg"]
        p.allowsMultipleSelection = true
        guard p.runModal() == .OK else { return }
        previews = p.urls
        prevLabel.stringValue = "已选 \(previews.count) 张"
        prevLabel.textColor = .labelColor
    }

    @objc private func doUpload() {
        let spec = StoreClient.UploadSpec(
            name: nameF.stringValue.trimmingCharacters(in: .whitespaces),
            author: authorF.stringValue.trimmingCharacters(in: .whitespaces),
            description: descField.string.trimmingCharacters(in: .whitespacesAndNewlines),
            version: versionF.stringValue.trimmingCharacters(in: .whitespaces),
            tags: tagsF.stringValue.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty },
            category: selectedCategory.rawValue,
            package: package, previews: previews)
        guard !spec.name.isEmpty else { status.stringValue = "请填写主题名称"; return }
        if spec.package == nil { status.stringValue = "请先选择主题包"; return }
        status.stringValue = "正在上传…"
        onUpload?(spec)
    }

    @objc private func doCancel() { onCancel?() }
}

final class StoreUploadWindowController: NSWindowController {
    var onSubmitted: (() -> Void)?
    var onCancel: (() -> Void)?
    private var view: StoreUploadView { window!.contentView as! StoreUploadView }

    convenience init() {
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 460, height: 430),
                         styleMask: [.titled], backing: .buffered, defer: false)
        w.title = "上传主题 / 资源到商店"
        w.isReleasedWhenClosed = false
        let v = StoreUploadView(frame: NSRect(x: 0, y: 0, width: 460, height: 430))
        w.contentView = v
        self.init(window: w)
    }

    func showSheet(on parent: NSWindow) {
        view.onUpload = { [weak self] spec in
            self?.submit(spec)
        }
        view.onCancel = { [weak self] in
            guard let self = self, let sheet = self.window else { return }
            parent.endSheet(sheet, returnCode: .cancel)
            self.onCancel?()
        }
        parent.beginSheet(window!, completionHandler: nil)
    }

    private func submit(_ spec: StoreClient.UploadSpec) {
        StoreClient.upload(spec) { [weak self] result in
            guard let self = self else { return }
            DispatchQueue.main.async {
                switch result {
                case .success:
                    self.view.status.stringValue = "上传成功！"
                    self.onSubmitted?()
                    if let w = self.window, let p = w.sheetParent {
                        p.endSheet(w, returnCode: .OK)
                    }
                case .failure(let err):
                    self.view.status.stringValue = "上传失败：\(err.localizedDescription)"
                }
            }
        }
    }
}
