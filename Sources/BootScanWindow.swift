import AppKit

// MARK: - Root view

final class BootScanRootView: NSView {
    override var isFlipped: Bool { true }

    let title = UI.label("", size: 14, weight: .semibold)
    let subtitle = UI.label("", size: 11, color: .secondaryLabelColor)
    let scroll: NSScrollView
    let table: NSTableView
    let status = UI.label("", size: 10.5, color: .secondaryLabelColor)
    let rescanBtn = UI.button("重新扫描", height: 28)
    let allBtn = UI.button("全选 / 全不选", height: 28)
    let addBtn = UI.button("加入当前主题", height: 28, accent: true)
    let closeBtn = UI.button("关闭", height: 28)
    let line = UI.hLine()

    override init(frame frameRect: NSRect) {
        let pair = makeTable(rowHeight: 46)
        scroll = pair.0
        table = pair.1
        super.init(frame: frameRect)
        for v in [title, subtitle, scroll, status, rescanBtn, allBtn, addBtn,
                  closeBtn, line] as [NSView] {
            addSubview(v)
        }
        subtitle.maximumNumberOfLines = 2
        subtitle.lineBreakMode = .byWordWrapping
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) unsupported") }

    override func layout() {
        super.layout()
        let pad: CGFloat = 16
        let w = bounds.width - pad * 2
        title.frame = NSRect(x: pad, y: 14, width: w, height: 20)
        subtitle.frame = NSRect(x: pad, y: 36, width: w, height: 32)
        line.frame = NSRect(x: pad, y: 74, width: w, height: 1)

        let by = bounds.height - 44
        closeBtn.frame = NSRect(x: bounds.width - pad - 74, y: by, width: 74, height: 28)
        addBtn.frame = NSRect(x: closeBtn.frame.minX - 8 - 116, y: by, width: 116, height: 28)
        allBtn.frame = NSRect(x: pad, y: by, width: 112, height: 28)
        rescanBtn.frame = NSRect(x: allBtn.frame.maxX + 8, y: by, width: 92, height: 28)
        let sx = rescanBtn.frame.maxX + 12
        status.frame = NSRect(x: sx, y: by + 4,
                              width: max(60, addBtn.frame.minX - 8 - sx), height: 20)

        scroll.frame = NSRect(x: pad - 2, y: 82, width: w + 4,
                              height: max(80, by - 8 - 82))
    }
}

// MARK: - Controller

