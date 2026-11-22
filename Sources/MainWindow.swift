import AppKit

private let themeRowID = NSUserInterfaceItemIdentifier("ThemeRow")
private let efiRowID = NSUserInterfaceItemIdentifier("EFIRow")
private let backupRowID = NSUserInterfaceItemIdentifier("BackupRow")

// MARK: - Column views

final class ButtonRow: NSView {
    override var isFlipped: Bool { true }
    private let a: NSButton
    private let b: NSButton
    init(_ a: NSButton, _ b: NSButton) {
        self.a = a; self.b = b
        super.init(frame: .zero)
        addSubview(a); addSubview(b)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) unsupported") }
    override func layout() {
        super.layout()
        let w = (bounds.width - 8) / 2
        let h = bounds.height
        a.frame = NSRect(x: 0, y: 0, width: w, height: h)
        b.frame = NSRect(x: w + 8, y: 0, width: w, height: h)
    }
}

/// Evenly spaced row of 2-4 buttons.
final class ButtonRowN: NSView {
    override var isFlipped: Bool { true }
    private let buttons: [NSButton]
    init(_ buttons: [NSButton]) {
        self.buttons = buttons
        super.init(frame: .zero)
        for b in buttons { addSubview(b) }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) unsupported") }
    override func layout() {
        super.layout()
        guard !buttons.isEmpty else { return }
        let gap: CGFloat = 6
        let w = (bounds.width - gap * CGFloat(buttons.count - 1)) / CGFloat(buttons.count)
        for (i, b) in buttons.enumerated() {
            b.frame = NSRect(x: CGFloat(i) * (w + gap), y: 0,
                             width: w, height: bounds.height)
        }
    }
}

final class LibraryColumnView: NSView {
    override var isFlipped: Bool { true }
    let header = UI.section("主题库")
    let importBtn = UI.button("＋ 导入主题包", height: 28, accent: true)
    let deleteBtn = UI.button("－ 删除", height: 26)
    let editBtn = UI.button("✎ 编辑", height: 26)
    let newBtn = UI.button("＋ 新建", height: 26)
    let renameBtn = UI.button("✎ 重命名", height: 26)
    let repairBtn = UI.button("⟳ 修复目录", height: 26)
    let bootBtn = UI.button("识别启动项", height: 26)
    let icnsBtn = UI.button("⇄ 转 ICNS", height: 26)
    let storeBtn = UI.button("🛒 上传到商店", height: 26)
    let moreBtn = UI.button("⋯ 更多", height: 26)
    let aiBtn = UI.button("✨ AI 一键生成主题", height: 28)
    let scroll: NSScrollView
    let table: NSTableView
    let foot = UI.label("", size: 10.5, color: .secondaryLabelColor)
    private let dropOverlay = DropHintView()
    private lazy var buttonsRow: ButtonRowN = ButtonRowN([deleteBtn, editBtn, newBtn])
    private lazy var buttonsRow2: ButtonRowN = ButtonRowN([renameBtn, repairBtn, bootBtn])
    private lazy var buttonsRow3: ButtonRowN = ButtonRowN([icnsBtn, storeBtn])
    private lazy var buttonsRow4: ButtonRowN = ButtonRowN([moreBtn])

    override init(frame frameRect: NSRect) {
        let pair = makeTable(rowHeight: 62)
        scroll = pair.0; table = pair.1
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        dropOverlay.isHidden = true
        aiBtn.bezelColor = .controlAccentColor
        aiBtn.contentTintColor = .white
        aiBtn.font = .systemFont(ofSize: 12, weight: .semibold)
        for v in [header, importBtn, buttonsRow, buttonsRow2, buttonsRow3,
                  buttonsRow4, aiBtn, scroll, foot, dropOverlay] as [NSView] {
            addSubview(v)
        }
        foot.lineBreakMode = .byWordWrapping
        foot.maximumNumberOfLines = 3
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) unsupported") }

    func setDropHighlight(_ on: Bool) { dropOverlay.isHidden = !on }

    override func layout() {
        super.layout()
        let pad: CGFloat = 14
        let w = bounds.width - pad * 2
        header.frame = NSRect(x: pad, y: 14, width: w, height: 16)
        importBtn.frame = NSRect(x: pad, y: 36, width: w, height: 28)
        buttonsRow.frame = NSRect(x: pad, y: 68, width: w, height: 26)
        buttonsRow2.frame = NSRect(x: pad, y: 100, width: w, height: 26)
        buttonsRow3.frame = NSRect(x: pad, y: 132, width: w, height: 26)
        buttonsRow4.frame = NSRect(x: pad, y: 164, width: w, height: 26)
        aiBtn.frame = NSRect(x: pad, y: 196, width: w, height: 28)
        foot.frame = NSRect(x: pad, y: bounds.height - 66, width: w, height: 52)
        let tableTop: CGFloat = 232
        let tableBottom = bounds.height - 74
        scroll.frame = NSRect(x: pad - 2, y: tableTop, width: w + 4,
                              height: max(60, tableBottom - tableTop))
        dropOverlay.frame = bounds
    }
}

final class PreviewColumnView: NSView {
    override var isFlipped: Bool { true }
    let header = UI.section("BOOT PICKER 预览")
    let aspectCtrl = NSSegmentedControl(labels: ["16:9", "16:10", "4:3"],
                                        trackingMode: .selectOne,
                                        target: nil, action: nil)
    let labelsChk = UI.checkbox("显示标签", on: true)
    let selectChk = UI.checkbox("选中框", on: true)
    let designBtn = UI.button("✎ 可视化设计", height: 24)
    let picker = BootPickerView()
    let titleF = UI.label("", size: 15, weight: .semibold)
    let statsF = UI.label("", size: 11, color: .secondaryLabelColor)

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        for v in [header, aspectCtrl, labelsChk, selectChk, designBtn,
                  picker, titleF, statsF] as [NSView] {
            addSubview(v)
        }
        aspectCtrl.selectedSegment = 0
        aspectCtrl.segmentStyle = .rounded
        aspectCtrl.font = .systemFont(ofSize: 11)
        picker.wantsLayer = true
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) unsupported") }

    override func layout() {
        super.layout()
        let pad: CGFloat = 18
        let w = bounds.width - pad * 2
        titleF.frame = NSRect(x: pad, y: 12, width: w * 0.55, height: 22)
        header.frame = NSRect(x: pad, y: 36, width: w * 0.55, height: 14)
        aspectCtrl.frame = NSRect(x: bounds.width - pad - 168, y: 12, width: 168, height: 24)
        designBtn.frame = NSRect(x: bounds.width - pad - 168 - 8 - 118, y: 12,
                                 width: 118, height: 24)
        labelsChk.frame = NSRect(x: bounds.width - pad - 168, y: 39, width: 84, height: 20)
        selectChk.frame = NSRect(x: bounds.width - pad - 84, y: 39, width: 84, height: 20)
        statsF.frame = NSRect(x: pad, y: bounds.height - 28, width: w, height: 16)
        let top: CGFloat = 66
        picker.frame = NSRect(x: 8, y: top, width: bounds.width - 16,
                              height: max(120, bounds.height - top - 36))
    }
}

final class EFIColumnView: NSView {
    override var isFlipped: Bool { true }
    let form = FormScroll()

    let efiSection = UI.section("EFI 分区")
    let scanBtn = UI.button("重新扫描", height: 26)
    let efiScroll: NSScrollView
    let efiTable: NSTableView
    let mountBtn = UI.button("挂载")
    let unmountBtn = UI.button("卸载")
    let finderBtn = UI.button("在 Finder 打开")
    let loadCurrentBtn = UI.button("载入当前 OC 主题")

    let ocSection = UI.section("OpenCore 状态")
    let ocInfo = UI.label("", size: 11.5)

    let optSection = UI.section("应用选项")
    let replaceChk = UI.checkbox("清空目标变体目录（保留其他主题）", on: true)
    let pickerChk = UI.checkbox("启用 OpenCanopy（PickerMode = External）", on: true)
    let variantField = UI.field("PickerVariant（如 Acidanthera\\GoldenGate，留空自动）")
    let applyBtn = UI.button("应用主题到 EFI", height: 34, accent: true)
    let applyHint = UI.label("写入前自动备份 Resources 与 config.plist，可一键精确恢复。",
                             size: 10, color: .secondaryLabelColor)

