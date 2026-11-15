import AppKit
import ImageIO

// MARK: - Model
//
// The asset library is a browsable pool of wallpapers, UI chrome and boot
// icons. Bundled assets live in the read-only app bundle; user imports live in
// ~/Library/Application Support/OCThemeStudio/Assets. Choosing an asset does
// not write into the theme directly — the caller stages it under the correct
// file name (Background.png / Selected.png / …) and goes through the normal
// addThemeAssets / replaceThemeAsset path so buildManifest() classifies it.

enum AssetCategory: String {
    case wallpaper = "壁纸"
    case ui = "界面元素"
    case icon = "图标"
}

/// How a chosen asset should be used inside a theme. The stem is significant:
/// buildManifest() classifies resources purely by file name, so unique roles
/// must be written under their canonical names.
enum AssetRole: String, CaseIterable {
    case auto = "自动识别"
    case background = "背景壁纸"
    case selected = "选中框"
    case cursor = "光标"
    case ui = "界面元素"
    case icon = "启动项图标"

    var stem: String? {
        switch self {
        case .background: return "Background"
        case .selected: return "Selected"
        case .cursor: return "Cursor"
        default: return nil
        }
    }

    /// UI roles are single-instance files; always write them as PNG so an
    /// .icns picked as a wallpaper never ends up as Background.icns.
    var forcePNG: Bool {
        switch self {
        case .background, .selected, .cursor, .ui: return true
        default: return false
        }
    }

    func resolved(for item: AssetItem) -> AssetRole {
        guard self == .auto else { return self }
        switch item.category {
        case .wallpaper: return .background
        case .ui:
            let n = item.name.lowercased()
            if n.contains("cursor") || n.contains("pointer") { return .cursor }
            if n.contains("select") || n.contains("selector") { return .selected }
            return .ui
        case .icon: return .icon
        }
    }
}

struct AssetItem: Equatable {
    let url: URL
    let fileName: String
    let name: String
    let category: AssetCategory
    let isCustom: Bool
    let dims: String
    let sizeText: String

    static func == (a: AssetItem, b: AssetItem) -> Bool { a.url == b.url }
}

enum AssetLibraryMode {
    case browse
    case add(AssetRole)
    case replace(String, AssetRole)

    var isPick: Bool {
        switch self { case .browse: return false; default: return true }
    }
    var defaultRole: AssetRole {
        switch self {
        case .browse: return .auto
        case .add(let r), .replace(_, let r): return r
        }
    }
    var replaceTarget: String? {
        switch self { case .replace(let r, _): return r; default: return nil }
    }
}

// MARK: - Store

enum AssetLibraryStore {
    static let imageExt: Set<String> = [
        "png", "icns", "jpg", "jpeg", "webp", "bmp", "tif", "tiff", "gif", "heic",
    ]

    /// Wallpaper is checked first, then the exact same keyword set
    /// buildManifest() uses for uiAssets — so a file shown as「界面元素」in the
    /// library really lands in the theme's uiAssets bucket.
    private static func classify(_ stem: String, hint: String = "") -> AssetCategory {
        let low = stem.lowercased()
        let h = hint.lowercased()
        if low.contains("background") || low.contains("wallpaper") || low.contains("backdrop")
            || low == "bg"
            || h.contains("wallpaper") || h.contains("壁纸") || h.contains("背景") {
            return .wallpaper
        }
        if isUIAssetName(stem)
            || h == "ui" || h == "界面" || h.contains("界面元素") {
            return .ui
        }
        return .icon
    }

