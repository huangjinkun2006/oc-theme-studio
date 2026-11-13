import AppKit

// MARK: - Small factory helpers

enum UI {
    static func label(_ text: String, size: CGFloat = 12,
                      weight: NSFont.Weight = .regular,
                      color: NSColor = .labelColor,
                      align: NSTextAlignment = .left) -> NSTextField {
        let f = NSTextField(labelWithString: text)
        f.font = .systemFont(ofSize: size, weight: weight)
        f.textColor = color
        f.alignment = align
        f.lineBreakMode = .byTruncatingTail
        f.isSelectable = false
        return f
    }

    static func section(_ text: String) -> NSTextField {
        label(text.uppercased(), size: 10.5, weight: .semibold, color: .secondaryLabelColor)
    }

    static func button(_ title: String, height: CGFloat = 28,
                       accent: Bool = false) -> NSButton {
        let b = NSButton(title: title, target: nil, action: nil)
        b.bezelStyle = .rounded
        b.font = .systemFont(ofSize: 12, weight: accent ? .semibold : .regular)
        b.frame.size.height = height
        if accent {
            b.bezelColor = .controlAccentColor
            b.contentTintColor = .white
            b.keyEquivalent = "\r"
        }
        return b
    }

    static func checkbox(_ title: String, on: Bool = true) -> NSButton {
        let b = NSButton(checkboxWithTitle: title, target: nil, action: nil)
        b.state = on ? .on : .off
        b.font = .systemFont(ofSize: 11.5)
        b.frame.size.height = 20
        return b
    }

    static func field(_ placeholder: String, value: String = "") -> NSTextField {
        let f = NSTextField(string: value)
        f.placeholderString = placeholder
        f.font = .systemFont(ofSize: 12)
        f.bezelStyle = .roundedBezel
        f.frame.size.height = 24
        return f
    }

    static func card(title: String? = nil) -> NSBox {
        let box = NSBox()
        box.boxType = .custom
        box.fillColor = .controlBackgroundColor
        box.borderColor = .separatorColor
        box.borderWidth = 1
        box.cornerRadius = 8
        box.title = title ?? ""
        box.titlePosition = .noTitle
        return box
    }

    static func hLine() -> NSView {
        let v = NSView()
        v.wantsLayer = true
        v.layer?.backgroundColor = NSColor.separatorColor.cgColor
        v.frame.size.height = 1
        return v
    }

    static func badge(_ text: String, color: NSColor) -> NSTextField {
        let f = label(text, size: 10, weight: .semibold, color: color, align: .center)
        f.wantsLayer = true
        f.layer?.backgroundColor = color.withAlphaComponent(0.14).cgColor
        f.layer?.cornerRadius = 4
        return f
    }
}

// MARK: - A simple top-down document view for scrollable forms

final class FormDocView: NSView {
    override var isFlipped: Bool { true }
    var spacing: CGFloat = 8
    var padding: CGFloat = 14
    private var laying = false

    /// Register a subview with an explicit height.
    func add(_ view: NSView, height: CGFloat) {
        view.frame = NSRect(x: 0, y: 0, width: 100, height: height)
        addSubview(view)
    }

    override func layout() {
        super.layout()
        guard !laying else { return }
        laying = true
        defer { laying = false }
        let w = bounds.width
        var y = padding
        for v in subviews where !v.isHidden {
            let h = v.frame.height
            v.frame = NSRect(x: padding, y: y, width: max(10, w - padding * 2), height: h)
            y += h + spacing
        }
        let minH = enclosingScrollView?.contentSize.height ?? 0
        let needed = max(y + padding, minH)
        if abs(frame.height - needed) > 0.5 {
            setFrameSize(NSSize(width: frame.width, height: needed))
        }
    }
}

/// NSScrollView whose document view is a FormDocView with a fixed width.
final class FormScroll: NSScrollView {
    let doc = FormDocView()
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        drawsBackground = false
        hasVerticalScroller = true
        hasHorizontalScroller = false
        automaticallyAdjustsContentInsets = false
        contentInsets = NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
        documentView = doc
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) unsupported") }

    override func layout() {
        super.layout()
        let w = contentSize.width
        if abs(doc.frame.width - w) > 0.5 {
            doc.setFrameSize(NSSize(width: w, height: doc.frame.height))
        }
        doc.needsLayout = true
    }
}

// MARK: - Table rows

