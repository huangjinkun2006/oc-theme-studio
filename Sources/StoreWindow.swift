import AppKit

// MARK: - Theme store window
//
// A simple two-pane store: a scrolling list of theme cards on the left and a
// detail / actions panel on the right. Themes come from a self-hosted HTTP
// backend (StoreClient) or, when no server is reachable, a bundled offline
// catalog of demo themes. "下载主题" imports the package into the local library;
// "应用主题" hands the imported Theme back to the main window's apply flow.

/// 明亮应用商店风配色，与网页商店 CSS token 一致（#f4f6fa / #fff / #2563eb …）。
enum StorePalette {
    static let bg         = NSColor(calibratedRed: 0.957, green: 0.965, blue: 0.980, alpha: 1)
    static let surface    = NSColor.white
    static let surface2   = NSColor(calibratedRed: 0.969, green: 0.976, blue: 0.988, alpha: 1)
    static let line       = NSColor(calibratedRed: 0.890, green: 0.910, blue: 0.937, alpha: 1)
    static let line2      = NSColor(calibratedRed: 0.831, green: 0.859, blue: 0.898, alpha: 1)
    static let text       = NSColor(calibratedRed: 0.106, green: 0.141, blue: 0.188, alpha: 1)
    static let muted      = NSColor(calibratedRed: 0.475, green: 0.522, blue: 0.584, alpha: 1)
    static let accent     = NSColor(calibratedRed: 0.145, green: 0.388, blue: 0.922, alpha: 1)
    static let accentSoft = NSColor(calibratedRed: 0.918, green: 0.945, blue: 1.000, alpha: 1)
    static let green      = NSColor(calibratedRed: 0.122, green: 0.616, blue: 0.388, alpha: 1)
}

private func storeCardShadow(_ layer: CALayer, hover: Bool) {
    layer.shadowColor = NSColor(calibratedRed: 0.086, green: 0.137, blue: 0.235, alpha: 1).cgColor
    layer.shadowOpacity = hover ? 0.18 : 0.07
    layer.shadowRadius = hover ? 12 : 5
    layer.shadowOffset = NSSize(width: 0, height: hover ? 5 : 2)
    layer.shouldRasterize = true
    layer.rasterizationScale = NSScreen.main?.backingScaleFactor ?? 2
}

/// 图片缓存：详情页翻页 / 网格滚动时避免重复下载同一张预览图。
private var storeImageCache: [String: NSImage] = [:]

private func loadStoreImage(_ path: String?, into iv: NSImageView,
                            placeholder: NSImage? = nil) {
    iv.image = placeholder
    guard let path = path, !path.isEmpty else { return }
    if let cached = storeImageCache[path] { iv.image = cached; return }
    guard let url = StoreClient.imageURL(for: path) else { return }
    if url.scheme == "http" || url.scheme == "https" {
        URLSession.shared.dataTask(with: url) { data, _, _ in
            guard let data = data, let img = NSImage(data: data) else { return }
            storeImageCache[path] = img
            DispatchQueue.main.async { iv.image = img }
        }.resume()
    } else if let img = NSImage(contentsOf: url) {
        storeImageCache[path] = img
        iv.image = img
    }
}

private func loadRemoteImage(_ url: URL, into iv: NSImageView) {
    loadStoreImage(url.absoluteString, into: iv)
}

/// 按名字稳定取头像底色，与网页 avatarColor 保持同一组颜色。
func storeAvatarTint(_ name: String) -> NSColor {
    let colors: [NSColor] = [.systemBlue, .systemTeal, .systemPurple,
                             .systemOrange, .systemPink, .systemBlue]
    var h: UInt32 = 0
    for c in name.unicodeScalars { h = h &* 31 &+ c.value }
    return colors[Int(h % UInt32(colors.count))]
}

func styleAvatarButton(_ b: NSButton, size: CGFloat) {
    b.bezelStyle = .rounded
    b.isBordered = false
    b.font = .systemFont(ofSize: max(9, size * 0.46), weight: .semibold)
    b.contentTintColor = .white
    b.imagePosition = .imageOnly
    b.imageScaling = .scaleAxesIndependently
    b.wantsLayer = true
    b.layer?.cornerRadius = size / 2
    b.layer?.masksToBounds = true
    b.layer?.backgroundColor = StorePalette.accent.cgColor
}

/// 头像按钮：有远程图片显示图片（SVG 会自然失败并保留首字母），否则显示首字母。
func setAvatarButton(_ b: NSButton, name: String, path: String?, size: CGFloat) {
    let initial = String(name.prefix(1)).uppercased()
    b.title = initial.isEmpty ? "?" : initial
    b.image = nil
    b.layer?.backgroundColor = storeAvatarTint(name).cgColor
    guard let path = path, !path.isEmpty else { return }
    if let cached = storeImageCache[path] { b.image = cached; return }
    guard let url = StoreClient.imageURL(for: path),
          url.scheme == "http" || url.scheme == "https" else { return }
    URLSession.shared.dataTask(with: url) { data, _, _ in
        guard let data = data, let img = NSImage(data: data) else { return }
        storeImageCache[path] = img
        DispatchQueue.main.async { b.image = img }
    }.resume()
}

/// 卡片内白底容器：必须 flipped，否则子视图 y 坐标自下而上，文字会倒排。
private final class StoreCardSurface: NSView {
    override var isFlipped: Bool { true }
}