    private static func dimensionText(_ url: URL) -> String {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any],
              let w = props[kCGImagePropertyPixelWidth] as? Int,
              let h = props[kCGImagePropertyPixelHeight] as? Int, w > 0, h > 0 else {
            if let img = NSImage(contentsOf: url) {
                for rep in img.representations where rep.pixelsWide > 0 {
                    return "\(rep.pixelsWide)×\(rep.pixelsHigh)"
                }
            }
            return ""
        }
        return "\(w)×\(h)"
    }

    private static func makeItem(_ url: URL, isCustom: Bool, hint: String) -> AssetItem? {
        let leaf = url.lastPathComponent
        guard !leaf.hasPrefix("."), !leaf.hasPrefix("._"),
              imageExt.contains(url.pathExtension.lowercased()) else { return nil }
        let stem = (leaf as NSString).deletingPathExtension
        return AssetItem(url: url, fileName: leaf, name: stem,
                         category: classify(stem, hint: hint),
                         isCustom: isCustom,
                         dims: dimensionText(url),
                         sizeText: humanSize(fileSize(url)))
    }

    /// Bundled pool + user imports. Built-in entries come first so the grid
    /// always has content even on a fresh install with an empty Assets folder.
    static func scan() -> [AssetItem] {
        let fm = FileManager.default
        var out: [AssetItem] = []
        var seen = Set<String>()

        func addFlat(_ dir: URL?, hint: String, custom: Bool) {
            guard let d = dir, fm.fileExists(atPath: d.path),
                  let items = try? fm.contentsOfDirectory(
                    at: d, includingPropertiesForKeys: nil,
                    options: [.skipsHiddenFiles]) else { return }
            for u in items {
                guard let it = makeItem(u, isCustom: custom, hint: hint),
                      seen.insert(u.standardizedFileURL.path).inserted else { continue }
                out.append(it)
            }
        }

        let root = ThemePreset.root
        addFlat(root?.appendingPathComponent("wallpapers", isDirectory: true),
                hint: "wallpaper", custom: false)
        addFlat(root?.appendingPathComponent("icons", isDirectory: true),
                hint: "", custom: false)
        addFlat(root?.appendingPathComponent("defaults", isDirectory: true),
                hint: "ui", custom: false)

        // User imports: recurse so people can organise Assets/Wallpapers etc.
        try? fm.createDirectory(at: Paths.assets, withIntermediateDirectories: true)
        if let e = fm.enumerator(at: Paths.assets, includingPropertiesForKeys: [.isDirectoryKey],
                                 options: [.skipsHiddenFiles]) {
            for case let u as URL in e {
                var d: ObjCBool = false
                guard fm.fileExists(atPath: u.path, isDirectory: &d), !d.boolValue else { continue }
                let folder = u.deletingLastPathComponent().lastPathComponent
                let hint = folder == Paths.assets.lastPathComponent ? "" : folder
                guard let it = makeItem(u, isCustom: true, hint: hint),
                      seen.insert(u.standardizedFileURL.path).inserted else { continue }
                out.append(it)
            }
        }

        let order: [AssetCategory: Int] = [.wallpaper: 0, .ui: 1, .icon: 2]
        return out.sorted { a, b in
            if a.isCustom != b.isCustom { return !a.isCustom }
            let oa = order[a.category] ?? 9, ob = order[b.category] ?? 9
            if oa != ob { return oa < ob }
            return a.name.lowercased() < b.name.lowercased()
        }
    }

    /// Copy chosen files into the user's Assets folder (never the bundle).
    @discardableResult
    static func importFiles(_ urls: [URL]) throws -> Int {
        let fm = FileManager.default
        try fm.createDirectory(at: Paths.assets, withIntermediateDirectories: true)
        var candidates: [URL] = []
        for u in urls {
            var d: ObjCBool = false
            guard fm.fileExists(atPath: u.path, isDirectory: &d) else { continue }
            if d.boolValue {
                guard let e = fm.enumerator(at: u, includingPropertiesForKeys: [.isDirectoryKey],
                                            options: [.skipsHiddenFiles]) else { continue }
                for case let f as URL in e {
                    var fd: ObjCBool = false
                    guard fm.fileExists(atPath: f.path, isDirectory: &fd), !fd.boolValue else { continue }
                    candidates.append(f)
                }
            } else {
                candidates.append(u)
            }
        }
        var n = 0
        for src in candidates where imageExt.contains(src.pathExtension.lowercased()) {
            let leaf = src.lastPathComponent
            guard !leaf.hasPrefix(".") else { continue }
            var dst = Paths.assets.appendingPathComponent(leaf)
            var i = 2
            let stem = src.deletingPathExtension().lastPathComponent
            let ext = src.pathExtension
            while fm.fileExists(atPath: dst.path) {
                dst = Paths.assets.appendingPathComponent("\(stem) \(i).\(ext)")
                i += 1
            }
            try fm.copyItem(at: src, to: dst)
            n += 1
        }
        return n
    }

    static func remove(_ item: AssetItem) throws {
        guard item.isCustom else { throw AppError.message("内置素材不能删除") }
        try FileManager.default.removeItem(at: item.url)
    }

    static func thumbnail(_ url: URL, maxPx: Int = 220) -> NSImage? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            return NSImage(contentsOf: url)
        }
        let opts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPx,
            kCGImageSourceCreateThumbnailWithTransform: true,
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary) else {
            return NSImage(contentsOf: url)
        }
        return NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
    }

    static func fullImage(_ url: URL) -> NSImage? { NSImage(contentsOf: url) }

    /// Highest-resolution PNG representation of any image we can read.
    private static func pngData(_ url: URL) throws -> Data {
        guard let img = NSImage(contentsOf: url) else {
            throw AppError.message("无法读取素材图片：\(url.lastPathComponent)")
        }
        var best: NSBitmapImageRep?
        for rep in img.representations {
            guard let b = rep as? NSBitmapImageRep else { continue }
            if best == nil || b.pixelsWide * b.pixelsHigh > best!.pixelsWide * best!.pixelsHigh {
                best = b
            }
        }
        let fallback = img.tiffRepresentation.flatMap { NSBitmapImageRep(data: $0) }
        guard let rep = best ?? fallback,
              let data = rep.representation(using: .png, properties: [:]) else {
            throw AppError.message("无法转换素材图片：\(url.lastPathComponent)")
        }
        return data
    }

    /// Preferred extension when adding an asset under `role`.
    static func preferredExt(_ item: AssetItem, role: AssetRole) -> String {
        role.forcePNG ? "png"
            : (item.url.pathExtension.isEmpty ? "png" : item.url.pathExtension)
    }

    /// Stage the asset in scratch under its destination file name. The caller
    /// passes this URL to addThemeAssets / replaceThemeAsset and then removes
    /// the scratch directory. Whenever the source format differs from the
    /// requested extension the bitmap is converted to a real PNG, so a file
    /// never ends up with a misleading extension.
    static func stage(_ item: AssetItem, destStem: String,
                      preferredExt: String) throws -> URL {
        let fm = FileManager.default
        let dir = Paths.scratch.appendingPathComponent("asset-\(UUID().uuidString)",
                                                      isDirectory: true)
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        let srcExt = item.url.pathExtension.lowercased()
        let want = preferredExt.lowercased().isEmpty ? "png" : preferredExt.lowercased()
        let ext = (srcExt == want || (srcExt.isEmpty && want == "png")) ? want : "png"
        let dst = dir.appendingPathComponent("\(destStem).\(ext)")
        if ext == "png" && srcExt != "png" {
            try pngData(item.url).write(to: dst)
        } else {
            try fm.copyItem(at: item.url, to: dst)
        }
        return dst
    }
}