final class BootScanWindowController: NSWindowController,
        NSTableViewDataSource, NSTableViewDelegate, NSWindowDelegate {

    private var root: BootScanRootView { window!.contentView as! BootScanRootView }
    private let rowID = NSUserInterfaceItemIdentifier("BootScanRow")
    private var theme: Theme?
    private var themeId = ""
    private var entries: [DetectedEntry] = []
    private var picked = Set<Int>()
    private var scanning = false
    private var onApplied: ((String) -> Void)?
    var onClose: (() -> Void)?

    convenience init(theme: Theme, applied: @escaping (String) -> Void) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 540),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered, defer: false)
        window.title = "识别系统启动项 · \(theme.name)"
        window.minSize = NSSize(width: 520, height: 400)
        window.center()
        window.setFrameAutosaveName("OCThemeStudioBootScan")
        self.init(window: window)
        self.theme = theme
        self.themeId = theme.id
        self.onApplied = applied
        let size = window.contentRect(forFrameRect: window.frame).size
        window.contentView = BootScanRootView(frame: NSRect(origin: .zero, size: size))
        window.delegate = self
        setup()
    }

    private func setup() {
        let r = root
        r.title.stringValue = "把系统里已有的启动项加入「\(theme?.name ?? "主题")」"
        r.subtitle.stringValue =
            "扫描当前系统卷、已挂载分区与 EFI 分区中的启动加载器。"
            + "Windows / Linux 分区若未挂载，可能识别不到——可先回主窗口右侧挂载 EFI 再扫描。"
        let table = r.table
        table.dataSource = self
        table.delegate = self
        // makeTable() ships a default column; replace it with our own.
        for c in table.tableColumns { table.removeTableColumn(c) }
        let c0 = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("pick"))
        c0.width = 34
        let c1 = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("info"))
        c1.width = 520
        table.addTableColumn(c0)
        table.addTableColumn(c1)
        table.headerView = nil
        table.rowHeight = 46
        table.selectionHighlightStyle = .none
        r.rescanBtn.target = self
        r.rescanBtn.action = #selector(rescan)
        r.allBtn.target = self
        r.allBtn.action = #selector(toggleAll)
        r.addBtn.target = self
        r.addBtn.action = #selector(applyEntries)
        r.closeBtn.target = self
        r.closeBtn.action = #selector(closeWindow)
        rescan()
    }

    @objc private func closeWindow() { window?.close() }

    @objc func rescan() {
        guard !scanning else { return }
        scanning = true
        root.status.stringValue = "正在扫描…"
        root.rescanBtn.isEnabled = false
        root.addBtn.isEnabled = false
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let found = BootScanner.detect()
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.scanning = false
                self.root.rescanBtn.isEnabled = true
                self.entries = found
                self.picked = Set(found.indices)
                self.root.table.reloadData()
                self.updateStatus()
            }
        }
    }

    private func updateStatus() {
        let n = entries.count, m = picked.count
        if n == 0 {
            root.status.stringValue = "未发现启动项"
            root.addBtn.isEnabled = false
            root.subtitle.stringValue =
                "没有扫描到可识别的启动项。若 Windows / Linux 分区未挂载，"
                + "请先在主窗口右侧挂载 EFI，再点「重新扫描」。"
        } else {
            root.status.stringValue = "发现 \(n) 个 · 已选 \(m) 个"
            root.addBtn.isEnabled = m > 0
        }
    }

    @objc private func togglePick(_ sender: NSButton) {
        let row = sender.tag
        guard row >= 0 && row < entries.count else { return }
        if sender.state == .on { picked.insert(row) } else { picked.remove(row) }
        updateStatus()
    }

    @objc private func toggleAll() {
        if picked.count == entries.count { picked.removeAll() }
        else { picked = Set(entries.indices) }
        root.table.reloadData()
        updateStatus()
    }

    @objc private func applyEntries() {
        let chosen = picked.sorted().compactMap { $0 < entries.count ? entries[$0] : nil }
        guard !chosen.isEmpty, let target = theme else { return }
        root.addBtn.isEnabled = false
        root.status.stringValue = "正在加入…"
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            let result: Result<BootAddResult, Error>
            do { result = .success(try addBootEntries(chosen, to: target)) }
            catch { result = .failure(error) }
            DispatchQueue.main.async {
                self.root.addBtn.isEnabled = true
                switch result {
                case .success(let r):
                    self.onApplied?(self.themeId)
                    self.root.status.stringValue = "已加入 \(r.added) 个启动项"
                    let a = NSAlert()
                    a.messageText = "已加入 \(r.added) 个启动项"
                    a.informativeText = r.layoutUpdated
                        ? "图标与标签已写入主题，默认排版已刷新，回到主窗口即可看到。"
                        : "图标与标签已写入主题。当前是自定义排版，点「恢复默认排版」可让新图标出现在画布上。"
                    a.addButton(withTitle: "好")
                    if let w = self.window { a.beginSheetModal(for: w, completionHandler: nil) }
                    else { a.runModal() }
                case .failure(let e):
                    self.root.status.stringValue = "加入失败"
                    let a = NSAlert()
                    a.messageText = "加入失败"
                    a.informativeText = e.localizedDescription
                    a.addButton(withTitle: "好")
                    if let w = self.window { a.beginSheetModal(for: w, completionHandler: nil) }
                    else { a.runModal() }
                }
            }
        }
    }

    func windowWillClose(_ notification: Notification) {
        DispatchQueue.main.async { [weak self] in self?.onClose?() }
    }

    // MARK: Table

    func numberOfRows(in tableView: NSTableView) -> Int { entries.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard row < entries.count else { return nil }
        let e = entries[row]
        if tableColumn?.identifier.rawValue == "pick" {
            let btn = NSButton(checkboxWithTitle: "", target: self,
                               action: #selector(togglePick(_:)))
            btn.tag = row
            btn.state = picked.contains(row) ? .on : .off
            let holder = NSView()
            btn.frame = NSRect(x: 4, y: 13, width: 22, height: 22)
            holder.addSubview(btn)
            return holder
        }
        let v = (tableView.makeView(withIdentifier: rowID, owner: self) as? BootRowView)
            ?? BootRowView()
        v.identifier = rowID
        v.configure(e)
        return v
    }
}

final class BootRowView: NSTableCellView {
    override var isFlipped: Bool { true }
    private let name = UI.label("", size: 12.5, weight: .semibold)
    private let detail = UI.label("", size: 10.5, color: .secondaryLabelColor)
    private let kind = UI.badge("", color: .systemBlue)

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        for v in [name, detail, kind] as [NSView] { addSubview(v) }
        detail.lineBreakMode = .byTruncatingMiddle
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) unsupported") }

    func configure(_ e: DetectedEntry) {
        name.stringValue = e.name
        detail.stringValue = e.detail
        kind.stringValue = e.kind
        let c: NSColor = e.kind == "macOS" ? .systemBlue
            : e.kind == "Windows" ? .systemTeal
            : e.kind == "Linux" ? .systemOrange : .systemGray
        kind.textColor = c
        kind.layer?.backgroundColor = c.withAlphaComponent(0.14).cgColor
        needsLayout = true
    }

    override func layout() {
        super.layout()
        let pad: CGFloat = 6
        let kw = max(52, kind.fittingSize.width)
        kind.frame = NSRect(x: bounds.width - kw - 4, y: 6, width: kw, height: 18)
        name.frame = NSRect(x: pad, y: 5, width: max(40, bounds.width - kw - pad - 12),
                            height: 18)
        detail.frame = NSRect(x: pad, y: 24, width: max(40, bounds.width - pad - 8),
                              height: 16)
    }
}