    let backupSection = UI.section("备份 / 恢复")
    let backupScroll: NSScrollView
    let backupTable: NSTableView
    let backupHint = UI.label("暂无备份 · 应用主题后会自动生成",
                              size: 10, color: .secondaryLabelColor)
    let restoreBtn = UI.button("恢复选中备份", height: 28)

    override init(frame frameRect: NSRect) {
        let e = makeTable(rowHeight: 54); efiScroll = e.0; efiTable = e.1
        let b = makeTable(rowHeight: 40); backupScroll = b.0; backupTable = b.1
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        addSubview(form)

        ocInfo.lineBreakMode = .byWordWrapping
        ocInfo.maximumNumberOfLines = 8
        applyHint.lineBreakMode = .byWordWrapping
        applyHint.maximumNumberOfLines = 3

        let d = form.doc
        d.spacing = 8
        d.add(efiSection, height: 15)
        d.add(scanBtn, height: 26)
        // Keep scroll heights at exact multiples of the row height, otherwise the
        // last visible row's badge line is sliced in half at the clip boundary.
        d.add(efiScroll, height: 162)   // 3 x 54
        d.add(ButtonRow(mountBtn, unmountBtn), height: 28)
        d.add(ButtonRow(finderBtn, loadCurrentBtn), height: 28)
        d.add(UI.hLine(), height: 1)
        d.add(ocSection, height: 15)
        d.add(ocInfo, height: 152)
        d.add(UI.hLine(), height: 1)
        d.add(optSection, height: 15)
        d.add(replaceChk, height: 20)
        d.add(pickerChk, height: 20)
        d.add(variantField, height: 24)
        d.add(applyBtn, height: 34)
        d.add(applyHint, height: 28)
        d.add(UI.hLine(), height: 1)
        d.add(backupSection, height: 15)
        d.add(backupScroll, height: 120)  // 3 x 40
        d.add(backupHint, height: 16)
        d.add(restoreBtn, height: 28)
        d.add(UI.label("提示：写入 EFI 会弹出 macOS 管理员密码。", size: 10,
                       color: .secondaryLabelColor), height: 16)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) unsupported") }

    override func layout() {
        super.layout()
        form.frame = bounds
    }
}

final class StatusBarView: NSView {
    let status = UI.label("就绪", size: 11, color: .secondaryLabelColor)
    let spinner = NSProgressIndicator()
    let version = UI.label("OC Theme Studio · 原生 Swift 版", size: 10,
                           color: .tertiaryLabelColor)
    let helpBtn = UI.button("使用说明", height: 22)
    /// Always-visible entry points for the store and the boot simulator so they
    /// are not hidden behind a menu.
    let bootSimBtn = UI.button("▶ 模拟引导", height: 22)
    let storeBtn = UI.button("🛒 主题商店", height: 22)
    let assetsBtn = UI.button("🎨 素材库", height: 22)

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.isDisplayedWhenStopped = false
        for v in [status, spinner, version, helpBtn, bootSimBtn, storeBtn,
                  assetsBtn] as [NSView] {
            addSubview(v)
        }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) unsupported") }
    override func layout() {
        super.layout()
        let h = bounds.height
        let w = bounds.width
        spinner.frame = NSRect(x: 12, y: (h - 16) / 2, width: 16, height: 16)
        status.frame = NSRect(x: 34, y: (h - 16) / 2, width: w - 556, height: 16)
        // Right cluster: version · asset library · boot sim · store · help
        helpBtn.frame = NSRect(x: w - 92, y: (h - 22) / 2, width: 80, height: 22)
        storeBtn.frame = NSRect(x: w - 184, y: (h - 22) / 2, width: 84, height: 22)
        bootSimBtn.frame = NSRect(x: w - 284, y: (h - 22) / 2, width: 92, height: 22)
        assetsBtn.frame = NSRect(x: w - 376, y: (h - 22) / 2, width: 84, height: 22)
        version.frame = NSRect(x: w - 514, y: (h - 15) / 2, width: 130, height: 15)
    }
    func set(_ text: String, busy: Bool) {
        status.stringValue = text
        if busy { spinner.startAnimation(nil) } else { spinner.stopAnimation(nil) }
    }
}

final class RootView: NSView {
    let library = LibraryColumnView()
    let preview = PreviewColumnView()
    let efi = EFIColumnView()
    let statusBar = StatusBarView()
    private let dividerA = NSView()
    private let dividerB = NSView()
    /// Called with the accepted ZIP / folder URLs when the user drops files.
    var onDropFiles: (([URL]) -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        for v in [dividerA, dividerB] {
            v.wantsLayer = true
            v.layer?.backgroundColor = NSColor.separatorColor.cgColor
            addSubview(v)
        }
        for v in [library, preview, efi, statusBar] as [NSView] { addSubview(v) }
        // Accept drops anywhere in the window, not just on the small library column.
        registerForDraggedTypes(themeDragTypes)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) unsupported") }

    private func accepted(_ sender: NSDraggingInfo) -> [URL] {
        themeInstallDrops(draggedFileURLs(sender.draggingPasteboard))
    }
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard !accepted(sender).isEmpty else { return [] }
        library.setDropHighlight(true)
        return .copy
    }
    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        accepted(sender).isEmpty ? [] : .copy
    }
    override func draggingExited(_ sender: NSDraggingInfo?) { library.setDropHighlight(false) }
    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
        !accepted(sender).isEmpty
    }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        library.setDropHighlight(false)
        let urls = accepted(sender)
        guard !urls.isEmpty else { return false }
        onDropFiles?(urls)
        return true
    }
    override func concludeDragOperation(_ sender: NSDraggingInfo?) {
        library.setDropHighlight(false)
    }

    override func layout() {
        super.layout()
        let w = bounds.width, h = bounds.height
        let barH: CGFloat = 34
        let leftW: CGFloat = 262
        let rightW: CGFloat = min(330, max(290, w * 0.26))
        let bodyH = h - barH
        library.frame = NSRect(x: 0, y: barH, width: leftW, height: bodyH)
        preview.frame = NSRect(x: leftW, y: barH, width: w - leftW - rightW, height: bodyH)
        efi.frame = NSRect(x: w - rightW, y: barH, width: rightW, height: bodyH)
        dividerA.frame = NSRect(x: leftW, y: barH, width: 1, height: bodyH)
        dividerB.frame = NSRect(x: w - rightW, y: barH, width: 1, height: bodyH)
        statusBar.frame = NSRect(x: 0, y: 0, width: w, height: barH)
    }
}

// MARK: - Window controller