// MARK: - Grid cell

final class FlippedContainer: NSView {
    override var isFlipped: Bool { true }
}

private let assetCellID = NSUserInterfaceItemIdentifier("AssetGridCell")

private final class AssetCellContainer: NSView {
    override var isFlipped: Bool { true }
    let img = NSImageView()
    let nameF = UI.label("", size: 10.5, weight: .medium, align: .center)
    let kindF = UI.label("", size: 9, color: .secondaryLabelColor, align: .center)
    let customF = UI.label("自定义", size: 8.5, weight: .semibold,
                           color: .controlAccentColor, align: .center)

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 7
        img.imageScaling = .scaleProportionallyUpOrDown
        img.imageAlignment = .alignCenter
        img.wantsLayer = true
        img.layer?.cornerRadius = 4
        img.layer?.masksToBounds = true
        nameF.lineBreakMode = .byTruncatingMiddle
        kindF.lineBreakMode = .byTruncatingTail
        customF.wantsLayer = true
        customF.layer?.cornerRadius = 3
        customF.layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.15).cgColor
        for v in [img, nameF, kindF, customF] as [NSView] { addSubview(v) }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) unsupported") }

    func setSelected(_ on: Bool) {
        layer?.backgroundColor = on
            ? NSColor.controlAccentColor.withAlphaComponent(0.20).cgColor
            : NSColor.controlBackgroundColor.withAlphaComponent(0.75).cgColor
        layer?.borderColor = on
            ? NSColor.controlAccentColor.cgColor
            : NSColor.separatorColor.withAlphaComponent(0.6).cgColor
        layer?.borderWidth = on ? 2 : 1
    }

    override func layout() {
        super.layout()
        let w = bounds.width
        img.frame = NSRect(x: 8, y: 8, width: w - 16, height: bounds.height - 48)
        nameF.frame = NSRect(x: 4, y: bounds.height - 38, width: w - 8, height: 15)
        kindF.frame = NSRect(x: 4, y: bounds.height - 22, width: w - 8, height: 13)
        customF.frame = NSRect(x: w - 48, y: 10, width: 40, height: 13)
    }
}