/// 应用商店风大卡片：16:10 预览图 + 白卡 + 分类/标签 + hover 放大。
final class StoreCardTile: NSView {
    override var isFlipped: Bool { true }
    private let card = StoreCardSurface()
    private let cover = NSImageView()
    private let nameF = UI.label("", size: 12.5, weight: .semibold)
    private let authorAv = NSButton()
    private let authorF = NSButton()
    private let badgeF = UI.label("", size: 9.5, weight: .semibold, align: .center)
    private let stateF = UI.label("", size: 9.5, weight: .semibold, align: .right)
    var onSelect: (() -> Void)?
    var onAuthor: (() -> Void)?
    private var tracking: NSTrackingArea?
    private var theme: StoreTheme?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        card.wantsLayer = true
        card.layer?.backgroundColor = StorePalette.surface.cgColor
        card.layer?.cornerRadius = 12
        card.layer?.borderWidth = 1
        card.layer?.borderColor = StorePalette.line.cgColor
        storeCardShadow(card.layer!, hover: false)
        cover.imageScaling = .scaleProportionallyUpOrDown
        cover.wantsLayer = true
        cover.layer?.cornerRadius = 8
        cover.layer?.masksToBounds = true
        cover.layer?.backgroundColor = StorePalette.surface2.cgColor
        badgeF.wantsLayer = true
        badgeF.layer?.cornerRadius = 4
        styleAvatarButton(authorAv, size: 16)
        authorAv.target = self
        authorAv.action = #selector(authorClicked)
        authorF.bezelStyle = .rounded
        authorF.isBordered = false
        authorF.font = .systemFont(ofSize: 10.5)
        authorF.contentTintColor = StorePalette.muted
        authorF.target = self
        authorF.action = #selector(authorClicked)
        card.addSubview(cover)
        card.addSubview(nameF)
        card.addSubview(authorAv)
        card.addSubview(authorF)
        card.addSubview(badgeF)
        card.addSubview(stateF)
        addSubview(card)
        let click = NSClickGestureRecognizer(target: self, action: #selector(clicked))
        card.addGestureRecognizer(click)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) unsupported") }

    @objc private func clicked() { onSelect?() }
    @objc private func authorClicked() { onAuthor?() }

    func configure(_ t: StoreTheme, image: NSImage?, downloaded: Bool) {
        theme = t
        nameF.stringValue = t.name
        authorF.title = "by \(t.author)" + (t.sizeText.map { " · \($0)" } ?? "")
        let authorKey = t.authorLogin ?? t.author
        authorAv.isHidden = authorKey.isEmpty
        if !authorKey.isEmpty {
            setAvatarButton(authorAv, name: t.author, path: t.authorAvatar, size: 16)
        }
        let bits = [t.categoryDisplay] + Array(t.tags.prefix(1))
        badgeF.stringValue = " " + bits.joined(separator: " · ") + " "
        badgeF.textColor = StorePalette.accent
        badgeF.layer?.backgroundColor = StorePalette.accentSoft.cgColor
        stateF.stringValue = downloaded ? "已下载 ✓" : (t.localDemo ? "示例" : "")
        stateF.textColor = downloaded ? StorePalette.green : StorePalette.muted
        if let img = image { cover.image = img }
        else { loadStoreImage(t.previewPaths.first, into: cover) }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let ta = tracking { removeTrackingArea(ta) }
        tracking = NSTrackingArea(rect: bounds,
            options: [.mouseEnteredAndExited, .activeInKeyWindow], owner: self, userInfo: nil)
        if let ta = tracking { addTrackingArea(ta) }
    }
    override func mouseEntered(with event: NSEvent) {
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.16
            card.animator().layer?.transform = CATransform3DMakeScale(1.035, 1.035, 1)
        }
        storeCardShadow(card.layer!, hover: true)
        card.layer?.borderColor = StorePalette.line2.cgColor
    }
    override func mouseExited(with event: NSEvent) {
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.16
            card.animator().layer?.transform = CATransform3DIdentity
        }
        storeCardShadow(card.layer!, hover: false)
        card.layer?.borderColor = StorePalette.line.cgColor
    }

    override func layout() {
        super.layout()
        card.frame = bounds.insetBy(dx: 1, dy: 1)
        let pad: CGFloat = 9
        let cw = card.bounds.width
        let imgH = (cw - pad * 2) * 10 / 16          // 16:10
        cover.frame = NSRect(x: pad, y: pad, width: cw - pad * 2, height: imgH)
        let y = cover.frame.maxY + 7
        nameF.frame = NSRect(x: pad, y: y, width: cw - pad * 2 - 58, height: 16)
        authorAv.frame = NSRect(x: pad, y: y + 17, width: 16, height: 16)
        authorF.frame = NSRect(x: pad + 20, y: y + 17, width: cw - pad * 2 - 20, height: 16)
        badgeF.frame = NSRect(x: pad, y: y + 32, width: min(150, cw - pad * 2 - 60), height: 14)
        stateF.frame = NSRect(x: cw - pad - 56, y: y, width: 56, height: 14)
    }
}

/// 自适应网格容器：按可用宽度排 1–3 列，承载 StoreCardTile。
final class StoreGridContainer: NSView {
    override var isFlipped: Bool { true }
    var tiles: [StoreCardTile] = [] {
        didSet { oldValue.forEach { $0.removeFromSuperview() }; tiles.forEach { addSubview($0) } }
    }

    /// 按给定宽度排布卡片并返回所需总高度。
    /// 不放在 layout() 里 setFrameSize —— NSScrollView 的 documentView 在该时机改高度不生效。
    @discardableResult
    func arrange(width: CGFloat) -> CGFloat {
        guard !tiles.isEmpty, width > 20 else { return 0 }
        let gap: CGFloat = 12
        let minW: CGFloat = 210
        let cols = max(1, min(3, Int((width + gap) / (minW + gap))))
        let tw = (width - gap * CGFloat(cols - 1)) / CGFloat(cols)
        let th = tw * 10 / 16 + 74
        for (i, tile) in tiles.enumerated() {
            let r = i / cols, c = i % cols
            tile.frame = NSRect(x: CGFloat(c) * (tw + gap), y: CGFloat(r) * (th + gap),
                                width: tw, height: th)
        }
        let rows = (tiles.count + cols - 1) / cols
        return CGFloat(rows) * th + CGFloat(max(0, rows - 1)) * gap
    }
}