final class ThemeRowView: NSTableCellView {
    override var isFlipped: Bool { true }
    private let thumb = NSImageView()
    private let nameF = UI.label("", size: 12.5, weight: .semibold)
    private let metaF = UI.label("", size: 10.5, color: .secondaryLabelColor)
    private let tagF = UI.label("", size: 9.5, weight: .semibold)

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        addSubview(thumb)
        addSubview(nameF)
        addSubview(metaF)
        addSubview(tagF)
        thumb.imageScaling = .scaleProportionallyUpOrDown
        thumb.wantsLayer = true
        thumb.layer?.cornerRadius = 5
        thumb.layer?.masksToBounds = true
        tagF.wantsLayer = true
        tagF.layer?.cornerRadius = 3
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) unsupported") }

    func configure(_ t: Theme) {
        thumb.image = t.backgroundImage ?? t.icons.first.flatMap { t.image($0.path) }
        nameF.stringValue = t.name
        let stat = "\(t.icons.count) 个图标 · \(t.fileCount) 文件 · \(t.sizeText)"
        metaF.stringValue = stat
        if !t.tag.isEmpty {
            tagF.isHidden = false
            tagF.stringValue = " " + t.tag + " "
            let c: NSColor = t.fromEfi ? .systemOrange : t.real ? .systemGreen : .systemGray
            tagF.textColor = c
            tagF.layer?.backgroundColor = c.withAlphaComponent(0.16).cgColor
        } else {
            tagF.isHidden = true
        }
    }

    override func layout() {
        super.layout()
        let pad: CGFloat = 10
        thumb.frame = NSRect(x: pad, y: 8, width: 46, height: 46)
        let x = pad + 46 + 10
        let w = bounds.width - x - pad
        nameF.frame = NSRect(x: x, y: 9, width: w, height: 17)
        tagF.frame = NSRect(x: x, y: 28, width: min(70, w), height: 14)
        metaF.frame = NSRect(x: x, y: 43, width: w, height: 14)
    }
}

final class EFIRowView: NSTableCellView {
    override var isFlipped: Bool { true }
    private let nameF = UI.label("", size: 12, weight: .semibold)
    private let subF = UI.label("", size: 10.5, color: .secondaryLabelColor)
    private let badgesF = UI.label("", size: 10, weight: .medium)

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        addSubview(nameF); addSubview(subF); addSubview(badgesF)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) unsupported") }

    func configure(_ p: EFIPartition) {
        nameF.stringValue = p.device + (p.current ? "  ★" : "")
        nameF.textColor = p.current ? .controlAccentColor : .labelColor
        subF.stringValue = "\(p.volumeName.isEmpty ? "EFI 分区" : p.volumeName) · \(p.sizeText)" +
                           (p.mounted ? " · 已挂载" : " · 未挂载")
        var tags: [String] = []
        if p.sameDisk { tags.append("系统盘") }
        if p.hasConfig { tags.append("含 OC 配置") }
        else if p.hasOC { tags.append("含 OC") }
        if p.mounted { tags.append("已挂载") }
        badgesF.stringValue = tags.joined(separator: "  ·  ")
        badgesF.textColor = p.hasConfig ? .systemGreen : .secondaryLabelColor
    }

    override func layout() {
        super.layout()
        let pad: CGFloat = 10
        let w = bounds.width - pad * 2
        nameF.frame = NSRect(x: pad, y: 5, width: w, height: 16)
        subF.frame = NSRect(x: pad, y: 22, width: w, height: 14)
        badgesF.frame = NSRect(x: pad, y: 37, width: w, height: 13)
    }
}

final class BackupRowView: NSTableCellView {
    override var isFlipped: Bool { true }
    private let nameF = UI.label("", size: 11.5, weight: .medium)
    private let subF = UI.label("", size: 10, color: .secondaryLabelColor)

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        addSubview(nameF); addSubview(subF)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) unsupported") }

    func configure(_ b: BackupItem) {
        nameF.stringValue = b.theme
        subF.stringValue = "\(b.time) · \(b.device) · \(b.sizeText)"
    }

    override func layout() {
        super.layout()
        let w = bounds.width - 20
        nameF.frame = NSRect(x: 10, y: 4, width: w, height: 16)
        subF.frame = NSRect(x: 10, y: 21, width: w, height: 14)
    }
}

// MARK: - Table construction

func makeTable(rowHeight: CGFloat) -> (NSScrollView, NSTableView) {
    let table = NSTableView()
    let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("main"))
    col.isEditable = false
    table.addTableColumn(col)
    table.headerView = nil
    table.rowHeight = rowHeight
    table.backgroundColor = .clear
    table.selectionHighlightStyle = .regular
    table.style = .plain
    table.intercellSpacing = NSSize(width: 0, height: 0)
    let scroll = NSScrollView()
    scroll.drawsBackground = false
    scroll.hasVerticalScroller = true
    scroll.documentView = table
    scroll.wantsLayer = true
    scroll.layer?.cornerRadius = 7
    return (scroll, table)
}