private final class AssetGridCell: NSCollectionViewItem {
    private var container: AssetCellContainer? { view as? AssetCellContainer }

    override func loadView() {
        view = AssetCellContainer(frame: .zero)
    }

    override var isSelected: Bool {
        didSet { container?.setSelected(isSelected) }
    }

    func configure(_ item: AssetItem, thumb: NSImage?, selected: Bool) {
        guard let c = container else { return }
        c.img.image = thumb
        c.nameF.stringValue = item.name
        c.kindF.stringValue = item.category.rawValue +
            (item.dims.isEmpty ? "" : " · " + item.dims)
        c.customF.isHidden = !item.isCustom
        c.setSelected(selected)
        c.needsLayout = true
    }
}

// MARK: - Root view

final class AssetLibraryRootView: NSView {
    override var isFlipped: Bool { true }
    /// Browse mode only needs one bottom button ("关闭").
    var singleButton = false

    let searchField = UI.field("搜索素材名称…")
    let categoryCtrl = NSSegmentedControl(
        labels: ["全部", "壁纸", "界面元素", "图标", "自定义"],
        trackingMode: .selectOne, target: nil, action: nil)
    let importBtn = UI.button("＋ 导入素材…", height: 26)
    let folderBtn = UI.button("打开素材文件夹", height: 26)
    let removeBtn = UI.button("移出素材库", height: 26)
    let topLine = UI.hLine()

    let gridScroll = NSScrollView()
    let grid: NSCollectionView

    let detailBox = NSBox()
    let detailContent = FlippedContainer()
    let previewImage = NSImageView()
    let previewEmpty = UI.label("选择一张素材以预览", size: 11.5,
                                color: .secondaryLabelColor, align: .center)
    let detailName = UI.label("", size: 13, weight: .semibold, align: .center)
    let detailInfo = UI.label("", size: 10.5, color: .secondaryLabelColor, align: .center)
    let roleTitle = UI.label("写入主题时用作", size: 10.5, color: .secondaryLabelColor)
    let rolePopup = NSPopUpButton()
    let roleNote = UI.label("", size: 10, color: .secondaryLabelColor)

    let bottomLine = UI.hLine()
    let statusF = UI.label("", size: 10.5, color: .secondaryLabelColor)
    let cancelBtn = UI.button("取消", height: 28)
    let applyBtn = UI.button("应用到主题", height: 28, accent: true)