final class StoreDetailView: NSView {
    override var isFlipped: Bool { true }
    let header = UI.label("主题详情", size: 11, weight: .semibold, color: StorePalette.muted)
    let stage = NSView()
    let mainThumb = NSImageView()
    let prevBtn = NSButton()
    let nextBtn = NSButton()
    let pageF = UI.label("", size: 10, color: StorePalette.muted, align: .center)
    let thumbs = NSView()
    let nameF = UI.label("", size: 17, weight: .semibold)
    let avatar = NSButton()
    let authorName = UI.label("", size: 12, weight: .semibold)
    let authorF = UI.label("", size: 11, color: StorePalette.muted)
    let statBox = NSView()
    var statLabels: [NSTextField] = []
    var statKeys: [NSTextField] = []
    let descHead = UI.label("主题简介", size: 10.5, weight: .semibold, color: StorePalette.muted)
    let descF = UI.label("", size: 12)
    let descMore = NSButton()
    let tagsHead = UI.label("标签", size: 10.5, weight: .semibold, color: StorePalette.muted)
    let tagsF = UI.label("", size: 11, color: StorePalette.accent)
    let versionHead = UI.label("版本历史", size: 10.5, weight: .semibold, color: StorePalette.muted)
    let versionUploadBtn = UI.button("上传新版本", height: 22)
    let versionBox = NSView()
    var versionBtns: [NSButton] = []
    let versionMoreF = UI.label("", size: 10, color: StorePalette.muted, align: .right)
    let relatedHead = UI.label("同分类推荐", size: 10.5, weight: .semibold, color: StorePalette.muted)
    let related = NSView()
    let downloadBtn = UI.button("下载主题", height: 34, accent: true)
    let applyBtn = UI.button("应用主题", height: 34)
    let busy = NSProgressIndicator()
    let hint = UI.label("", size: 10.5, color: StorePalette.muted)