final class MainWindowController: NSWindowController, NSTableViewDataSource,
        NSTableViewDelegate, NSMenuDelegate {

    private var root: RootView { window!.contentView as! RootView }
    private var themes: [Theme] = []
    private var scanResult = EFIScanResult()
    private var backups: [BackupItem] = []
    private var selectedTheme: Theme?
    private var selectedPartition: EFIPartition?
    private var selectedBackup: BackupItem?
    private var autoVariant = ""
    private var busy = false
    private var editor: ThemeEditorWindowController?
    private var icnsWindow: ICNSWindowController?
    private var designWindow: DesignWindowController?
    private var bootWindow: BootScanWindowController?
    private var storeWindow: StoreWindowController?
    private var storeUpload: StoreUploadWindowController?
    private var bootSimWindow: BootSimWindowController?
    private var assetWindow: AssetLibraryWindowController?
    private var aiWindow: AIThemeWindowController?
    /// Row the context menu was opened on (‑1 = use the selected row).
    private var contextRow = -1

    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1320, height: 840),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered, defer: false)
        window.title = "OC Theme Studio"
        window.minSize = NSSize(width: 1080, height: 680)
        window.center()
        window.setFrameAutosaveName("OCThemeStudioSwiftMainWindow")
        self.init(window: window)
        let size = window.contentRect(forFrameRect: window.frame).size
        window.contentView = RootView(frame: NSRect(origin: .zero, size: size))
        setup()
    }

    private func setup() {
        Paths.ensure()
        ThemeLibrary.shared.reload()
        themes = ThemeLibrary.shared.themes

        let r = root
        r.library.table.dataSource = self
        r.library.table.delegate = self
        r.library.table.target = self
        r.library.table.action = #selector(themeTableClicked)
        r.efi.efiTable.dataSource = self
        r.efi.efiTable.delegate = self
        r.efi.efiTable.target = self
        r.efi.efiTable.action = #selector(efiTableClicked)
        r.efi.backupTable.dataSource = self
        r.efi.backupTable.delegate = self
        r.efi.backupTable.target = self
        r.efi.backupTable.action = #selector(backupTableClicked)

        r.library.importBtn.target = self
        r.library.importBtn.action = #selector(chooseZip)
        r.library.deleteBtn.target = self
        r.library.deleteBtn.action = #selector(removeSelectedTheme)
        r.library.editBtn.target = self
        r.library.editBtn.action = #selector(editSelectedTheme)
        r.library.newBtn.target = self
        r.library.newBtn.action = #selector(makeNewTheme)
        r.library.icnsBtn.target = self
        r.library.icnsBtn.action = #selector(convertImage)
        r.library.storeBtn.target = self
        r.library.storeBtn.action = #selector(uploadSelectedThemeToStore)
        r.library.renameBtn.target = self
        r.library.renameBtn.action = #selector(renameSelectedTheme)
        r.library.repairBtn.target = self
        r.library.repairBtn.action = #selector(repairSelectedTheme)
        r.library.bootBtn.target = self
        r.library.bootBtn.action = #selector(scanBootEntries)
        r.library.moreBtn.target = self
        r.library.moreBtn.action = #selector(showMoreMenu(_:))
        r.library.aiBtn.target = self
        r.library.aiBtn.action = #selector(openAIThemeGenerator)
        r.library.table.menu = makeThemeMenu()
        r.preview.designBtn.target = self
        r.preview.designBtn.action = #selector(openDesignEditor)
        r.onDropFiles = { [weak self] urls in self?.importURLs(urls) }
        r.preview.aspectCtrl.target = self
        r.preview.aspectCtrl.action = #selector(aspectChanged)
        r.preview.labelsChk.target = self
        r.preview.labelsChk.action = #selector(previewOptionChanged)
        r.preview.selectChk.target = self
        r.preview.selectChk.action = #selector(previewOptionChanged)
        r.statusBar.helpBtn.target = self
        r.statusBar.helpBtn.action = #selector(showHelp)
        r.statusBar.storeBtn.target = self
        r.statusBar.storeBtn.action = #selector(openStore)
        r.statusBar.bootSimBtn.target = self
        r.statusBar.bootSimBtn.action = #selector(openBootSim)
        r.statusBar.assetsBtn.target = self
        r.statusBar.assetsBtn.action = #selector(openAssetLibrary)

        let e = r.efi
        for (b, sel) in [(e.scanBtn, #selector(scanEFI)),
                         (e.mountBtn, #selector(mountEFI)),
                         (e.unmountBtn, #selector(unmountEFI)),
                         (e.finderBtn, #selector(openFinder)),
                         (e.loadCurrentBtn, #selector(loadCurrentTheme)),
                         (e.applyBtn, #selector(confirmApply)),
                         (e.restoreBtn, #selector(confirmRestore))] as [(NSButton, Selector)] {
            b.target = self; b.action = sel
        }

        restoreState()
        reloadLibrary(selectId: jsonRead(Paths.state)?["themeId"] as? String)
        reloadBackups()
        updateApplyButton()
        scanEFINow()

        NotificationCenter.default.addObserver(self,
            selector: #selector(appWillTerminate),
            name: NSApplication.willTerminateNotification, object: nil)
    }

    /// Used only by the build-validation `--debug ... --editor` mode.
    func debugOpenEditor() { editSelectedTheme() }
    func debugSelectEditorAsset(_ row: Int) { editor?.debugSelectAsset(row) }
    func debugOpenEditorConverter(_ image: URL? = nil) { editor?.debugOpenConverter(image) }
    func debugOpenDesign() { openDesignEditor() }
    func debugDesignAddText(_ s: String) { designWindow?.debugAddText(s) }
    func debugDesignMove(dx: Double, dy: Double) { designWindow?.debugMoveSelected(dx: dx, dy: dy) }
    func debugDesignResize(dw: Double, dh: Double) { designWindow?.debugResizeSelected(dw: dw, dh: dh) }
    func debugDesignFont(_ family: String, size: Double) {
        designWindow?.debugFontSelected(family, size: size)
    }
    func debugDesignDump() -> String { designWindow?.debugLayoutDump() ?? "" }
    func debugDesignExportPNG(to path: String) { designWindow?.debugExportPNG(to: path) }
    func debugDesignPersist() { designWindow?.debugPersist() }
    func debugOpenBootScan() { scanBootEntries() }

    /// Used only by the build-validation `--debug ... --select N` mode.
    func debugSelect(_ row: Int) {
        guard row >= 0 && row < themes.count else { return }
        root.library.table.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        syncThemeSelection()
    }

    /// Single source of truth for "which theme is being previewed".
    private func syncThemeSelection() {
        let row = root.library.table.selectedRow
        guard row >= 0 && row < themes.count else { return }
        if ProcessInfo.processInfo.environment["OCTHEME_DEBUG"] == "1" {
            appLog("syncThemeSelection row=\(row) theme=\(themes[row].name)")
        }
        selectTheme(themes[row])
    }

    // MARK: Table data source

    func numberOfRows(in tableView: NSTableView) -> Int {
        if tableView === root.library.table { return themes.count }
        if tableView === root.efi.efiTable { return scanResult.partitions.count }
        if tableView === root.efi.backupTable { return backups.count }
        return 0
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        if tableView === root.library.table {
            let v = (tableView.makeView(withIdentifier: themeRowID, owner: self) as? ThemeRowView)
                ?? ThemeRowView()
            v.identifier = themeRowID
            v.configure(themes[row])
            return v
        }
        if tableView === root.efi.efiTable {
            let v = (tableView.makeView(withIdentifier: efiRowID, owner: self) as? EFIRowView)
                ?? EFIRowView()
            v.identifier = efiRowID
            v.configure(scanResult.partitions[row])
            return v
        }
        if tableView === root.efi.backupTable {
            let v = (tableView.makeView(withIdentifier: backupRowID, owner: self) as? BackupRowView)
                ?? BackupRowView()
            v.identifier = backupRowID
            v.configure(backups[row])
            return v
        }
        return nil
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        guard let t = notification.object as? NSTableView else { return }
        if t === root.library.table {
            syncThemeSelection()
        } else if t === root.efi.efiTable {
            let row = t.selectedRow
            selectedPartition = (row >= 0 && row < scanResult.partitions.count)
                ? scanResult.partitions[row] : nil
            refreshInspect()
        } else if t === root.efi.backupTable {
            let row = t.selectedRow
            selectedBackup = (row >= 0 && row < backups.count) ? backups[row] : nil
            root.efi.restoreBtn.isEnabled = selectedBackup != nil && !busy
        }
    }

    @objc private func themeTableClicked() { syncThemeSelection() }
    @objc private func efiTableClicked() { /* selection handled by delegate */ }
    @objc private func backupTableClicked() { /* selection handled by delegate */ }

    // MARK: Library / preview

    private func reloadLibrary(selectId: String? = nil) {
        ThemeLibrary.shared.reload()
        themes = ThemeLibrary.shared.themes
        root.library.table.reloadData()
        root.library.foot.stringValue =
            "共 \(themes.count) 套主题 · 拖入 ZIP / 文件夹即可安装\n"
            + "右键主题：设计 / 重命名 / 修复目录 / 识别启动项\n"
            + "「＋ 新建」可选预设图标集，免去手动拖图标"
        if let id = selectId, let t = themes.first(where: { $0.id == id }) {
            selectTheme(t)
            let row = themes.firstIndex { $0.id == id } ?? 0
            root.library.table.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        } else if let first = themes.first {
            selectTheme(first)
            root.library.table.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        }
    }

    private func selectTheme(_ t: Theme) {
        selectedTheme = t
        let p = root.preview
        p.picker.theme = t
        p.picker.designLayout = t.layout
        p.titleF.stringValue = t.name
        let (bw, bh) = t.backgroundSize
        let sizeText = bw > 0 ? " · 背景 \(bw)×\(bh)" : ""
        let designNote = t.layout == nil ? "" : " · ✎ 可视化设计"
        p.statsF.stringValue = "\(t.icons.count) 个启动项 · \(t.fileCount) 个文件 · \(t.sizeText)"
            + " · 字体 \(t.fontCount) · 标签 \(t.labelCount) · 声音 \(t.soundCount)"
            + sizeText + designNote

        // Auto-fill PickerVariant, but never overwrite a manual edit.
        let vf = root.efi.variantField
        if vf.stringValue == autoVariant { vf.stringValue = "" }
        // OpenCore uses a UEFI-style backslash path; show that form in the UI.
        autoVariant = t.pickerVariant.replacingOccurrences(of: "/", with: "\\")
        if !autoVariant.isEmpty && vf.stringValue.isEmpty { vf.stringValue = autoVariant }

        updateApplyButton()
        saveState()
    }

    @objc private func aspectChanged() {
        let aspects: [CGFloat] = [16.0 / 9.0, 16.0 / 10.0, 4.0 / 3.0]
        let i = root.preview.aspectCtrl.selectedSegment
        if i >= 0 && i < aspects.count { root.preview.picker.aspect = aspects[i] }
        saveState()
    }

    @objc private func previewOptionChanged() {
        root.preview.picker.showLabels = root.preview.labelsChk.state == .on
        root.preview.picker.selectionVisible = root.preview.selectChk.state == .on
        saveState()
    }

    // MARK: State

    private func restoreState() {
        let s = jsonRead(Paths.state) ?? [:]
        let aspect = s["aspect"] as? String ?? "16/9"
        let idx: Int = aspect == "4/3" ? 2 : aspect == "16/10" ? 1 : 0
        root.preview.aspectCtrl.selectedSegment = idx
        if idx < 3 {
            root.preview.picker.aspect = [16.0 / 9.0, 16.0 / 10.0, 4.0 / 3.0][idx]
        }
        let show = s["showLabels"] as? Bool ?? true
        root.preview.labelsChk.state = show ? .on : .off
        root.preview.picker.showLabels = show
        if let r = s["replace"] as? Bool { root.efi.replaceChk.state = r ? .on : .off }
        if let p = s["enablePicker"] as? Bool { root.efi.pickerChk.state = p ? .on : .off }
    }

    private func saveState() {
        let aspects = ["16/9", "16/10", "4/3"]
        let i = max(0, min(2, root.preview.aspectCtrl.selectedSegment))
        let obj: [String: Any] = [
            "themeId": selectedTheme?.id ?? "",
            "aspect": aspects[i],
            "showLabels": root.preview.labelsChk.state == .on,
            "replace": root.efi.replaceChk.state == .on,
            "enablePicker": root.efi.pickerChk.state == .on,
        ]
        try? jsonWrite(obj, to: Paths.state)
    }

    @objc private func appWillTerminate() { saveState() }

    // MARK: Busy / status

    private func setBusy(_ on: Bool, _ text: String? = nil) {
        busy = on
        root.statusBar.set(text ?? (on ? "处理中…" : "就绪"), busy: on)
        let e = root.efi
        let l = root.library
        let controls: [NSControl] = [e.scanBtn, e.mountBtn, e.unmountBtn, e.finderBtn,
                                     e.loadCurrentBtn, e.applyBtn, e.restoreBtn,
                                     l.importBtn, l.deleteBtn, l.editBtn, l.newBtn,
                                     l.renameBtn, l.repairBtn, l.bootBtn,
                                     l.icnsBtn, l.storeBtn, l.moreBtn]
        for c in controls { c.isEnabled = !on && controlShouldEnable(c) }
        if !on { updateApplyButton() }
    }

    private func controlShouldEnable(_ c: NSControl) -> Bool {
        let e = root.efi
        let l = root.library
        switch c {
        case e.mountBtn: return selectedPartition?.mounted == false
        case e.unmountBtn, e.finderBtn, e.loadCurrentBtn: return selectedPartition?.mounted == true
        case e.restoreBtn: return selectedBackup != nil
        case l.deleteBtn, l.editBtn, l.storeBtn: return selectedTheme != nil
        default: return true
        }
    }

    private func runBusy<T>(_ title: String,
                            _ work: @escaping () -> T,
                            _ finish: @escaping (T) -> Void) {
        setBusy(true, title)
        DispatchQueue.global(qos: .userInitiated).async {
            let value = work()
            DispatchQueue.main.async {
                self.setBusy(false)
                finish(value)
            }
        }
    }

    private func notify(_ title: String, _ text: String, critical: Bool = false) {
        let a = NSAlert()
        a.messageText = title
        a.informativeText = text
        a.alertStyle = critical ? .critical : .informational
        a.addButton(withTitle: "好")
        if let w = window { a.beginSheetModal(for: w, completionHandler: nil) }
        else { a.runModal() }
    }

    private func confirm(_ title: String, _ text: String, ok: String = "继续",
                         danger: Bool = false, _ action: @escaping () -> Void) {
        let a = NSAlert()
        a.messageText = title
        a.informativeText = text
        a.alertStyle = danger ? .critical : .warning
        a.addButton(withTitle: ok)
        a.addButton(withTitle: "取消")
        guard let w = window else { return }
        a.beginSheetModal(for: w) { resp in
            if resp == .alertFirstButtonReturn { action() }
        }
    }

    // MARK: Import

    @objc func chooseZip() {
        let p = NSOpenPanel()
        p.message = "选择 OpenCore 主题 ZIP 包（支持 EFI/OC/Resources 结构与多变体主题）"
        p.allowedFileTypes = ["zip"]
        p.canChooseDirectories = false
        p.allowsMultipleSelection = false
        p.beginSheetModal(for: window!) { [weak self] resp in
            guard resp == .OK, let url = p.url else { return }
            self?.importURLs([url])
        }
    }

    @objc func chooseFolder() {
        let p = NSOpenPanel()
        p.message = "选择包含主题资源的文件夹"
        p.canChooseFiles = false
        p.canChooseDirectories = true
        p.allowsMultipleSelection = false
        p.beginSheetModal(for: window!) { [weak self] resp in
            guard resp == .OK, let url = p.url else { return }
            self?.importURLs([url])
        }
    }

    /// Single entry point for panel imports, drag-and-drop and "open with".
    /// Multiple packages are imported sequentially in one busy operation.
    func importURLs(_ urls: [URL]) {
        guard !busy else {
            notify("正在处理", "请等待当前操作结束后再安装主题。")
            return
        }
        let accepted = themeInstallDrops(urls)
        guard !accepted.isEmpty else {
            notify("无法安装主题", "请拖入 .zip 主题包，或包含主题资源的文件夹。", critical: true)
            return
        }
        runBusy("正在安装 \(accepted.count) 个主题包…", {
            () -> (created: [Theme], errors: [String]) in
            var created: [Theme] = []
            var errors: [String] = []
            for u in accepted {
                do {
                    created += try ThemeLibrary.shared.importPackage(u, name: nil)
                } catch {
                    errors.append("\(u.lastPathComponent)：\(error.localizedDescription)")
                }
            }
            return (created, errors)
        }) { (result: (created: [Theme], errors: [String])) in
            let keep = self.selectedTheme?.id
            self.reloadLibrary(selectId: result.created.first?.id ?? keep)
            let names = result.created.map(\.name).joined(separator: "、")
            var text = result.created.isEmpty ? "" : "已导入 \(result.created.count) 套主题：\(names)"
            if !result.errors.isEmpty {
                text += (text.isEmpty ? "" : "\n\n") + "失败 \(result.errors.count) 项：\n"
                    + result.errors.joined(separator: "\n")
            }
            self.notify(result.errors.isEmpty ? "导入完成" : "部分导入完成",
                        text.isEmpty ? "没有识别到可用主题。" : text,
                        critical: result.created.isEmpty)
        }
    }

    @objc func removeSelectedTheme() {
        guard let t = contextTheme() ?? selectedTheme else { return }
        confirm("移除主题", "确定从主题库移除「\(t.name)」？只会删除本机的主题副本，不会改动 EFI。",
                ok: "移除", danger: true) {
            do {
                if self.editor?.themeId == t.id { self.editor?.window?.close() }
                try ThemeLibrary.shared.remove(t)
                self.reloadLibrary()
                self.notify("已移除", "「\(t.name)」已从主题库移除。")
            } catch {
                self.notify("移除失败", error.localizedDescription, critical: true)
            }
        }
    }

    /// Open the native theme editor for the selected theme.
    @objc func editSelectedTheme() {
        guard let t = contextTheme() ?? selectedTheme else { return }
        if let e = editor, e.themeId == t.id, e.window?.isVisible == true {
            e.showWindow(nil)
            e.window?.makeKeyAndOrderFront(nil)
            return
        }
        let e = ThemeEditorWindowController(theme: t) { [weak self] savedId in
            self?.reloadLibrary(selectId: savedId)
        }
        editor = e
        e.showWindow(nil)
        e.window?.makeKeyAndOrderFront(nil)
    }

    /// Open the visual design editor for the selected theme: free drag / snap,
    /// eight-handle resize, right-click replace, inline text edit, font swap.
    @objc func openDesignEditor() {
        guard let t = contextTheme() ?? selectedTheme else {
            notify("先选一个主题", "在左侧主题库里选中一个主题，再打开可视化设计。")
            return
        }
        if let d = designWindow, d.themeId == t.id, d.window?.isVisible == true {
            d.showWindow(nil)
            d.window?.makeKeyAndOrderFront(nil)
            return
        }
        let d = DesignWindowController(theme: t) { [weak self] savedId in
            self?.reloadLibrary(selectId: savedId)
        }
        d.onLayoutChange = { [weak self] tid, layout in
            guard let self = self, self.selectedTheme?.id == tid else { return }
            self.root.preview.picker.designLayout = layout
            let s = self.root.preview.statsF.stringValue
            if !s.contains("✎ 可视化设计") {
                self.root.preview.statsF.stringValue = s + " · ✎ 可视化设计"
            }
        }
        d.onClosed = { [weak self] in self?.designWindow = nil }
        designWindow = d
        d.showWindow(nil)
        d.window?.makeKeyAndOrderFront(nil)
    }

    /// Create a theme. A preset pre-fills real boot icons + a background so the
    /// user does not have to drag each file in by hand.
    @objc func makeNewTheme() {
        let presets = ThemePreset.all()
        let a = NSAlert()
        a.messageText = "新建主题"
        a.informativeText = "输入名称并选择一个起始图标集。预设会直接生成图标文件与默认排版；选「空白」则自己拖入。"
        a.alertStyle = .informational
        let acc = NSView(frame: NSRect(x: 0, y: 0, width: 360, height: 104))
        let nameField = NSTextField(frame: NSRect(x: 0, y: 72, width: 360, height: 24))
        nameField.stringValue = "我的主题"
        nameField.placeholderString = "主题名称"
        nameField.bezelStyle = .roundedBezel
        let pop = NSPopUpButton(frame: NSRect(x: 0, y: 40, width: 360, height: 26))
        pop.addItem(withTitle: "空白主题 · 自己拖入图标")
        for p in presets { pop.addItem(withTitle: "\(p.name) · \(p.desc)") }
        let note = UI.label("预设图标随应用内置，创建后仍可在编辑器里增删替换。",
                            size: 10, color: .secondaryLabelColor)
        note.frame = NSRect(x: 0, y: 6, width: 360, height: 26)
        note.maximumNumberOfLines = 2
        for v in [nameField, pop, note] as [NSView] { acc.addSubview(v) }
        a.accessoryView = acc
        a.addButton(withTitle: "创建并编辑")
        a.addButton(withTitle: "取消")
        guard a.runModal() == .alertFirstButtonReturn else { return }

        let idx = pop.indexOfSelectedItem
        let preset = (idx > 0 && idx - 1 < presets.count) ? presets[idx - 1] : nil
        do {
            // Seed the new theme from the EFI partition currently selected in
            // the right-hand list (if mounted) so it inherits the working
            // picker assets; falls back to bundled defaults otherwise.
            let t = try makeTheme(name: nameField.stringValue, preset: preset,
                                  efiMount: selectedPartition?.mountPoint)
            self.reloadLibrary(selectId: t.id)
            self.editSelectedTheme()
            self.root.statusBar.set(preset == nil
                ? "已新建「\(t.name)」· 拖入资源即可开始"
                : "已新建「\(t.name)」· 已应用预设「\(preset!.name)」", busy: false)
        } catch {
            self.notify("新建失败", error.localizedDescription, critical: true)
        }
    }

    // MARK: Store & boot simulation

    /// The theme currently shown in the preview (exposed for the boot-sim
    /// fallback and the store's "apply" hand-off).
    var currentTheme: Theme? { selectedTheme }

    /// Open the theme store window (list / detail / download / upload).
    @objc func openStore() {
        if let s = storeWindow, s.window?.isVisible == true {
            s.showWindow(nil)
            s.window?.makeKeyAndOrderFront(nil)
            return
        }
        let s = StoreWindowController()
        storeWindow = s
        s.showWindow(nil)
        s.window?.makeKeyAndOrderFront(nil)
    }

    /// AI theme generator: prompt -> design -> locally rendered full theme.
    @objc func openAIThemeGenerator() {
        if let a = aiWindow, a.window?.isVisible == true {
            a.showWindow(nil)
            a.window?.makeKeyAndOrderFront(nil)
            return
        }
        let a = AIThemeWindowController()
        aiWindow = a
        a.onClose = { [weak self] in self?.aiWindow = nil }
        a.onSaved = { [weak self] id in
            guard let self = self else { return }
            self.reloadLibrary(selectId: id)
            self.updateApplyButton()
            self.root.statusBar.set("已生成并选中新主题 · 可直接应用到 EFI", busy: false)
        }
        a.showWindow(nil)
        a.window?.makeKeyAndOrderFront(nil)
    }

    /// Browse / maintain the bundled + user-imported wallpaper & icon pool.
    /// From a theme editor the same window additionally offers "apply to theme".
    @objc func openAssetLibrary() {
        if let a = assetWindow, a.window?.isVisible == true {
            a.showWindow(nil)
            a.window?.makeKeyAndOrderFront(nil)
            return
        }
        let a = AssetLibraryWindowController(mode: .browse)
        assetWindow = a
        a.onClose = { [weak self] in self?.assetWindow = nil }
        a.showWindow(nil)
        a.window?.makeKeyAndOrderFront(nil)
    }

    /// Open the full-screen simulated boot / startup overlay. It reads the real
    /// host EFI theme when available and otherwise shows the current selection.
    @objc func openBootSim() {
        if let b = bootSimWindow, b.window?.isVisible == true {
            b.showBoot()
            return
        }
        let b = BootSimWindowController(fallback: selectedTheme)
        bootSimWindow = b
        b.onClosed = { [weak self] in self?.bootSimWindow = nil }
        b.showBoot()
    }

    /// Apply a theme that came from the store: select it, scan for a mounted EFI
    /// partition, and run the exact same apply flow as the main window.
    func applyThemeFromStore(_ theme: Theme) {
        selectedTheme = theme
        let scan = EFIScanResult.scan()
        if let p = scan.best ?? scan.partitions.first(where: { $0.mounted }),
           p.mounted {
            selectedPartition = p
            refreshInspect()
            showWindow(nil)
            NSApp.activate(ignoringOtherApps: true)
            confirmApply()
        } else {
            showWindow(nil)
            NSApp.activate(ignoringOtherApps: true)
            notify("未挂载 EFI 分区",
                   "主题「\(theme.name)」已加入本机主题库。请先在右侧 EFI 分区「挂载」一个分区，再点「应用主题到 EFI」。")
        }
    }

    // MARK: EFI 配置包（商店上传 / 安装）

    /// 从主窗口当前选中的已挂载 EFI 分区生成脱敏配置包，供商店上传。
    func exportEFIConfigPackageForStore() throws -> URL {
        guard let p = selectedPartition, p.mounted else {
            throw AppError.message("请先在右侧「EFI 分区」选择并挂载一个分区")
        }
        Paths.ensure()
        let dest = Paths.scratch.appendingPathComponent(
            "efi_config_" + UUID().uuidString + ".zip")
        return try EFIActions.makeConfigPackage(device: p.device,
                                                mount: p.mountPoint, to: dest)
    }

    /// 下载 EFI 配置包后，按主窗口当前选中的 EFI 分区安装。
    func installEFIConfigPackage(_ zip: URL) {
        guard let p = selectedPartition, p.mounted else {
            showWindow(nil)
            NSApp.activate(ignoringOtherApps: true)
            notify("未挂载 EFI 分区",
                   "EFI 配置包已下载到本机。请先在右侧 EFI 分区「挂载」一个分区，再重新下载安装。")
            return
        }
        showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
        let text = """
        即将把下载的 EFI 配置包写入 \(p.device)（\(p.mountPoint)）的 EFI/OC/Resources。

        只会安装包内的主题资源，并把 PickerMode / PickerVariant 合并进本机现有的 config.plist；
        不会覆盖 PlatformInfo / NVRAM / Kexts / Drivers 等机器相关配置。
        写入前会自动备份现有 Resources 与 config.plist；此操作需要管理员密码并会修改引导分区。
        """
        confirm("确认写入 EFI 配置包", text, ok: "写入配置包", danger: true) {
            self.runBusy("正在写入 EFI 配置包（可能需要管理员授权）…", {
                EFIActions.installConfigPackage(zip: zip, device: p.device,
                                                mount: p.mountPoint)
            }) { (r: ActionResult) in
                self.reloadBackups()
                self.refreshInspect()
                if r.ok {
                    self.notify("安装成功", r.message + "\n备份编号：" + r.backupId)
                } else {
                    self.notify("安装失败", r.message +
                        (r.backupId.isEmpty ? "" : "\n已保留备份：" + r.backupId),
                                critical: true)
                }
            }
        }
    }

    // MARK: Library actions / context menu

    /// Theme a context-menu action should target. A right-click selects the row
    /// first, so the selected row is always the right one.
    private func contextTheme() -> Theme? {
        let r = contextRow >= 0 ? contextRow : root.library.table.selectedRow
        guard r >= 0 && r < themes.count else { return nil }
        return themes[r]
    }

    func menuWillOpen(_ menu: NSMenu) {
        guard menu === root.library.table.menu else { return }
        let r = root.library.table.clickedRow
        if r >= 0 {
            root.library.table.selectRowIndexes(IndexSet(integer: r),
                                                byExtendingSelection: false)
        }
        contextRow = r
    }

    func menuDidClose(_ menu: NSMenu) { contextRow = -1 }

    private func makeThemeMenu() -> NSMenu {
        let m = NSMenu(title: "主题操作")
        m.delegate = self
        func item(_ title: String, _ sel: Selector) {
            let i = NSMenuItem(title: title, action: sel, keyEquivalent: "")
            i.target = self
            m.addItem(i)
        }
        item("可视化设计…", #selector(openDesignEditor))
        item("主题编辑器…", #selector(editSelectedTheme))
        item("重命名…", #selector(renameSelectedTheme))
        m.addItem(.separator())
        item("修复主题目录", #selector(repairSelectedTheme))
        item("识别系统启动项…", #selector(scanBootEntries))
        m.addItem(.separator())
        item("导出 ZIP…", #selector(exportSelectedTheme))
        item("上传到主题商店…", #selector(uploadSelectedThemeToStore))
        item("在 Finder 显示", #selector(revealSelectedTheme))
        m.addItem(.separator())
        item("删除主题", #selector(removeSelectedTheme))
        return m
    }

    @objc private func showMoreMenu(_ sender: NSButton) {
        let m = makeThemeMenu()
        m.popUp(positioning: nil,
                at: NSPoint(x: 0, y: sender.bounds.height + 2), in: sender)
    }

    @objc func renameSelectedTheme() {
        guard let t = contextTheme() else {
            notify("先选一个主题", "在左侧主题库里选中一个主题再重命名。")
            return
        }
        askForThemeName("重命名主题",
                        "只改显示名称，不会改变主题目录，也不会改动已写入 EFI 的内容。",
                        t.name, "保存") { [weak self] name in
            guard let self = self else { return }
            do {
                let clean = try renameTheme(t, to: name)
                self.reloadLibrary(selectId: t.id)
                self.root.statusBar.set("已重命名为「\(clean)」", busy: false)
            } catch {
                self.notify("重命名失败", error.localizedDescription, critical: true)
            }
        }
    }

    @objc func repairSelectedTheme() {
        guard let t = contextTheme() else {
            notify("先选一个主题", "在左侧主题库里选中一个主题再修复。")
            return
        }
        do {
            let r = try repairTheme(t)
            self.reloadLibrary(selectId: t.id)
            self.notify("修复完成", r.summary)
            self.root.statusBar.set(r.changed
                ? "已修复「\(t.name)」" : "「\(t.name)」目录正常", busy: false)
        } catch {
            self.notify("修复失败", error.localizedDescription, critical: true)
        }
    }

    @objc func scanBootEntries() {
        guard let t = contextTheme() ?? selectedTheme else {
            notify("先选一个主题", "在左侧主题库里选中一个主题，再把识别到的启动项加入它。")
            return
        }
        if let w = bootWindow, w.window?.isVisible == true {
            w.showWindow(nil)
            w.window?.makeKeyAndOrderFront(nil)
            return
        }
        let w = BootScanWindowController(theme: t) { [weak self] themeId in
            self?.reloadLibrary(selectId: themeId)
        }
        bootWindow = w
        w.onClose = { [weak self] in self?.bootWindow = nil }
        w.showWindow(nil)
        w.window?.makeKeyAndOrderFront(nil)
    }

    @objc func exportSelectedTheme() {
        guard let t = contextTheme() else { return }
        let p = NSSavePanel()
        p.title = "导出主题 ZIP"
        p.nameFieldStringValue = t.name + ".zip"
        p.allowedFileTypes = ["zip"]
        guard p.runModal() == .OK, let url = p.url else { return }
        do {
            try exportTheme(t, to: url)
            self.root.statusBar.set("已导出 \(url.lastPathComponent)", busy: false)
        } catch {
            notify("导出失败", error.localizedDescription, critical: true)
        }
    }

    // MARK: 上传到主题商店

    /// 把主题库选中的主题打包并打开商店上传面板（预填名称 / 简介 / zip / 预览图）。
    /// 预览图由 App 用真实 Boot Picker 渲染自动生成，用户仍可在面板里更换。
    @objc func uploadSelectedThemeToStore() {
        guard let t = contextTheme() ?? selectedTheme else {
            notify("先选一个主题", "在左侧主题库里选中一个主题，再上传到主题商店。")
            return
        }
        guard StoreClient.baseURL != nil else {
            notify("未配置商店地址", "请先在「🛒 主题商店」窗口填写可用的服务器地址。", critical: true)
            return
        }
        let name = t.name
        runBusy("正在打包「\(name)」…", {
            () -> Result<(zip: URL, desc: String), Error> in
            do {
                Paths.ensure()
                let zip = Paths.scratch.appendingPathComponent(
                    "store_upload_\(UUID().uuidString).zip")
                try exportTheme(t, to: zip)
                var bits = ["\(t.icons.count) 个启动项", "\(t.fileCount) 个文件"]
                if !t.sizeText.isEmpty { bits.append(t.sizeText) }
                if !t.pickerVariant.isEmpty { bits.append("PickerVariant: \(t.pickerVariant)") }
                let desc = "由 OC Theme Studio 主题库上传。\n" + bits.joined(separator: " · ")
                return .success((zip, desc))
            } catch {
                return .failure(error)
            }
        }) { (result: Result<(zip: URL, desc: String), Error>) in
            switch result {
            case .failure(let err):
                self.notify("打包失败", err.localizedDescription, critical: true)
            case .success(let packed):
                let previews = self.renderStorePreviews(t)
                let u = StoreUploadWindowController()
                u.applyPrefill(name: name, description: packed.desc,
                               package: packed.zip, previews: previews)
                u.onSubmitted = { [weak self] in
                    self?.storeUpload = nil
                    self?.notify("上传成功", "「\(name)」已发布到主题商店。")
                    self?.root.statusBar.set("已上传「\(name)」到主题商店", busy: false)
                }
                u.onCancel = { [weak self] in self?.storeUpload = nil }
                self.storeUpload = u
                u.showSheet(on: self.window!)
            }
        }
    }

    /// 用真实 Boot Picker 渲染 1-3 张预览图 PNG（不同选中项），写到 scratch。
    /// 必须在主线程调用（AppKit 视图渲染）。
    private func renderStorePreviews(_ t: Theme) -> [URL] {
        let count = t.icons.count
        var picks = [0]
        if count > 2 { picks.append(count / 2) }
        if count > 1 { picks.append(count - 1) }
        var seen = Set<Int>()
        picks = picks.filter { seen.insert($0).inserted }

        let screenW = 1280, screenH = 800        // 16:10
        let pad: CGFloat = 18
        let frame = NSRect(x: 0, y: 0,
                           width: CGFloat(screenW) + pad * 2,
                           height: CGFloat(screenH) + pad * 2)
        var urls: [URL] = []
        Paths.ensure()
        for (i, sel) in picks.enumerated() {
            let v = BootPickerView(frame: frame)
            v.theme = t
            v.designLayout = t.layout
            v.aspect = CGFloat(screenW) / CGFloat(screenH)
            v.showLabels = true
            v.selectionVisible = true
            v.selectedIndex = sel
            guard let rep = v.bitmapImageRepForCachingDisplay(in: v.bounds) else { continue }
            v.cacheDisplay(in: v.bounds, to: rep)
            // 裁掉四周 18pt 的舞台边距，只留纯屏幕画面。
            // bitmapImageRep 是像素尺寸（Retina 下可能是 2x），必须按 scale 换算，
            // 否则会只截到左上角四分之一。
            let pngData: Data?
            let scale = v.bounds.width > 0
                ? CGFloat(rep.pixelsWide) / v.bounds.width : 1
            let crop = CGRect(x: pad * scale, y: pad * scale,
                              width: CGFloat(screenW) * scale,
                              height: CGFloat(screenH) * scale)
            if let cg = rep.cgImage,
               crop.maxX <= CGFloat(cg.width), crop.maxY <= CGFloat(cg.height),
               let cropped = cg.cropping(to: crop) {
                pngData = NSBitmapImageRep(cgImage: cropped)
                    .representation(using: .png, properties: [:])
            } else {
                pngData = rep.representation(using: .png, properties: [:])
            }
            guard let data = pngData else { continue }
            let out = Paths.scratch.appendingPathComponent(
                "store_preview_\(t.id)_\(i).png")
            do {
                try data.write(to: out)
                urls.append(out)
            } catch { continue }
        }
        return urls
    }

    @objc func revealSelectedTheme() {
        guard let t = contextTheme() else { return }
        NSWorkspace.shared.activateFileViewerSelecting([t.dir])
    }

    /// Standalone converter: no theme attached, output is saved to a file.
    /// `initialFile` is used when a picture is dropped on the Dock / Finder icon.
    func openICNSConverter(initialFile: URL? = nil) {
        if let c = icnsWindow, c.window?.isVisible == true {
            if let u = initialFile { c.debugLoad(u) }
            c.showWindow(nil)
            c.window?.makeKeyAndOrderFront(nil)
            return
        }
        let c = ICNSWindowController(initialFile: initialFile)
        icnsWindow = c
        c.onClose = { [weak self] in self?.icnsWindow = nil }
        c.showWindow(nil)
        c.window?.makeKeyAndOrderFront(nil)
    }

    @objc private func convertImage() { openICNSConverter() }

    /// Debug hook used by the build-validation snapshot mode.
    func debugOpenConverter(_ image: URL? = nil) { openICNSConverter(initialFile: image) }

    // MARK: EFI

    @objc func scanEFI() { scanEFINow() }

    private func scanEFINow() {
        runBusy("正在扫描 EFI 分区…", {
            EFIScanResult.scan()
        }) { (scan: EFIScanResult) in
            let pinned = self.selectedPartition?.device
            self.scanResult = scan
            self.root.efi.efiTable.reloadData()
            var row = scan.partitions.firstIndex { $0.current } ?? 0
            if let dev = pinned, let i = scan.partitions.firstIndex(where: { $0.device == dev }) {
                row = i
            }
            if !scan.partitions.isEmpty {
                self.root.efi.efiTable.selectRowIndexes(IndexSet(integer: row),
                                                        byExtendingSelection: false)
                self.selectedPartition = scan.partitions[row]
            } else {
                self.selectedPartition = nil
            }
            self.refreshInspect()
            let note = scan.ambiguous
                ? "检测到 \(scan.systemDiskEfiCount) 个同盘 EFI 分区，请确认含 OC 配置的那一个"
                : "扫描完成：\(scan.partitions.count) 个 EFI 分区 · 系统盘 \(scan.physicalDisk)"
            self.root.statusBar.set(note, busy: false)
        }
    }

    private func refreshInspect() {
        let e = root.efi
        guard let p = selectedPartition else {
            e.ocInfo.stringValue = "未选择 EFI 分区。\n点击「重新扫描」列出本机 EFI 分区。"
            updateApplyButton()
            return
        }
        var lines: [String] = [
            "设备：\(p.device)   \(p.sizeText)",
            "卷标：\(p.volumeName.isEmpty ? "—" : p.volumeName)",
            "状态：\(p.mounted ? "已挂载 \(p.mountPoint)" : "未挂载")",
        ]
        if p.mounted {
            if let i = try? EFIInspect.inspect(mount: p.mountPoint) {
                lines += [
                    "EFI/OC：\(i.hasOC ? "存在" : "不存在")   config.plist：\(i.hasConfig ? "存在" : "不存在")",
                    "PickerMode：\(i.pickerMode.isEmpty ? "—" : i.pickerMode)",
                    "PickerVariant：\(i.pickerVariant.isEmpty ? "—" : i.pickerVariant)",
                    "主题目录：\(i.imageVariantPresent ? "存在" : "缺失 ← 会显示文字菜单")",
                    "OpenCanopy：\(i.canopyInConfig ? "已启用" : "未启用") · \(i.canopyDriverFile ? "驱动存在" : "驱动缺失")",
                    "Resources：Image \(i.resources["Image"] ?? 0) · Font \(i.resources["Font"] ?? 0)" +
                        " · Label \(i.resources["Label"] ?? 0) · Audio \(i.resources["Audio"] ?? 0)",
                    "图形菜单：\(i.graphicalReady ? "配置就绪" : "配置不完整")",
                ]
            } else {
                lines.append("无法读取 OpenCore 配置")
            }
        } else {
            lines.append("挂载后可查看 OpenCore 配置与当前主题。")
        }
        e.ocInfo.stringValue = lines.joined(separator: "\n")
        updateApplyButton()
    }

    private func updateApplyButton() {
        let e = root.efi
        let ready = !busy && selectedTheme != nil && selectedPartition?.mounted == true
        e.applyBtn.isEnabled = ready
        for (b, sel) in [(e.mountBtn, #selector(mountEFI)),
                         (e.unmountBtn, #selector(unmountEFI)),
                         (e.finderBtn, #selector(openFinder)),
                         (e.loadCurrentBtn, #selector(loadCurrentTheme))] as [(NSButton, Selector)] {
            _ = sel
            b.isEnabled = !busy && controlShouldEnable(b)
        }
        e.restoreBtn.isEnabled = !busy && selectedBackup != nil
        let l = root.library
        l.deleteBtn.isEnabled = !busy && selectedTheme != nil
        l.editBtn.isEnabled = !busy && selectedTheme != nil
        l.storeBtn.isEnabled = !busy && selectedTheme != nil
        l.newBtn.isEnabled = !busy
        l.importBtn.isEnabled = !busy
    }

    @objc private func mountEFI() {
        guard let p = selectedPartition else { return }
        runBusy("正在挂载 \(p.device)…", {
            EFIActions.mount(device: p.device)
        }) { (r: ActionResult) in
            if !r.ok { self.notify("挂载失败", r.message, critical: true) }
            if let s = r.scan { self.scanResult = s; self.root.efi.efiTable.reloadData() }
            self.selectDevice(p.device)
            self.root.statusBar.set(r.ok ? "已挂载 \(p.device)" : r.message, busy: false)
        }
    }

    @objc private func unmountEFI() {
        guard let p = selectedPartition else { return }
        runBusy("正在卸载 \(p.device)…", {
            EFIActions.unmount(device: p.device)
        }) { (r: ActionResult) in
            if !r.ok { self.notify("卸载失败", r.message, critical: true) }
            if let s = r.scan { self.scanResult = s; self.root.efi.efiTable.reloadData() }
            self.selectDevice(p.device)
            self.root.statusBar.set(r.ok ? "已卸载 \(p.device)" : r.message, busy: false)
        }
    }

    private func selectDevice(_ dev: String) {
        if let i = scanResult.partitions.firstIndex(where: { $0.device == dev }) {
            root.efi.efiTable.selectRowIndexes(IndexSet(integer: i), byExtendingSelection: false)
            selectedPartition = scanResult.partitions[i]
        }
        refreshInspect()
    }

    @objc private func openFinder() {
        guard let p = selectedPartition, p.mounted else { return }
        NSWorkspace.shared.open(URL(fileURLWithPath: p.mountPoint))
    }

    @objc private func loadCurrentTheme() {
        guard let p = selectedPartition, p.mounted else { return }
        let mount = p.mountPoint, dev = p.device
        runBusy("正在读取 EFI 上的当前主题…", {
            Result { try ThemeLibrary.shared.importCurrentTheme(mount: mount,
                                                                device: dev, name: nil) }
        }) { (result: Result<Theme, Error>) in
            switch result {
            case .success(let t):
                self.reloadLibrary(selectId: t.id)
                self.notify("已载入当前 OC 主题", "「\(t.name)」已加入主题库（只读复制，未修改 EFI）。")
            case .failure(let err):
                self.notify("读取失败", err.localizedDescription, critical: true)
            }
        }
    }

    // MARK: Apply / restore

    @objc private func confirmApply() {
        guard let t = selectedTheme, let p = selectedPartition, p.mounted else { return }
        guard !t.installList("image").isEmpty else {
            notify("主题还没有图片资源",
                   "「\(t.name)」是空白主题，写入后会清空目标变体目录却没有任何图标。\n请先用「✎ 编辑」添加背景图与启动项图标，再应用主题。",
                   critical: true)
            return
        }
        let variant = root.efi.variantField.stringValue.trimmingCharacters(in: .whitespaces)
        var notes: [String] = []
        if let i = try? EFIInspect.inspect(mount: p.mountPoint) {
            if !i.canopyInConfig || !i.canopyDriverFile {
                notes.append("⚠️ OpenCanopy.efi 未在 UEFI → Drivers 启用或文件缺失，图形菜单不会加载。")
            }
            if !i.imageVariantPresent {
                notes.append("⚠️ 当前 PickerVariant 指向的目录不存在——这正是文字菜单的原因，本次写入会重建它。")
            }
        }
        let diag = notes.isEmpty ? "" : "\n\n体检提示：\n" + notes.joined(separator: "\n")
        let text = """
        即将把「\(t.name)」写入 \(p.device)（\(p.mountPoint)）的 EFI/OC/Resources。

        图标会放进 PickerVariant 对应的变体目录，并同步写入 config.plist（反斜杠 UEFI 路径）。
        写入前会自动备份现有 Resources 与 config.plist；如出现问题可在「备份 / 恢复」中精确还原。
        此操作需要 macOS 管理员密码，并会修改引导分区。
        """ + diag
        confirm("确认写入 EFI", text, ok: "写入主题", danger: true) {
            self.runBusy("正在写入 EFI（可能需要管理员授权）…", {
                EFIActions.apply(theme: t, device: p.device, mount: p.mountPoint,
                                 replace: self.root.efi.replaceChk.state == .on,
                                 enablePicker: self.root.efi.pickerChk.state == .on,
                                 variant: variant)
            }) { (r: ActionResult) in
                self.reloadBackups()
                self.refreshInspect()
                if r.ok {
                    self.notify("应用成功", r.message + "\n备份编号：" + r.backupId)
                } else {
                    self.notify("应用失败", r.message +
                        (r.backupId.isEmpty ? "" : "\n已保留备份：" + r.backupId), critical: true)
                }
            }
        }
    }

    private func reloadBackups() {
        backups = EFIActions.listBackups()
        let e = root.efi
        e.backupTable.reloadData()
        e.backupSection.stringValue = "备份 / 恢复 · \(backups.count)"
        let empty = backups.isEmpty
        e.backupHint.isHidden = !empty
        // The right column is a scrollable form. Without backups, hide the empty
        // list and its restore button so the whole column fits on screen; when
        // backups exist, reveal them and scroll the form to the backup area.
        e.backupScroll.isHidden = empty
        e.restoreBtn.isHidden = empty
        e.form.doc.needsLayout = true
        if selectedBackup == nil, let first = backups.first {
            selectedBackup = first
            root.efi.backupTable.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        }
        updateApplyButton()
        DispatchQueue.main.async {
            let form = e.form
            let y: CGFloat = empty ? 0 : max(0, form.doc.frame.height - form.contentSize.height)
            form.contentView.scroll(to: NSPoint(x: 0, y: y))
            form.reflectScrolledClipView(form.contentView)
        }
    }

    @objc private func confirmRestore() {
        guard let b = selectedBackup, let p = selectedPartition, p.mounted else { return }
        confirm("恢复备份", "将用「\(b.theme)」（\(b.time)）精确还原 \(p.device) 的 Resources 与 config.plist。\n\n恢复前会自动为当前状态再生成一份快照。",
                ok: "恢复", danger: true) {
            let bid = b.id, dev = p.device, mount = p.mountPoint
            self.runBusy("正在恢复备份…", {
                EFIActions.restore(backupId: bid, device: dev, mount: mount)
            }) { (r: ActionResult) in
                self.reloadBackups()
                self.refreshInspect()
                if r.ok { self.notify("恢复成功", r.message) }
                else { self.notify("恢复失败", r.message, critical: true) }
            }
        }
    }

    // MARK: Help

    @objc func showHelp() {
        let a = NSAlert()
        a.messageText = "OC Theme Studio · 原生 Swift 版"
        a.informativeText = """
        1. 导入主题：左侧「＋ 导入主题包」选择 ZIP 或文件夹；也可以直接把 ZIP / 文件夹拖进窗口（或拖到 Dock 的应用图标上）安装。支持 EFI/OC/Resources、多变体 PickerVariant、Windows 反斜杠打包的 ZIP，一次可拖多个。

        2. 主题管理：左栏第二行是「重命名 / 修复目录 / 识别启动项」，第三行是「转 ICNS / 更多」；右键任意主题也会弹出同样的菜单。「－ 删除」只删本机副本。

        3. 新建主题：点「＋ 新建」，输入名称后可选「标准启动项 / 极简四图标 / 多发行版」等预设，直接生成真实图标与背景，无需再手动拖图标；选「空白主题」则从零开始。

        4. 修复主题目录：把误拖进来的嵌套 Resources 目录摊平到主题根目录，重建 manifest 索引，移除指向缺失文件的元素，并修正被压扁 / 越界的旧默认排版。

        5. 识别系统启动项：扫描当前系统卷、已挂载分区和 EFI 分区里已有的启动加载器（macOS / Windows / 各 Linux 发行版），勾选后一键加入当前主题，自动补齐图标与标签。

        6. 主题编辑器：可改名、设置 PickerVariant、添加 / 替换 / 删除资源、查看图片尺寸、改启动项预览名、导出 ZIP、另存副本。所有改动会重建安装清单，应用主题时真实写入 EFI。

        7. 图片转 ICNS：左栏「⇄ 转 ICNS」或文件菜单打开；把 JPG / PNG 拖进去（也可直接拖到 Dock 图标），选图标 / 背景 / 原尺寸规格，实时预览后可保存 .icns，或在编辑器里直接加入主题 / 替换选中资源。生成的是 ic07(1x)+ic13(2x) 的真实 OpenCore 格式，不是 macOS 应用图标。

        8. 可视化设计：选中主题后点预览区右上「✎ 可视化设计」（或文件菜单 ⌘D）。画布上可随意拖动元素并自动吸附网格 / 居中 / 相邻元素；拖八个白点缩放；双击文字就地编辑、双击图标换图；右键可替换资源、改字体与颜色、加粗、对齐、层级、隐藏、删除；右侧检查器可改字号 / 字体 / 颜色 / 对齐 / 不透明度，并可「替换主题字体文件」（.ttf / .otf / .ttc 直接嵌入主题）。设计坐标保存在 manifest 的 layout 字段，主窗口预览实时同步。

        9. 预览：中间是真实 OpenCanopy Boot Picker 渲染，点击图标可切换选中项。

        10. 挂载与应用：右侧选分区 →「挂载」→「应用主题到 EFI」。自动备份 Resources 与 config.plist；「恢复选中备份」先清空再整体还原。

        注意：OpenCanopy 菜单上的真实文字来自 Label 目录的 .lbl / .l2x 位图，编辑器里的显示名用于本软件预览。

        数据位置：~/Library/Application Support/OCThemeStudio
        本应用不依赖 Python、浏览器或本地 HTTP 服务。
        """
        a.alertStyle = .informational
        a.addButton(withTitle: "知道了")
        if let w = window { a.beginSheetModal(for: w, completionHandler: nil) }
        else { a.runModal() }
    }
}