    override init(frame frameRect: NSRect) {
        let layout = NSCollectionViewFlowLayout()
        layout.itemSize = NSSize(width: 134, height: 126)
        layout.sectionInset = NSEdgeInsets(top: 10, left: 10, bottom: 10, right: 10)
        layout.minimumLineSpacing = 10
        layout.minimumInteritemSpacing = 8
        grid = NSCollectionView()
        grid.collectionViewLayout = layout
        super.init(frame: frameRect)

        grid.isSelectable = true
        grid.allowsMultipleSelection = false
        grid.backgroundColors = [.clear]
        grid.register(AssetGridCell.self, forItemWithIdentifier: assetCellID)
        gridScroll.documentView = grid
        gridScroll.drawsBackground = false
        gridScroll.hasVerticalScroller = true
        gridScroll.wantsLayer = true
        gridScroll.layer?.cornerRadius = 8

        detailBox.boxType = .custom
        detailBox.fillColor = .controlBackgroundColor
        detailBox.borderColor = .separatorColor
        detailBox.borderWidth = 1
        detailBox.cornerRadius = 8
        detailBox.titlePosition = .noTitle
        previewImage.imageScaling = .scaleProportionallyUpOrDown
        previewImage.imageAlignment = .alignCenter
        previewImage.wantsLayer = true
        previewImage.layer?.cornerRadius = 6
        previewImage.layer?.masksToBounds = true
        detailInfo.lineBreakMode = .byWordWrapping
        detailInfo.maximumNumberOfLines = 3
        roleNote.lineBreakMode = .byWordWrapping
        roleNote.maximumNumberOfLines = 4
        roleNote.stringValue = """
        按用途自动命名写入主题（如 Background.png、Selected.png），\
        并同步更新安装清单。内置素材不会被修改。
        """
        categoryCtrl.selectedSegment = 0
        categoryCtrl.segmentStyle = .texturedRounded
        detailBox.addSubview(detailContent)
        for v in [previewImage, previewEmpty, detailName, detailInfo,
                  roleTitle, rolePopup, roleNote, removeBtn] as [NSView] {
            detailContent.addSubview(v)
        }

        for v in [searchField, categoryCtrl, importBtn, folderBtn,
                  topLine, gridScroll, detailBox, bottomLine, statusF,
                  cancelBtn, applyBtn] as [NSView] { addSubview(v) }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) unsupported") }