    /// 同分类推荐点击回调（由 StoreView 注入，复用其 select(_:)）。
    var onPickRelated: ((StoreTheme) -> Void)?
    /// 作者头像 / 昵称点击回调（由 StoreView 注入，打开用户主页）。
    var onAuthor: (() -> Void)?
    /// 版本历史：下载指定版本 / 上传新版本（由 StoreView 注入）。
    var onDownloadVersion: ((String) -> Void)?
    var onUploadVersion: (() -> Void)?
    private var authorKey = ""
    private var versionList: [StoreThemeVersion] = []
    private var relatedThemes: [StoreTheme] = []
    private var relatedBtns: [NSButton] = []
    private var previews: [String] = []
    private var page = 0
    private var thumbIVs: [NSImageView] = []
    private var descExpanded = false
    private static let perPage = 3

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = StorePalette.surface.cgColor
        descF.lineBreakMode = .byWordWrapping
        descF.maximumNumberOfLines = 4
        styleAvatarButton(avatar, size: 30)
        avatar.target = self
        avatar.action = #selector(authorClicked)
        authorName.addGestureRecognizer(NSClickGestureRecognizer(target: self,
                                                                 action: #selector(authorClicked)))
        statBox.wantsLayer = true
        statBox.layer?.backgroundColor = StorePalette.surface2.cgColor
        statBox.layer?.cornerRadius = 9
        statBox.layer?.borderWidth = 1
        statBox.layer?.borderColor = StorePalette.line.cgColor
        statLabels = (0..<4).map { _ in
            let l = UI.label("—", size: 13, weight: .bold, color: StorePalette.text, align: .center)
            l.lineBreakMode = .byClipping
            return l
        }
        statKeys = ["下载", "评论", "大小", "版本"].map {
            UI.label($0, size: 9.5, color: StorePalette.muted, align: .center)
        }
        statLabels.forEach { statBox.addSubview($0) }
        statKeys.forEach { statBox.addSubview($0) }
        descMore.bezelStyle = .rounded
        descMore.title = "展开全文"
        descMore.font = .systemFont(ofSize: 10.5, weight: .semibold)
        descMore.contentTintColor = StorePalette.accent
        descMore.target = self
        descMore.action = #selector(toggleDesc)
        descMore.isBordered = false
        relatedBtns = (0..<6).map { _ in
            let b = NSButton()
            b.bezelStyle = .rounded
            b.font = .systemFont(ofSize: 10.5, weight: .medium)
            b.target = self
            b.action = #selector(relatedClicked(_:))
            b.wantsLayer = true
            b.layer?.cornerRadius = 6
            b.layer?.borderWidth = 1
            b.layer?.borderColor = StorePalette.line.cgColor
            b.layer?.backgroundColor = StorePalette.surface.cgColor
            return b
        }
        relatedBtns.forEach { related.addSubview($0) }
        versionBox.wantsLayer = true
        versionBox.layer?.backgroundColor = StorePalette.surface2.cgColor
        versionBox.layer?.cornerRadius = 7
        versionBox.layer?.borderWidth = 1
        versionBox.layer?.borderColor = StorePalette.line.cgColor
        versionBtns = (0..<4).map { _ in
            let b = NSButton(title: "", target: self, action: #selector(versionClicked(_:)))
            b.bezelStyle = .rounded
            b.font = .systemFont(ofSize: 9.5, weight: .medium)
            b.contentTintColor = StorePalette.accent
            b.isBordered = false
            b.isHidden = true
            return b
        }
        versionBtns.forEach { versionBox.addSubview($0) }
        versionBox.addSubview(versionMoreF)
        versionUploadBtn.font = .systemFont(ofSize: 10.5, weight: .semibold)
        versionUploadBtn.target = self
        versionUploadBtn.action = #selector(uploadVersionClicked)
        versionUploadBtn.isHidden = true
        mainThumb.imageScaling = .scaleProportionallyUpOrDown
        mainThumb.wantsLayer = true
        mainThumb.layer?.cornerRadius = 10
        mainThumb.layer?.masksToBounds = true
        mainThumb.layer?.backgroundColor = StorePalette.surface2.cgColor
        stage.wantsLayer = true
        stage.layer?.backgroundColor = StorePalette.surface2.cgColor
        stage.layer?.cornerRadius = 10
        stage.layer?.masksToBounds = true
        for (b, a) in [(prevBtn, #selector(prevPage)), (nextBtn, #selector(nextPage))] {
            b.bezelStyle = .rounded
            b.title = a == #selector(prevPage) ? "‹" : "›"
            b.font = .systemFont(ofSize: 16, weight: .semibold)
            b.target = self
            b.action = a
            b.wantsLayer = true
            b.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.85).cgColor
            b.layer?.cornerRadius = 12
        }
        thumbIVs = (0..<StoreDetailView.perPage).map { _ in
            let iv = NSImageView()
            iv.imageScaling = .scaleProportionallyUpOrDown
            iv.wantsLayer = true
            iv.layer?.cornerRadius = 4
            iv.layer?.masksToBounds = true
            iv.layer?.borderWidth = 1
            iv.layer?.borderColor = StorePalette.line.cgColor
            iv.layer?.backgroundColor = StorePalette.surface2.cgColor
            return iv
        }
        thumbIVs.forEach { thumbs.addSubview($0) }
        busy.style = .spinning
        busy.controlSize = .small
        busy.isDisplayedWhenStopped = false
        for v in [header, stage, mainThumb, prevBtn, nextBtn, pageF, thumbs,
                  nameF, avatar, authorName, authorF, statBox,
                  descHead, descF, descMore, tagsHead, tagsF,
                  versionHead, versionUploadBtn, versionBox,
                  relatedHead, related,
                  downloadBtn, applyBtn, busy, hint] as [NSView] {
            addSubview(v)
        }
        applyBtn.isEnabled = false
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) unsupported") }

    var theme: StoreTheme? { didSet { refresh() } }
    var localTheme: Theme? { didSet { applyBtn.isEnabled = localTheme != nil } }

    @objc private func prevPage() {
        guard !previews.isEmpty else { return }
        page = (page - 1 + max(1, (previews.count + StoreDetailView.perPage - 1) / StoreDetailView.perPage))
            % max(1, (previews.count + StoreDetailView.perPage - 1) / StoreDetailView.perPage)
        renderPage()
    }
    @objc private func nextPage() {
        guard !previews.isEmpty else { return }
        let pages = max(1, (previews.count + StoreDetailView.perPage - 1) / StoreDetailView.perPage)
        page = (page + 1) % pages
        renderPage()
    }
    private func renderPage() {
        let pages = max(1, (previews.count + StoreDetailView.perPage - 1) / StoreDetailView.perPage)
        let start = page * StoreDetailView.perPage
        for (i, iv) in thumbIVs.enumerated() {
            let idx = start + i
            iv.isHidden = idx >= previews.count
            if !iv.isHidden { loadStoreImage(previews[idx], into: iv) }
        }
        pageF.stringValue = previews.count > StoreDetailView.perPage
            ? "\(page + 1)/\(pages)" : ""
        let hideNav = previews.count <= StoreDetailView.perPage
        prevBtn.isHidden = hideNav
        nextBtn.isHidden = hideNav
    }

    /// 四项统计：下载 / 评论 / 大小 / 版本。评论数来自 to_public 的 commentCount。
    func renderStats(_ t: StoreTheme?) {
        guard let t = t else {
            statLabels.forEach { $0.stringValue = "—" }
            return
        }
        let vals = ["\(t.downloads ?? 0)", "\(t.commentCount ?? 0)",
                    t.sizeText ?? "—", t.version.map { "v\($0)" } ?? "—"]
        for (i, l) in statLabels.enumerated() { l.stringValue = i < vals.count ? vals[i] : "—" }
    }

    /// 同分类推荐（最多 6 个），复用 StoreView 已加载的列表。
    func setRelated(_ list: [StoreTheme]) {
        relatedThemes = list
        for (i, b) in relatedBtns.enumerated() {
            let on = i < list.count
            b.isHidden = !on
            if on { b.title = list[i].name }
        }
        relatedHead.isHidden = list.isEmpty
    }

    @objc private func relatedClicked(_ sender: NSButton) {
        guard let idx = relatedBtns.firstIndex(of: sender), idx < relatedThemes.count else { return }
        onPickRelated?(relatedThemes[idx])
    }
    private func renderVersions(_ t: StoreTheme) {
        versionList = t.versions ?? []
        let on = !versionList.isEmpty
        versionHead.isHidden = !on
        versionBox.isHidden = !on
        for (i, b) in versionBtns.enumerated() {
            let visible = i < versionList.count
            b.isHidden = !visible
            if visible {
                let v = versionList[i]
                let note = (v.notes?.isEmpty == false) ? (v.notes ?? "")
                           : (i == 0 ? "当前版本" : "历史版本")
                b.title = "v\(v.version ?? "") · \(note)"
                b.tag = i
            }
        }
        let extra = versionList.count - versionBtns.count
        versionMoreF.isHidden = extra <= 0
        versionMoreF.stringValue = extra > 0 ? "+\(extra)" : ""
        let me = StoreClient.currentUser
        let mine = (me?.loginName.lowercased() == authorKey.lowercased()
                    && !authorKey.isEmpty) || me?.isAdmin == true
        versionUploadBtn.isHidden = !mine
    }

    @objc private func authorClicked() { onAuthor?() }
    @objc private func versionClicked(_ sender: NSButton) {
        guard sender.tag >= 0, sender.tag < versionList.count,
              let v = versionList[sender.tag].version else { return }
        onDownloadVersion?(v)
    }
    @objc private func uploadVersionClicked() { onUploadVersion?() }

    @objc private func toggleDesc() {
        descExpanded.toggle()
        descF.maximumNumberOfLines = descExpanded ? 0 : 4
        descMore.title = descExpanded ? "收起" : "展开全文"
        needsLayout = true
    }

    private func refresh() {
        guard let t = theme else {
            nameF.stringValue = ""; authorF.stringValue = ""; authorName.stringValue = ""
            tagsF.stringValue = ""; setAvatarButton(avatar, name: "?", path: nil, size: 30)
            authorKey = ""
            descF.stringValue = "从左侧选择一个主题查看详情。"
            downloadBtn.title = "下载主题"; hint.stringValue = ""
            mainThumb.image = nil; downloadBtn.isEnabled = false; applyBtn.isEnabled = false
            previews = []; page = 0; renderPage(); renderStats(nil); setRelated([])
            versionList = []
            versionBtns.forEach { $0.isHidden = true }
            versionHead.isHidden = true; versionBox.isHidden = true
            versionUploadBtn.isHidden = true; versionMoreF.isHidden = true
            return
        }
        nameF.stringValue = t.name
        let author = t.author.isEmpty ? "匿名" : t.author
        authorName.stringValue = "by \(author)"
        authorF.stringValue = t.updated.map { "更新于 \($0)" } ?? ""
        authorKey = t.authorLogin ?? (t.author.isEmpty ? "" : t.author)
        avatar.isHidden = authorKey.isEmpty
        setAvatarButton(avatar, name: author, path: t.authorAvatar, size: 30)
        let cat = "类型：" + t.categoryDisplay
        tagsF.stringValue = t.tags.isEmpty ? cat : cat + "   #" + t.tags.joined(separator: "  #")
        renderVersions(t)
        descF.stringValue = t.description
        descExpanded = false
        descF.maximumNumberOfLines = 4
        descMore.title = "展开全文"
        descMore.isHidden = t.description.count <= 70
        renderStats(t)
        let isEFI = t.categoryKind == .efi
        let baseLabel = isEFI ? "下载并安装…" : "下载主题"
        downloadBtn.title = t.latestVersion.map { "\(baseLabel) · v\($0)" } ?? baseLabel
        hint.stringValue = isEFI
            ? "下载后按主窗口所选 EFI 分区安装，写入前自动备份 Resources 与 config.plist。"
            : ""
        downloadBtn.isEnabled = true
        previews = t.previewPaths
        page = 0
        if let first = previews.first { loadStoreImage(first, into: mainThumb) }
        else { mainThumb.image = nil }
        renderPage()
    }

    override func layout() {
        super.layout()
        let pad: CGFloat = 14
        let w = bounds.width - pad * 2
        header.frame = NSRect(x: pad, y: 10, width: w, height: 14)
        let imageH = min(180, (w - 2) * 10 / 16)
        stage.frame = NSRect(x: pad, y: 28, width: w, height: imageH)
        mainThumb.frame = stage.frame
        prevBtn.frame = NSRect(x: pad + 8, y: 28 + imageH / 2 - 13, width: 26, height: 26)
        nextBtn.frame = NSRect(x: pad + w - 34, y: 28 + imageH / 2 - 13, width: 26, height: 26)
        let thumbsY = stage.frame.maxY + 5
        thumbs.frame = NSRect(x: pad, y: thumbsY, width: w - 40, height: 38)
        let tw = (thumbs.bounds.width - 4 * 4) / 3
        for (i, iv) in thumbIVs.enumerated() {
            iv.frame = NSRect(x: 4 + CGFloat(i) * (tw + 4), y: 1, width: tw, height: 36)
        }
        pageF.frame = NSRect(x: pad + w - 36, y: thumbsY + 12, width: 34, height: 14)

        var y = thumbs.frame.maxY + 8
        nameF.frame = NSRect(x: pad, y: y, width: w, height: 22); y += 24
        // 作者行：圆形头像 + 昵称 + 更新时间
        avatar.frame = NSRect(x: pad, y: y, width: 30, height: 30)
        authorName.frame = NSRect(x: pad + 38, y: y + 1, width: w - 38, height: 15)
        authorF.frame = NSRect(x: pad + 38, y: y + 16, width: w - 38, height: 13)
        y += 34
        // 四项统计条
        statBox.frame = NSRect(x: pad, y: y, width: w, height: 42); y += 50
        let cw = statBox.bounds.width / 4
        for (i, l) in statLabels.enumerated() {
            l.frame = NSRect(x: CGFloat(i) * cw, y: 4, width: cw, height: 17)
            statKeys[i].frame = NSRect(x: CGFloat(i) * cw, y: 22, width: cw, height: 14)
        }

        descHead.frame = NSRect(x: pad, y: y, width: w, height: 14); y += 16
        let descH: CGFloat = descExpanded
            ? min(150, max(40, bounds.height - y - 190))
            : min(72, max(34, bounds.height - y - 190))
        descF.frame = NSRect(x: pad, y: y, width: w, height: descH)
        y += descH + 2
        descMore.frame = NSRect(x: pad, y: y, width: 80, height: 18); y += 22

        tagsHead.frame = NSRect(x: pad, y: y, width: w, height: 14); y += 16
        tagsF.frame = NSRect(x: pad, y: y, width: w, height: 16); y += 20

        versionHead.frame = NSRect(x: pad, y: y, width: w - 110, height: 14)
        versionUploadBtn.frame = NSRect(x: pad + w - 100, y: y - 4, width: 100, height: 22)
        y += 18
        versionBox.frame = NSRect(x: pad, y: y, width: w, height: 28)
        let vw = max(30, (w - 66) / CGFloat(max(1, versionBtns.count)))
        for (i, b) in versionBtns.enumerated() {
            b.frame = NSRect(x: 4 + CGFloat(i) * (vw + 4), y: 3, width: vw, height: 22)
        }
        versionMoreF.frame = NSRect(x: w - 58, y: 7, width: 54, height: 16)
        y += 34

        relatedHead.frame = NSRect(x: pad, y: y, width: w, height: 14); y += 16
        related.frame = NSRect(x: pad, y: y, width: w, height: 34)
        let bw2 = (w - 5 * 5) / 6
        for (i, b) in relatedBtns.enumerated() {
            b.frame = NSRect(x: 5 + CGFloat(i) * (bw2 + 5), y: 0, width: bw2, height: 34)
        }

        let bw: CGFloat = (w - 10) / 2
        downloadBtn.frame = NSRect(x: pad, y: bounds.height - 44, width: bw, height: 34)
        applyBtn.frame = NSRect(x: pad + bw + 10, y: bounds.height - 44, width: bw, height: 34)
        busy.frame = NSRect(x: bounds.width / 2 - 12, y: bounds.height - 46, width: 24, height: 24)
        hint.frame = NSRect(x: pad, y: bounds.height - 64, width: w, height: 16)
    }
}

final class StoreView: NSView {
    override var isFlipped: Bool { true }
    let addrField = UI.field("主题商店服务器地址（留空使用内置示例）")
    let refreshBtn = UI.button("刷新", height: 26)
    let uploadBtn = UI.button("上传主题…", height: 26)
    let userAvatarBtn = NSButton()
    let userNameBtn = UI.button("登录 / 注册", height: 26)
    let listScroll = NSScrollView()
    let grid = StoreGridContainer()
    let detail = StoreDetailView()
    let status = UI.label("就绪", size: 11, color: StorePalette.muted)
    let spinner = NSProgressIndicator()
    let titleF = UI.label("主题商店", size: 18, weight: .bold)
    let subF = UI.label("按完整主题 / 图标 / 背景 / 字体 / EFI 浏览，任何平台都能参与", size: 11, color: StorePalette.muted)
    let searchF = UI.field("🔍 搜索主题、作者或标签…")
    var categoryPills: [NSButton] = []

    var onApplyTheme: ((Theme) -> Void)?
    fileprivate var themes: [StoreTheme] = []
    fileprivate var selected: StoreTheme?
    fileprivate var downloaded: [String: Theme] = [:]
    private var busy = false
    private var selectedCategory: StoreCategory = .all
    private var categoryCounts: [StoreCategory: Int] = [:]
    private var query = ""

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = StorePalette.bg.cgColor
        spinner.style = .spinning; spinner.controlSize = .small; spinner.isDisplayedWhenStopped = false
        listScroll.drawsBackground = false
        listScroll.hasVerticalScroller = true
        listScroll.documentView = grid
        if let u = StoreClient.baseURL { addrField.stringValue = u.absoluteString }
        searchF.target = self
        searchF.action = #selector(searchChanged)
        styleAvatarButton(userAvatarBtn, size: 26)
        userAvatarBtn.target = self
        userAvatarBtn.action = #selector(openOwnProfile)
        for v in [titleF, subF, addrField, refreshBtn, uploadBtn,
                  userAvatarBtn, userNameBtn, searchF,
                  listScroll, detail, status, spinner] as [NSView] { addSubview(v) }
        buildPills()
        updateUserUI()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) unsupported") }

    var controller: StoreWindowController?

    private func syncAddress() {
        StoreClient.saveBaseURL(addrField.stringValue.trimmingCharacters(in: .whitespaces))
    }

    private func buildPills() {
        categoryPills.forEach { $0.removeFromSuperview() }
        categoryPills = StoreCategory.selectable.map { c in
            let b = NSButton(title: c.label, target: self, action: #selector(pillClicked))
            b.bezelStyle = .rounded
            b.font = .systemFont(ofSize: 11, weight: .medium)
            b.tag = StoreCategory.selectable.firstIndex(of: c) ?? 0
            b.wantsLayer = true
            b.layer?.cornerRadius = 12
            return b
        }
        categoryPills.forEach { addSubview($0) }
        updatePills()
    }

    /// 分类胶囊附带服务端数量；旧服务器没有 /api/categories 时只显示名称。
    private func updatePills() {
        for (i, b) in categoryPills.enumerated() {
            let c = StoreCategory.selectable[i]
            let suffix = categoryCounts[c].map { " \($0)" } ?? ""
            b.title = c.label + suffix
            let on = c == selectedCategory
            b.layer?.backgroundColor = (on ? StorePalette.accent : StorePalette.surface).cgColor
            b.contentTintColor = on ? .white : StorePalette.muted
            b.layer?.borderWidth = on ? 0 : 1
            b.layer?.borderColor = StorePalette.line.cgColor
        }
    }

    func refreshCategories() {
        StoreClient.categories { [weak self] counts in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.categoryCounts = counts
                self.updatePills()
            }
        }
    }

    @objc private func pillClicked(_ sender: NSButton) {
        guard sender.tag >= 0, sender.tag < StoreCategory.selectable.count else { return }
        selectedCategory = StoreCategory.selectable[sender.tag]
        updatePills()
        load()
    }

    @objc private func searchChanged() {
        query = searchF.stringValue.trimmingCharacters(in: .whitespaces).lowercased()
        renderGrid()
    }

    private func renderGrid() {
        let list = themes.filter { t in
            if query.isEmpty { return true }
            return t.name.lowercased().contains(query)
                || t.author.lowercased().contains(query)
                || t.tags.joined(separator: " ").lowercased().contains(query)
        }
        grid.tiles = list.map { t in
            let tile = StoreCardTile()
            tile.configure(t, image: downloaded[t.id]?.backgroundImage,
                           downloaded: downloaded[t.id] != nil)
            tile.onSelect = { [weak self] in self?.select(t) }
            tile.onAuthor = { [weak self] in
                let key = t.authorLogin ?? t.author
                if !key.isEmpty { self?.openProfile(key) }
            }
            return tile
        }
        let gridW = grid.frame.width > 20 ? grid.frame.width : 340
        let h = grid.arrange(width: gridW)
        grid.frame = NSRect(x: 0, y: 0, width: gridW, height: h)
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
                    self.renderGrid()
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

    func selectTheme(_ t: StoreTheme) { select(t) }

    private func select(_ t: StoreTheme) {
        selected = t
        detail.theme = t
        detail.localTheme = downloaded[t.id]
        detail.downloadBtn.action = #selector(downloadSelected)
        detail.downloadBtn.target = self
        detail.applyBtn.action = #selector(applySelected)
        detail.applyBtn.target = self
        // 同分类推荐（最多 6 个），点击复用同一个 select 流程
        let same = themes.filter { $0.id != t.id && $0.categoryKind == t.categoryKind }.prefix(6)
        detail.setRelated(Array(same))
        detail.onPickRelated = { [weak self] picked in self?.select(picked) }
        detail.onAuthor = { [weak self] in
            let key = t.authorLogin ?? t.author
            if !key.isEmpty { self?.openProfile(key) }
        }
        detail.onDownloadVersion = { [weak self] v in self?.downloadVersion(t, version: v) }
        detail.onUploadVersion = { [weak self] in self?.openVersionUpload(t) }
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

    /// 下载指定历史版本，后续导入流程与默认下载完全一致。
    private func downloadVersion(_ t: StoreTheme, version: String) {
        setBusy(true, "正在下载「\(t.name)」v\(version)…")
        detail.downloadBtn.isEnabled = false
        StoreClient.download(t, version: version) { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.setBusy(false)
                self.detail.downloadBtn.isEnabled = true
                switch result {
                case .success(let r): self.finishDownload(t, result: r)
                case .failure(let err): self.status.stringValue = "下载失败：\(err.localizedDescription)"
                }
            }
        }
    }

    func openVersionUpload(_ t: StoreTheme) { controller?.openVersionUpload(t) }

    private func finishDownload(_ t: StoreTheme, result: StoreDownloadResult) {
        // EFI 配置包不进主题库：直接交给主窗口，按用户所选的 EFI 分区安装。
        if t.categoryKind == .efi {
            guard case .remote(let zip) = result else {
                status.stringValue = "EFI 配置包没有可安装的 zip"
                detail.hint.stringValue = "请重新下载该配置包。"
                return
            }
            status.stringValue = "已下载 EFI 配置包，请在主窗口确认写入所选 EFI 分区。"
            detail.hint.stringValue = "写入前会自动备份 Resources 与 config.plist。"
            downloaded[t.id] = nil
            detail.localTheme = nil
            renderGrid()
            AppDelegate.shared?.installEFIConfigPackage(zip)
            self.window?.orderOut(nil)
            return
        }
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
            renderGrid()
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

    // MARK: 账号入口

    @objc func openAccount() { controller?.openAccount() }

    @objc func openOwnProfile() {
        guard let u = StoreClient.currentUser, !u.loginName.isEmpty else {
            openAccount()
            return
        }
        openProfile(u.loginName)
    }

    func openProfile(_ login: String) { controller?.openProfile(login: login) }

    /// 登录态变化后刷新顶栏头像/昵称，并重绘卡片上的作者头像。
    func updateUserUI() {
        if let u = StoreClient.currentUser, !u.displayName.isEmpty {
            userNameBtn.title = u.displayName + (u.isAdmin == true ? "（管理员）" : "")
            setAvatarButton(userAvatarBtn, name: u.displayName, path: u.avatar, size: 26)
        } else {
            userNameBtn.title = "登录 / 注册"
            setAvatarButton(userAvatarBtn, name: "?", path: nil, size: 26)
        }
        renderGrid()
        if let t = selected { detail.theme = t }   // 刷新版本区上传入口的可见性
    }

    func applyVersionUpdate(_ t: StoreTheme) {
        if let i = themes.firstIndex(where: { $0.id == t.id }) { themes[i] = t }
        if selected?.id == t.id {
            selected = t
            detail.theme = t
        }
        renderGrid()
        status.stringValue = "已上传新版本 v\(t.latestVersion ?? "")"
    }

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
        titleF.frame = NSRect(x: pad, y: 10, width: 200, height: 22)
        subF.frame = NSRect(x: pad + 130, y: 13, width: bounds.width - pad * 2 - 360, height: 16)
        let toolbarY: CGFloat = 38
        let tfW: CGFloat = bounds.width - pad * 2 - 200
        addrField.frame = NSRect(x: pad, y: toolbarY, width: max(160, tfW), height: 26)
        refreshBtn.frame = NSRect(x: bounds.width - pad - 188, y: toolbarY, width: 90, height: 26)
        uploadBtn.frame = NSRect(x: bounds.width - pad - 90, y: toolbarY, width: 90, height: 26)
        userAvatarBtn.frame = NSRect(x: bounds.width - pad - 172, y: 8, width: 26, height: 26)
        userNameBtn.frame = NSRect(x: bounds.width - pad - 140, y: 8, width: 140, height: 26)
        let searchY = toolbarY + 32
        searchF.frame = NSRect(x: pad, y: searchY, width: 240, height: 26)
        let pillY = searchY + 34
        var px = pad
        for b in categoryPills {
            let w = b.title.size(withAttributes: [.font: b.font!]).width + 34
            b.frame = NSRect(x: px, y: pillY, width: w, height: 24)
            px += w + 8
        }
        let top = pillY + 32
        let leftW: CGFloat = max(340, bounds.width * 0.56)
        listScroll.frame = NSRect(x: pad, y: top, width: leftW,
                                  height: bounds.height - top - 28)
        let gridW = leftW - 14
        let gridH = grid.arrange(width: gridW)
        grid.frame = NSRect(x: 0, y: 0, width: gridW, height: gridH)
        detail.frame = NSRect(x: pad + leftW + 10, y: top,
                              width: bounds.width - pad * 2 - leftW - 10,
                              height: bounds.height - top - 28)
        spinner.frame = NSRect(x: pad, y: 6, width: 16, height: 16)
        status.frame = NSRect(x: pad + 22, y: 6, width: bounds.width - pad * 2 - 22, height: 16)
    }
}

final class StoreWindowController: NSWindowController {
    private var view: StoreView { window!.contentView as! StoreView }
    private var upload: StoreUploadWindowController?
    private var account: StoreAccountWindowController?
    private var profileEdit: StoreProfileEditWindowController?
    private var userProfile: StoreUserProfileWindowController?
    private var versionUpload: StoreVersionUploadWindowController?
    private var configured = false

    convenience init() {
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1120, height: 720),
                         styleMask: [.titled, .closable, .miniaturizable, .resizable],
                         backing: .buffered, defer: false)
        w.title = "主题商店"
        w.minSize = NSSize(width: 880, height: 620)
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
        v.refreshBtn.target = v; v.refreshBtn.action = #selector(StoreView.refresh)
        v.uploadBtn.target = v; v.uploadBtn.action = #selector(StoreView.openUpload)
        v.userNameBtn.target = v; v.userNameBtn.action = #selector(StoreView.openAccount)
        v.onApplyTheme = { [weak self] theme in
            self?.applyTheme(theme)
        }
        v.refreshCategories()
        v.load()
        if !StoreClient.userToken.isEmpty {
            StoreClient.session { [weak self] _ in
                DispatchQueue.main.async { self?.view.updateUserUI() }
            }
        }
    }

    override func windowDidLoad() {
        super.windowDidLoad()
        configure()
    }

    // MARK: 账号 / 用户主页窗口

    func openAccount() {
        let a = StoreAccountWindowController()
        a.onDone = { [weak self] in
            self?.view.updateUserUI()
            self?.account = nil
        }
        account = a
        a.showWindow(nil)
    }

    func openProfile(login: String) {
        guard !login.isEmpty else { return }
        let p = StoreUserProfileWindowController(login: login)
        p.onPickTheme = { [weak self] t in
            guard let self = self else { return }
            self.window?.makeKeyAndOrderFront(nil)
            self.view.selectTheme(t)
            p.window?.orderOut(nil)
            self.userProfile = nil
        }
        p.onEdit = { [weak self] in
            p.window?.orderOut(nil)
            self?.userProfile = nil
            self?.openProfileEdit()
        }
        userProfile = p
        p.showWindow(nil)
    }

    func openProfileEdit() {
        let e = StoreProfileEditWindowController()
        e.onDone = { [weak self] in
            self?.view.updateUserUI()
            self?.profileEdit = nil
        }
        profileEdit = e
        e.showWindow(nil)
    }

    func openVersionUpload(_ t: StoreTheme) {
        let c = StoreVersionUploadWindowController(theme: t)
        c.onDone = { [weak self] updated in
            self?.view.applyVersionUpdate(updated)
            self?.versionUpload = nil
        }
        versionUpload = c
        c.showWindow(nil)
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
        u.generateEFIPackage = {
            guard let app = AppDelegate.shared else {
                return .failure(StoreError.message("主窗口未就绪，请重新打开上传面板"))
            }
            do {
                return .success(try app.exportEFIConfigPackageForStore())
            } catch {
                return .failure(error)
            }
        }
        upload = u   // 强引用：否则 sheet 控制器在函数返回后就被释放，回调失效
        u.showSheet(on: w)
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
    /// 从主窗口当前选中的 EFI 分区生成脱敏配置包，返回临时 zip。
    var onGenerateEFI: (() -> Result<URL, Error>)?
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
        case .efi:
            categoryHint.stringValue = "EFI 配置包：从右侧已挂载的 EFI 分区生成，只含 Resources 与脱敏后的 PickerVariant；不会上传序列号 / MLB / ROM / NVRAM。"
        case .all:
            categoryHint.stringValue = ""
        }
        pkgBtn.title = selectedCategory == .efi
            ? "从当前 EFI 分区生成…"
            : "选择资源包（ZIP 或本机主题）…"
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