    override func layout() {
        super.layout()
        let pad: CGFloat = 16
        let w = bounds.width - pad * 2
        // .fullSizeContentView windows put their content under the title bar,
        // so keep the toolbar below the ~28pt title-bar strip.
        let top: CGFloat = 30
        let toolY = top + 10
        searchField.frame = NSRect(x: pad, y: toolY, width: 200, height: 24)
        categoryCtrl.frame = NSRect(x: pad + 208, y: toolY, width: 300, height: 25)
        folderBtn.frame = NSRect(x: bounds.width - pad - 124, y: toolY,
                                 width: 124, height: 26)
        importBtn.frame = NSRect(x: folderBtn.frame.minX - 8 - 108, y: toolY,
                                 width: 108, height: 26)
        topLine.frame = NSRect(x: pad, y: top + 46, width: w, height: 1)

        let bodyTop = top + 56
        let bodyBottom = bounds.height - 62
        let bodyH = max(180, bodyBottom - bodyTop)
        let detailW: CGFloat = 250
        let gridW = w - detailW - 12
        gridScroll.frame = NSRect(x: pad, y: bodyTop, width: gridW, height: bodyH)
        detailBox.frame = NSRect(x: pad + gridW + 12, y: bodyTop,
                                 width: detailW, height: bodyH)
        detailContent.frame = detailBox.bounds

        let dp: CGFloat = 12
        let iw = detailContent.bounds.width - dp * 2
        previewImage.frame = NSRect(x: dp, y: dp, width: iw, height: 150)
        previewEmpty.frame = NSRect(x: dp, y: dp + 66, width: iw, height: 20)
        detailName.frame = NSRect(x: dp, y: dp + 158, width: iw, height: 19)
        detailInfo.frame = NSRect(x: dp, y: dp + 182, width: iw, height: 42)
        roleTitle.frame = NSRect(x: dp, y: dp + 230, width: iw, height: 15)
        rolePopup.frame = NSRect(x: dp, y: dp + 248, width: iw, height: 26)
        roleNote.frame = NSRect(x: dp, y: dp + 282, width: iw, height: 58)
        removeBtn.frame = NSRect(x: dp, y: dp + 348, width: iw, height: 26)

        bottomLine.frame = NSRect(x: pad, y: bounds.height - 54, width: w, height: 1)
        let by = bounds.height - 42
        applyBtn.isHidden = singleButton
        if singleButton {
            cancelBtn.frame = NSRect(x: bounds.width - pad - 92, y: by,
                                     width: 92, height: 28)
        } else {
            cancelBtn.frame = NSRect(x: bounds.width - pad - 176, y: by,
                                     width: 76, height: 28)
            applyBtn.frame = NSRect(x: bounds.width - pad - 92, y: by,
                                    width: 92, height: 28)
        }
        statusF.frame = NSRect(x: pad, y: by + 6,
                               width: max(60, cancelBtn.frame.minX - pad - 10), height: 16)
    }
}

// MARK: - Window controller