    /// 从主题库直接上传时预填：名称、简介、已打包的资源与生成的预览图。
    func prefill(name: String, description: String, package: URL?, previews: [URL]) {
        nameF.stringValue = name
        descField.string = description
        if let p = package {
            self.package = p
            pkgLabel.stringValue = p.lastPathComponent
            pkgLabel.textColor = .labelColor
        }
        if !previews.isEmpty {
            self.previews = previews
            prevLabel.stringValue = "已选 \(previews.count) 张（自动生成，可更换）"
            prevLabel.textColor = .labelColor
        }
    }

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
        // 切换类型后旧包可能不再适用（尤其 EFI 包与普通主题包结构不同）。
        package = nil
        pkgLabel.stringValue = "未选择"
        pkgLabel.textColor = .secondaryLabelColor
        status.stringValue = ""
        updateCategoryHint()
    }

    @objc private func choosePkg() {
        if selectedCategory == .efi {
            guard let gen = onGenerateEFI else {
                status.stringValue = "生成功能未就绪，请从主窗口重新打开上传面板"
                return
            }
            status.stringValue = "正在从所选 EFI 分区读取并生成脱敏配置包…"
            switch gen() {
            case .success(let u):
                package = u
                pkgLabel.stringValue = u.lastPathComponent
                pkgLabel.textColor = .labelColor
                status.stringValue = "已生成 EFI 配置包（不含机器标识）"
            case .failure(let e):
                status.stringValue = "生成失败：\(e.localizedDescription)"
            }
            return
        }
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
        if spec.package == nil {
            status.stringValue = selectedCategory == .efi
                ? "请先从当前 EFI 分区生成配置包" : "请先选择资源包"
            return
        }
        if let p = spec.package,
           let attr = try? FileManager.default.attributesOfItem(atPath: p.path),
           let n = attr[.size] as? NSNumber,
           n.doubleValue > 200 * 1024 * 1024 {
            status.stringValue = "资源包超过 200 MB 上限，请精简后重试"
            return
        }
        status.stringValue = "正在上传…"
        onUpload?(spec)
    }

    @objc private func doCancel() { onCancel?() }
}

final class StoreUploadWindowController: NSWindowController {
    var onSubmitted: (() -> Void)?
    var onCancel: (() -> Void)?
    /// 从主窗口当前 EFI 分区生成脱敏配置包（返回临时 zip）。
    var generateEFIPackage: (() -> Result<URL, Error>)?
    private var view: StoreUploadView { window!.contentView as! StoreUploadView }

    /// 主题库「上传到商店」入口：打开面板前预填名称 / 简介 / 资源包 / 预览图。
    func applyPrefill(name: String, description: String,
                      package: URL?, previews: [URL]) {
        view.prefill(name: name, description: description,
                     package: package, previews: previews)
    }

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
        view.onGenerateEFI = generateEFIPackage
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