final class AssetLibraryWindowController: NSWindowController,
        NSCollectionViewDataSource, NSCollectionViewDelegate,
        NSTextFieldDelegate, NSWindowDelegate {

    private var mode: AssetLibraryMode = .browse
    var onChoose: ((AssetItem, AssetRole) -> Void)?
    var onClose: (() -> Void)?

    private var allItems: [AssetItem] = []
    private var filtered: [AssetItem] = []
    private var thumbs: [String: NSImage] = [:]
    private var selected: AssetItem?
    private var searchText = ""

    private var root: AssetLibraryRootView { window!.contentView as! AssetLibraryRootView }

    convenience init(mode: AssetLibraryMode = .browse) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 960, height: 640),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered, defer: false)
        window.title = "素材库 · 图标与壁纸"
        window.minSize = NSSize(width: 820, height: 560)
        window.center()
        window.setFrameAutosaveName("OCThemeStudioSwiftAssetLibrary")
        self.init(window: window)
        self.mode = mode
        let size = window.contentRect(forFrameRect: window.frame).size
        window.contentView = AssetLibraryRootView(frame: NSRect(origin: .zero, size: size))
        window.delegate = self
        setup()
    }

    private func setup() {
        let r = root
        switch mode {
        case .browse:
            window?.title = "素材库 · 图标与壁纸"
            r.singleButton = true
            r.roleTitle.isHidden = true
            r.rolePopup.isHidden = true
        case .add:
            window?.title = "从素材库添加资源"
            r.applyBtn.title = "添加到主题"
        case .replace(let rel, _):
            window?.title = "从素材库替换 · \((rel as NSString).lastPathComponent)"
            r.applyBtn.title = "替换该资源"
            r.roleTitle.isHidden = true
            r.rolePopup.isHidden = true
        }
        r.cancelBtn.title = mode.isPick ? "取消" : "关闭"
        r.needsLayout = true

        for role in AssetRole.allCases {
            r.rolePopup.addItem(withTitle: role.rawValue)
        }
        r.rolePopup.selectItem(withTitle: mode.defaultRole.rawValue)

        r.grid.dataSource = self
        r.grid.delegate = self
        r.searchField.delegate = self
        for (b, sel) in [(r.importBtn, #selector(importAssets)),
                         (r.folderBtn, #selector(revealAssetsFolder)),
                         (r.removeBtn, #selector(removeCustom)),
                         (r.cancelBtn, #selector(closeWindow)),
                         (r.applyBtn, #selector(applySelection))] as [(NSButton, Selector)] {
            b.target = self; b.action = sel
        }
        r.categoryCtrl.target = self
        r.categoryCtrl.action = #selector(categoryChanged)
        reload(selectURL: nil)
        updateDetail()
    }

    // MARK: Data

    private func reload(selectURL: URL?) {
        allItems = AssetLibraryStore.scan()
        applyFilter(selectURL: selectURL)
    }

    private func applyFilter(selectURL: URL?) {
        let seg = root.categoryCtrl.selectedSegment
        let q = searchText.lowercased()
        filtered = allItems.filter { item in
            if !q.isEmpty && !item.name.lowercased().contains(q)
                && !item.fileName.lowercased().contains(q) { return false }
            switch seg {
            case 1: return item.category == .wallpaper
            case 2: return item.category == .ui
            case 3: return item.category == .icon
            case 4: return item.isCustom
            default: return true
            }
        }
        root.grid.reloadData()
        let target = selectURL ?? selected?.url
        selected = target.flatMap { u in filtered.first { $0.url == u } }
        if let s = selected, let i = filtered.firstIndex(of: s) {
            root.grid.selectItems(at: [IndexPath(item: i, section: 0)],
                                  scrollPosition: .centeredVertically)
        }
        root.statusF.stringValue = "共 \(allItems.count) 项素材 · 当前显示 \(filtered.count) 项" +
            (mode.isPick ? " · 双击「应用到主题」写入当前主题" : "")
        updateDetail()
    }

    private func thumbnail(_ item: AssetItem) -> NSImage? {
        let key = item.url.path
        if let cached = thumbs[key] { return cached }
        let img = AssetLibraryStore.thumbnail(item.url)
        thumbs[key] = img
        return img
    }

    private func updateDetail() {
        let r = root
        guard let item = selected else {
            r.previewImage.image = nil
            r.previewImage.isHidden = true
            r.previewEmpty.isHidden = false
            r.previewEmpty.stringValue = "选择一张素材以预览"
            r.detailName.stringValue = "未选择素材"
            r.detailInfo.stringValue = ""
            r.removeBtn.isEnabled = false
            r.applyBtn.isEnabled = false
            return
        }
        r.previewImage.image = AssetLibraryStore.fullImage(item.url)
        r.previewImage.isHidden = r.previewImage.image == nil
        r.previewEmpty.isHidden = r.previewImage.image != nil
        r.detailName.stringValue = item.name
        r.detailInfo.stringValue = "\(item.category.rawValue) · \(item.isCustom ? "自定义" : "内置")\n" +
            (item.dims.isEmpty ? "" : item.dims + " · ") + item.sizeText + "\n" + item.fileName
        r.removeBtn.isEnabled = item.isCustom
        r.applyBtn.isEnabled = true
        r.rolePopup.isEnabled = true
        r.roleNote.stringValue = explainRole(for: item)
    }

    private func chosenRole() -> AssetRole {
        let raw = root.rolePopup.titleOfSelectedItem ?? AssetRole.auto.rawValue
        return AssetRole(rawValue: raw) ?? .auto
    }

    private func explainRole(for item: AssetItem) -> String {
        switch mode {
        case .browse:
            return "在主题编辑器里点「素材库」即可把选中的素材写入当前主题。"
        case .replace(let rel, _):
            return "将替换当前选中的资源 \((rel as NSString).lastPathComponent)，文件名保持不变，安装清单自动更新。"
        case .add:
            let role = chosenRole().resolved(for: item)
            if let stem = role.stem {
                return "将写入 \(stem).png；若主题已有同用途资源会被直接替换，不会生成重复文件。"
            }
            return "将保留素材名称写入主题，作为启动项图标使用，安装清单自动更新。"
        }
    }

    // MARK: Collection view

    func numberOfSections(in collectionView: NSCollectionView) -> Int { 1 }

    func collectionView(_ collectionView: NSCollectionView,
                        numberOfItemsInSection section: Int) -> Int { filtered.count }

    func collectionView(_ collectionView: NSCollectionView,
                        itemForRepresentedObjectAt indexPath: IndexPath) -> NSCollectionViewItem {
        let cell = collectionView.makeItem(withIdentifier: assetCellID,
                                           for: indexPath) as? AssetGridCell
            ?? AssetGridCell()
        let item = filtered[indexPath.item]
        cell.configure(item, thumb: thumbnail(item), selected: item == selected)
        return cell
    }

    func collectionView(_ collectionView: NSCollectionView,
                        didSelectItemsAt indexPaths: Set<IndexPath>) {
        guard let i = indexPaths.first?.item, i < filtered.count else { return }
        selected = filtered[i]
        updateDetail()
    }

    func collectionView(_ collectionView: NSCollectionView,
                        didDeselectItemsAt indexPaths: Set<IndexPath>) {
        // Selecting another item already updates the detail; keep the last
        // selection highlighted until then.
    }

    // MARK: Actions

    func controlTextDidChange(_ obj: Notification) {
        guard let f = obj.object as? NSTextField, f === root.searchField else { return }
        searchText = f.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        applyFilter(selectURL: selected?.url)
    }

    @objc private func categoryChanged() { applyFilter(selectURL: selected?.url) }

    @objc private func revealAssetsFolder() {
        NSWorkspace.shared.activateFileViewerSelecting([Paths.assets])
    }

    @objc private func importAssets() {
        let p = NSOpenPanel()
        p.message = "选择要加入素材库的图片，可多选文件或整个文件夹"
        p.canChooseFiles = true
        p.canChooseDirectories = true
        p.allowsMultipleSelection = true
        p.beginSheetModal(for: window!) { [weak self] resp in
            guard resp == .OK, let self = self else { return }
            do {
                let n = try AssetLibraryStore.importFiles(p.urls)
                self.thumbs.removeAll()
                self.reload(selectURL: nil)
                self.root.statusF.stringValue = n > 0
                    ? "已导入 \(n) 张素材到「\(Paths.assets.path)」"
                    : "没有找到可导入的图片（支持 png / icns / jpg / webp 等）"
            } catch {
                NSAlert(error: error).beginSheetModal(for: self.window!, completionHandler: nil)
            }
        }
    }

    @objc private func removeCustom() {
        guard let item = selected, item.isCustom else { return }
        let a = NSAlert()
        a.messageText = "移出素材库"
        a.informativeText = "「\(item.fileName)」将从素材库中移除（只删除应用素材文件夹里的副本，原文件不受影响）。"
        a.alertStyle = .warning
        a.addButton(withTitle: "移出")
        a.addButton(withTitle: "取消")
        a.beginSheetModal(for: window!) { [weak self] resp in
            guard resp == .alertFirstButtonReturn, let self = self else { return }
            do {
                try AssetLibraryStore.remove(item)
                self.thumbs.removeValue(forKey: item.url.path)
                self.selected = nil
                self.reload(selectURL: nil)
            } catch {
                NSAlert(error: error).beginSheetModal(for: self.window!, completionHandler: nil)
            }
        }
    }

    @objc private func applySelection() {
        guard mode.isPick else { window?.close(); return }
        guard let item = selected else { return }
        let role = chosenRole().resolved(for: item)
        onChoose?(item, role)
        window?.close()
    }

    @objc private func closeWindow() { window?.close() }

    func windowWillClose(_ notification: Notification) { onClose?() }

    /// Hook for the build validation harness.
    func debugSelect(_ index: Int) {
        guard index >= 0, index < filtered.count else { return }
        selected = filtered[index]
        root.grid.selectItems(at: [IndexPath(item: index, section: 0)],
                              scrollPosition: .centeredVertically)
        updateDetail()
    }
}
