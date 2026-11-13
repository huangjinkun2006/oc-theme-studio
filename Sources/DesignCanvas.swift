import AppKit

// MARK: - Handles

private enum ResizeHandle: Int, CaseIterable {
    case nw, n, ne, e, se, s, sw, w
}

// MARK: - Canvas

/// Direct-manipulation canvas: drag to move, drag handles to resize, snap to
/// grid / centre / neighbouring elements, double click to edit text, right
/// click for the context menu.
final class DesignCanvasView: NSView, NSTextFieldDelegate {
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    var theme: Theme? { didSet { needsDisplay = true } }
    var layout = ThemeLayout() { didSet { needsDisplay = true } }
    var selectedId: String? { didSet { needsDisplay = true } }

    var onChange: (() -> Void)?
    var onSelect: ((DesignElement?) -> Void)?
    var onReplaceAsset: ((DesignElement) -> Void)?
    var onFontFile: (() -> Void)?
    var onAddText: (() -> Void)?
    var onAddImage: (() -> Void)?
    var onFontStyle: ((DesignElement) -> Void)?
    var onResetAll: (() -> Void)?
    var onStatus: ((String) -> Void)?

    private var dragState: (id: String, start: NSPoint, origin: CGRect, handle: ResizeHandle?)?
    private var guides: [(vertical: Bool, at: Double)] = []
    private var inlineEditor: NSTextField?
    private var inlineId: String?
    private var inlineOriginal = ""

    private let handleSize: CGFloat = 9

    // MARK: Geometry

    func screenRect() -> NSRect {
        let avail = bounds.insetBy(dx: 24, dy: 24)
        let a = CGFloat(max(0.6, min(3.0, layout.aspect)))
        var w = avail.width, h = w / a
        if h > avail.height { h = avail.height; w = h * a }
        return NSRect(x: bounds.midX - w / 2, y: bounds.midY - h / 2,
                      width: w, height: h)
    }

    private func rect(_ e: DesignElement, in s: NSRect) -> NSRect {
        NSRect(x: s.minX + CGFloat(e.x) * s.width,
               y: s.minY + CGFloat(e.y) * s.height,
               width: CGFloat(e.w) * s.width, height: CGFloat(e.h) * s.height)
    }

    private func element(_ id: String) -> DesignElement? {
        layout.elements.first { $0.id == id }
    }
    private func index(_ id: String) -> Int? {
        layout.elements.firstIndex { $0.id == id }
    }

    private func handleRects(_ r: NSRect) -> [(ResizeHandle, NSRect)] {
        let q = handleSize
        let pts: [(ResizeHandle, NSPoint)] = [
            (.nw, NSPoint(x: r.minX, y: r.minY)), (.n, NSPoint(x: r.midX, y: r.minY)),
            (.ne, NSPoint(x: r.maxX, y: r.minY)), (.e, NSPoint(x: r.maxX, y: r.midY)),
            (.se, NSPoint(x: r.maxX, y: r.maxY)), (.s, NSPoint(x: r.midX, y: r.maxY)),
            (.sw, NSPoint(x: r.minX, y: r.maxY)), (.w, NSPoint(x: r.minX, y: r.midY)),
        ]
        return pts.map { ($0.0, NSRect(x: $0.1.x - q / 2, y: $0.1.y - q / 2,
                                      width: q, height: q)) }
    }

    private func handle(at p: NSPoint, for r: NSRect) -> ResizeHandle? {
        handleRects(r).first { $0.1.insetBy(dx: -3, dy: -3).contains(p) }?.0
    }

    private func hit(_ p: NSPoint, in s: NSRect) -> DesignElement? {
        for e in layout.elements.reversed() where !e.hidden {
            if rect(e, in: s).insetBy(dx: -2, dy: -2).contains(p) { return e }
        }
        return nil
    }

    // MARK: Drawing

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        NSColor(calibratedWhite: 0.10, alpha: 1).setFill()
        bounds.fill()

        let s = screenRect()
        let path = NSBezierPath(roundedRect: s, xRadius: 8, yRadius: 8)
        NSGraphicsContext.saveGraphicsState()
        path.addClip()
        DesignRenderer.drawScreen(layout, theme: theme, themeDir: theme?.dir, in: s)
        if layout.snap { drawGrid(in: s) }
        drawGuides(in: s)
        NSGraphicsContext.restoreGraphicsState()

        NSColor(calibratedWhite: 1, alpha: 0.22).setStroke()
        path.lineWidth = 1
        path.stroke()

        if let id = selectedId, let e = element(id) {
            let r = rect(e, in: s)
            NSColor.controlAccentColor.setStroke()
            let outline = NSBezierPath(rect: r)
            outline.lineWidth = 1.5
            outline.setLineDash([5, 4], count: 2, phase: 0)
            outline.stroke()
            NSColor.white.setFill()
            NSColor.controlAccentColor.setStroke()
            for (_, hr) in handleRects(r) {
                NSBezierPath(rect: hr).fill()
                NSBezierPath(rect: hr).stroke()
            }
        }

        let hint = "拖动漫游 · 拖白点缩放 · 双击改文字 / 换图 · 右键更多"
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 10.5, weight: .medium),
            .foregroundColor: NSColor.white.withAlphaComponent(0.9),
        ]
        let sz = (hint as NSString).size(withAttributes: attrs)
        let box = NSRect(x: s.minX + 10, y: s.minY + 9,
                         width: min(sz.width + 16, s.width - 20), height: 20)
        NSColor(calibratedWhite: 0, alpha: 0.45).setFill()
        NSBezierPath(roundedRect: box, xRadius: 5, yRadius: 5).fill()
        (hint as NSString).draw(in: NSRect(x: box.minX + 8, y: box.minY + 3,
                                           width: box.width - 16, height: 14),
                                withAttributes: attrs)
    }

    private func drawGrid(in s: NSRect) {
        let step = max(4, s.width * CGFloat(layout.grid) / 1280)
        NSColor(calibratedWhite: 1, alpha: 0.055).setStroke()
        let g = NSBezierPath()
        g.lineWidth = 0.5
        var x = s.minX + step
        while x < s.maxX { g.move(to: NSPoint(x: x, y: s.minY)); g.line(to: NSPoint(x: x, y: s.maxY)); x += step }
        var y = s.minY + step
        while y < s.maxY { g.move(to: NSPoint(x: s.minX, y: y)); g.line(to: NSPoint(x: s.maxX, y: y)); y += step }
        g.stroke()
    }

    private func drawGuides(in s: NSRect) {
        guard !guides.isEmpty else { return }
        NSColor.systemPink.withAlphaComponent(0.9).setStroke()
        let p = NSBezierPath()
        p.lineWidth = 1
        p.setLineDash([4, 3], count: 2, phase: 0)
        for g in guides {
            if g.vertical {
                let x = s.minX + CGFloat(g.at) * s.width
                p.move(to: NSPoint(x: x, y: s.minY)); p.line(to: NSPoint(x: x, y: s.maxY))
            } else {
                let y = s.minY + CGFloat(g.at) * s.height
                p.move(to: NSPoint(x: s.minX, y: y)); p.line(to: NSPoint(x: s.maxX, y: y))
            }
        }
        p.stroke()
    }

    // MARK: Mouse

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        commitInline()
        let p = convert(event.locationInWindow, from: nil)
        let s = screenRect()

        if let id = selectedId, let e = element(id),
           let h = handle(at: p, for: rect(e, in: s)) {
            dragState = (id, p, e.frame, h)
            return
        }
        if let e = hit(p, in: s) {
            selectedId = e.id
            onSelect?(e)
            if event.clickCount >= 2 {
                dragState = nil
                if e.kind == .text { beginInline(e, in: s) }
                else { onReplaceAsset?(e) }
                return
            }
            dragState = (e.id, p, e.frame, nil)
            return
        }
        selectedId = nil
        onSelect?(nil)
        dragState = nil
    }

    override func mouseDragged(with event: NSEvent) {
        guard let d = dragState else { return }
        let p = convert(event.locationInWindow, from: nil)
        let s = screenRect()
        let dx = Double((p.x - d.start.x) / s.width)
        let dy = Double((p.y - d.start.y) / s.height)
        var f = d.origin
        if let h = d.handle { resize(&f, h, dx: dx, dy: dy) }
        else { f.origin.x += dx; f.origin.y += dy }
        snap(&f, excluding: d.id)
        clamp(&f)
        if let i = index(d.id) { layout.elements[i].frame = f }
        needsDisplay = true
        onStatus?(statusText(d.id))
    }

    override func mouseUp(with event: NSEvent) {
        guard dragState != nil else { return }
        dragState = nil
        guides = []
        needsDisplay = true
        onChange?()
        onStatus?("")
    }

    private func statusText(_ id: String) -> String {
        guard let e = element(id) else { return "" }
        return "\(e.kind.rawValue) · x \(Int(e.x * 1000) / 10)%  y \(Int(e.y * 1000) / 10)%  " +
               "w \(Int(e.w * 1000) / 10)%  h \(Int(e.h * 1000) / 10)%"
    }

    private func resize(_ f: inout CGRect, _ h: ResizeHandle, dx: Double, dy: Double) {
        let minW = 0.012, minH = 0.02
        var x = f.origin.x, y = f.origin.y, w = f.width, hh = f.height
        if h == .nw || h == .w || h == .sw {
            x += dx; w -= dx
            if w < minW { x -= (minW - w); w = minW }
        }
        if h == .ne || h == .e || h == .se {
            w += dx
            if w < minW { w = minW }
        }
        if h == .nw || h == .n || h == .ne {
            y += dy; hh -= dy
            if hh < minH { y -= (minH - hh); hh = minH }
        }
        if h == .sw || h == .s || h == .se {
            hh += dy
            if hh < minH { hh = minH }
        }
        f = CGRect(x: x, y: y, width: w, height: hh)
    }

    private func clamp(_ f: inout CGRect) {
        let maxW = 1.0 - f.origin.x
        f.size.width = min(max(f.size.width, 0.012), max(min(1.0, maxW), 0.012))
        let maxH = 1.0 - f.origin.y
        f.size.height = min(max(f.size.height, 0.02), max(min(1.0, maxH), 0.02))
        f.origin.x = min(max(f.origin.x, 0), 1 - f.size.width)
        f.origin.y = min(max(f.origin.y, 0), 1 - f.size.height)
    }

    /// Grid + centre + peer edge/centre alignment. The closest candidate wins.
    private struct SnapCandidate {
        let delta: Double
        let guide: Double?   // nil = plain grid snap, no guide line
    }

    private func snap(_ f: inout CGRect, excluding id: String) {
        guides = []
        guard layout.snap else { return }
        let gx = max(0.002, layout.grid / 1280)
        let gy = gx * layout.aspect
        let tolX = gx * 1.4, tolY = gy * 1.4

        func best(_ c: [SnapCandidate], _ tol: Double) -> SnapCandidate? {
            var pick: SnapCandidate?
            for x in c where abs(x.delta) < tol {
                if pick == nil || abs(x.delta) < abs(pick!.delta) { pick = x }
            }
            return pick
        }
        func grid(_ v: Double, _ step: Double) -> Double {
            (v / step).rounded() * step - v
        }

        var cx: [SnapCandidate] = [
            SnapCandidate(delta: grid(f.minX, gx), guide: nil),
            SnapCandidate(delta: grid(f.maxX, gx), guide: nil),
            SnapCandidate(delta: 0.5 - f.midX, guide: 0.5),
        ]
        var cy: [SnapCandidate] = [
            SnapCandidate(delta: grid(f.minY, gy), guide: nil),
            SnapCandidate(delta: grid(f.maxY, gy), guide: nil),
            SnapCandidate(delta: 0.5 - f.midY, guide: 0.5),
        ]
        // Alignment with every other visible element (edge & centre guides).
        for o in layout.elements where o.id != id && !o.hidden {
            let ox = [o.frame.minX, o.frame.midX, o.frame.maxX]
            let oy = [o.frame.minY, o.frame.midY, o.frame.maxY]
            let sx = [f.minX, f.midX, f.maxX]
            let sy = [f.minY, f.midY, f.maxY]
            for t in ox { for v in sx { cx.append(SnapCandidate(delta: t - v, guide: t)) } }
            for t in oy { for v in sy { cy.append(SnapCandidate(delta: t - v, guide: t)) } }
        }
        if let b = best(cx, tolX) {
            f.origin.x += b.delta
            if let g = b.guide { guides.append((true, g)) }
        }
        if let b = best(cy, tolY) {
            f.origin.y += b.delta
            if let g = b.guide { guides.append((false, g)) }
        }
        guides = guides.filter { $0.at >= 0 && $0.at <= 1 }
    }

    // MARK: Inline text editing

    private func beginInline(_ e: DesignElement, in s: NSRect) {
        let r = rect(e, in: s)
        let f = NSTextField(frame: NSRect(x: r.minX, y: r.minY,
                                          width: max(120, r.width),
                                          height: max(26, r.height)))
        f.stringValue = e.text
        f.font = NSFont.systemFont(ofSize: 13)
        f.bezelStyle = .roundedBezel
        f.backgroundColor = .textBackgroundColor
        f.textColor = .labelColor
        f.isEditable = true
        f.isSelectable = true
        f.target = self
        f.action = #selector(inlineDone(_:))
        f.delegate = self
        addSubview(f)
        inlineEditor = f
        inlineId = e.id
        inlineOriginal = e.text
        window?.makeFirstResponder(f)
        f.selectText(nil)
    }

    @objc private func inlineDone(_ sender: NSTextField) { commitInline() }

    func controlTextDidEndEditing(_ obj: Notification) { commitInline() }

    func control(_ control: NSControl, textView: NSTextView,
                 doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
            guard let f = inlineEditor, inlineId != nil else { return false }
            f.stringValue = inlineOriginal
            f.removeFromSuperview()
            inlineEditor = nil; inlineId = nil
            needsDisplay = true
            return true
        }
        return false
    }

    private func commitInline() {
        guard let f = inlineEditor, let id = inlineId else { return }
        let text = f.stringValue
        f.removeFromSuperview()
        inlineEditor = nil
        inlineId = nil
        update(id) { $0.text = text }
        onChange?()
    }

    // MARK: Right-click menu

    override func rightMouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        let s = screenRect()
        commitInline()
        if let e = hit(p, in: s) {
            selectedId = e.id
            onSelect?(e)
        } else {
            selectedId = nil
            onSelect?(nil)
        }
        let m = NSMenu()
        func add(_ title: String, _ sel: Selector, _ on: Bool = true) {
            let i = NSMenuItem(title: title, action: sel, keyEquivalent: "")
            i.target = self
            i.isEnabled = on
            m.addItem(i)
        }
        let e = selectedId.flatMap { element($0) }
        let isText = e?.kind == .text
        let hasAsset = e?.kind == .icon || e?.kind == .image || e?.kind == .selection
        if let e = e {
            add("替换图片资源…", #selector(menuReplaceAsset), hasAsset)
            add("编辑文字…", #selector(menuEditText), isText)
            add("字体与颜色…", #selector(menuFontStyle), isText)
            add("替换主题字体文件…", #selector(menuFontFile))
            m.addItem(.separator())
            add("加粗" + (e.bold ? " ✓" : ""), #selector(menuBold), isText)
            let align = NSMenuItem(title: "对齐", action: nil, keyEquivalent: "")
            let sub = NSMenu()
            for (title, value) in [("左对齐", "left"), ("居中", "center"), ("右对齐", "right")] {
                let it = NSMenuItem(title: (e.align == value ? "✓ " : "") + title,
                                    action: #selector(menuAlign(_:)), keyEquivalent: "")
                it.target = self
                it.representedObject = value
                sub.addItem(it)
            }
            align.submenu = sub
            m.addItem(align)
            m.addItem(.separator())
            add("置于顶层", #selector(menuFront))
            add("置于底层", #selector(menuBack))
            add(e.hidden ? "显示此元素" : "隐藏此元素（导出时不绘制）", #selector(menuHide))
            add("重置此元素位置与大小", #selector(menuResetOne))
            add("删除此元素", #selector(menuDelete))
            m.addItem(.separator())
        }
        add("＋ 新增文字", #selector(menuAddText))
        add("＋ 新增图片元素", #selector(menuAddImage))
        add(layout.snap ? "吸附：开（网格 / 居中 / 对齐）" : "吸附：关", #selector(menuSnap))
        add("恢复默认排版…", #selector(menuResetAll))
        NSMenu.popUpContextMenu(m, with: event, for: self)
    }

    @objc private func menuReplaceAsset() { selected().flatMap { onReplaceAsset?($0) } }
    @objc private func menuEditText() {
        guard let e = selected(), e.kind == .text else { return }
        beginInline(e, in: screenRect())
    }
    @objc private func menuFontStyle() { selected().flatMap { onFontStyle?($0) } }
    @objc private func menuFontFile() { onFontFile?() }
    @objc private func menuBold() {
        guard let e = selected(), e.kind == .text else { return }
        update(e.id) { $0.bold.toggle() }; onChange?()
    }
    @objc private func menuAlign(_ sender: NSMenuItem) {
        guard let e = selected(), let v = sender.representedObject as? String else { return }
        update(e.id) { $0.align = v }; onChange?()
    }
    @objc private func menuFront() {
        guard let id = selectedId, let i = index(id) else { return }
        let e = layout.elements.remove(at: i)
        layout.elements.append(e)
        onChange?()
    }
    @objc private func menuBack() {
        guard let id = selectedId, let i = index(id) else { return }
        let e = layout.elements.remove(at: i)
        layout.elements.insert(e, at: 0)
        onChange?()
    }
    @objc private func menuHide() {
        guard let e = selected() else { return }
        update(e.id) { $0.hidden.toggle() }; onChange?()
    }
    @objc private func menuResetOne() {
        guard let e = selected(), let t = theme else { return }
        if let d = ThemeLayout.defaults(for: t).elements.first(where: { $0.id == e.id }) {
            update(e.id) { $0.frame = d.frame }
            onChange?()
        }
    }
    @objc private func menuDelete() {
        guard let id = selectedId, let i = index(id) else { return }
        layout.elements.remove(at: i)
        selectedId = nil
        onSelect?(nil)
        onChange?()
    }
    @objc private func menuAddText() { onAddText?() }
    @objc private func menuAddImage() { onAddImage?() }
    @objc private func menuSnap() { layout.snap.toggle(); onChange?(); needsDisplay = true }
    @objc private func menuResetAll() { onResetAll?() }

    private func selected() -> DesignElement? { selectedId.flatMap { element($0) } }

    private func update(_ id: String, _ body: (inout DesignElement) -> Void) {
        guard let i = index(id) else { return }
        body(&layout.elements[i])
        needsDisplay = true
        onSelect?(layout.elements[i])
    }

    // MARK: Keyboard

    override func keyDown(with event: NSEvent) {
        guard let id = selectedId, index(id) != nil else {
            super.keyDown(with: event); return
        }
        let coarse: Double = event.modifierFlags.contains(.shift) ? 10 : 1
        let stepX = coarse / 1280
        let stepY = stepX * layout.aspect
        var dx: Double = 0, dy: Double = 0
        switch event.keyCode {
        case 123: dx = -stepX
        case 124: dx = stepX
        case 125: dy = stepY
        case 126: dy = -stepY
        case 51, 117:
            if let i = index(id) {
                layout.elements.remove(at: i)
                selectedId = nil
                onSelect?(nil)
                onChange?()
            }
            return
        default: super.keyDown(with: event); return
        }
        update(id) {
            $0.x += dx
            $0.y += dy
        }
        onChange?()
        onStatus?(statusText(id))
    }

    /// Programmatic hook used by the inspector and the build-validation probe.
    func apply(_ e: DesignElement) {
        guard let i = index(e.id) else { return }
        layout.elements[i] = e
        needsDisplay = true
        onChange?()
    }
}

// MARK: - Inspector

final class DesignInspectorView: NSView {
    override var isFlipped: Bool { true }

    let header = UI.section("元素属性")
    let kindLabel = UI.label("未选中元素", size: 12, weight: .semibold)
    let assetBtn = UI.button("替换图片资源…", height: 26)
    let textLabel = UI.label("文字内容", size: 10.5, color: .secondaryLabelColor)
    let textField = UI.field("双击画布可就地编辑文字")
    let fontLabel = UI.label("字体", size: 10.5, color: .secondaryLabelColor)
    let fontPop = NSPopUpButton(frame: .zero, pullsDown: false)
    let sizeLabel = UI.label("字号", size: 10.5, color: .secondaryLabelColor)
    let sizeField = UI.field("字号", value: "24")
    let sizeStep = NSStepper(frame: .zero)
    let boldChk = UI.checkbox("加粗", on: false)
    let colorLabel = UI.label("颜色", size: 10.5, color: .secondaryLabelColor)
    let colorWell = NSColorWell(frame: .zero)
    let alignLabel = UI.label("对齐", size: 10.5, color: .secondaryLabelColor)
    let alignCtrl = NSSegmentedControl(labels: ["左", "中", "右"],
                                       trackingMode: .selectOne,
                                       target: nil, action: nil)
    let opacityLabel = UI.label("不透明度", size: 10.5, color: .secondaryLabelColor)
    let opacitySlider = NSSlider(value: 1, minValue: 0.1, maxValue: 1,
                                 target: nil, action: nil)
    let hiddenChk = UI.checkbox("隐藏（不参与导出）", on: false)
    let line = UI.hLine()
    let snapChk = UI.checkbox("吸附到网格 / 居中 / 相邻元素", on: true)
    let gridLabel = UI.label("网格", size: 10.5, color: .secondaryLabelColor)
    let gridPop = NSPopUpButton(frame: .zero, pullsDown: false)
    let fontFileBtn = UI.button("替换主题字体文件…", height: 26)
    let addTextBtn = UI.button("＋ 新增文字", height: 26)
    let addImageBtn = UI.button("＋ 新增图片元素", height: 26)
    let hint = UI.label("", size: 10, color: .secondaryLabelColor)

    var current: DesignElement?
    var onUpdate: ((DesignElement) -> Void)?
    var onReplaceAsset: (() -> Void)?
    var onFontFile: (() -> Void)?
    var onAddText: (() -> Void)?
    var onAddImage: (() -> Void)?
    var onFontStyleFocus: (() -> Void)?
    var onSnapChange: ((Bool, Double) -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        layer?.cornerRadius = 8
        layer?.borderColor = NSColor.separatorColor.cgColor
        layer?.borderWidth = 1

        fontPop.addItems(withTitles: ["系统字体"] + DesignStyle.availableFamilies)
        fontPop.font = .systemFont(ofSize: 11)
        gridPop.addItems(withTitles: ["4", "8", "16", "32"])
        gridPop.selectItem(withTitle: "8")
        gridPop.font = .systemFont(ofSize: 11)
        alignCtrl.selectedSegment = 1
        alignCtrl.segmentStyle = .rounded
        alignCtrl.font = .systemFont(ofSize: 11)
        colorWell.color = .white
        textField.isContinuous = true
        textField.lineBreakMode = .byTruncatingTail
        sizeStep.minValue = 6
        sizeStep.maxValue = 160
        sizeStep.doubleValue = 24
        sizeStep.valueWraps = false
        sizeField.formatter = designNumberFormatter()
        hint.stringValue = """
        坐标 / 字体 / 颜色属于本软件的设计层，保存在主题 manifest 的 layout 字段，\
        用于预览与导出合成图。「替换图片」「替换字体文件」则是真实主题资源，\
        应用主题时会写入 EFI。OpenCanopy 自身按固定行排列图标，不读取坐标。
        """
        hint.lineBreakMode = .byWordWrapping
        hint.maximumNumberOfLines = 6

        let views: [NSView] = [header, kindLabel, assetBtn, textLabel, textField,
                               fontLabel, fontPop,
                               sizeLabel, sizeField, sizeStep, boldChk,
                               colorLabel, colorWell, alignLabel, alignCtrl,
                               opacityLabel, opacitySlider, hiddenChk, line,
                               snapChk, gridLabel, gridPop, fontFileBtn,
                               addTextBtn, addImageBtn, hint]
        for v in views { addSubview(v) }

        for (c, sel) in [(textField, #selector(propChanged)),
                         (fontPop, #selector(propChanged)),
                         (sizeField, #selector(propChanged)),
                         (sizeStep, #selector(stepChanged)),
                         (boldChk, #selector(propChanged)),
                         (colorWell, #selector(propChanged)),
                         (alignCtrl, #selector(propChanged)),
                         (opacitySlider, #selector(propChanged)),
                         (hiddenChk, #selector(propChanged)),
                         (snapChk, #selector(snapChanged)),
                         (gridPop, #selector(snapChanged))] as [(NSControl, Selector)] {
            c.target = self; c.action = sel
        }
        assetBtn.target = self; assetBtn.action = #selector(replaceAsset)
        fontFileBtn.target = self; fontFileBtn.action = #selector(fontFile)
        addTextBtn.target = self; addTextBtn.action = #selector(addText)
        addImageBtn.target = self; addImageBtn.action = #selector(addImage)
        configure(nil)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) unsupported") }

    private func designNumberFormatter() -> NumberFormatter {
        let f = NumberFormatter()
        f.minimum = 6; f.maximum = 160
        f.allowsFloats = false
        return f
    }

    func configure(_ e: DesignElement?) {
        current = e
        let text = e?.kind == .text
        let asset = e?.kind == .icon || e?.kind == .image || e?.kind == .selection
        kindLabel.stringValue = e == nil ? "未选中元素" :
            "\(kindTitle(e!.kind)) · \(e!.id.count > 22 ? String(e!.id.prefix(22)) + "…" : e!.id)"
        for c in [textField, fontPop, sizeField, sizeStep, boldChk, colorWell,
                  alignCtrl] as [NSControl] { c.isEnabled = text }
        // Opacity and visibility apply to every element kind.
        opacitySlider.isEnabled = e != nil
        hiddenChk.isEnabled = e != nil
        assetBtn.isEnabled = asset
        guard let e = e else { textField.stringValue = ""; return }
        // Do not stomp on the user's cursor while the inspector field is live.
        if textField.currentEditor() == nil { textField.stringValue = e.text }
        if e.fontFamily.isEmpty { fontPop.selectItem(at: 0) }
        else if let idx = DesignStyle.availableFamilies.firstIndex(of: e.fontFamily) {
            fontPop.selectItem(at: idx + 1)
        } else { fontPop.selectItem(at: 0) }
        sizeField.stringValue = String(Int(e.fontSize))
        sizeStep.doubleValue = e.fontSize
        boldChk.state = e.bold ? .on : .off
        colorWell.color = DesignStyle.color(e.colorHex)
        alignCtrl.selectedSegment = e.align == "left" ? 0 : e.align == "right" ? 2 : 1
        opacitySlider.doubleValue = e.opacity
        hiddenChk.state = e.hidden ? .on : .off
    }

    private func kindTitle(_ k: DesignKind) -> String {
        switch k {
        case .icon: return "启动项图标"
        case .image: return "图片元素"
        case .text: return "文字"
        case .selection: return "选中框"
        }
    }

    func configureSnap(_ snap: Bool, _ grid: Double) {
        snapChk.state = snap ? .on : .off
        gridPop.selectItem(withTitle: String(Int(grid)))
    }

    @objc private func propChanged() {
        guard var e = current else { return }
        if e.kind == .text {
            e.text = textField.stringValue
            if fontPop.indexOfSelectedItem > 0 {
                e.fontFamily = DesignStyle.availableFamilies[fontPop.indexOfSelectedItem - 1]
            } else { e.fontFamily = "" }
            e.fontSize = min(160, max(6, sizeStep.doubleValue))
            sizeField.stringValue = String(Int(e.fontSize))
            e.bold = boldChk.state == .on
            e.colorHex = DesignStyle.hex(colorWell.color)
            e.align = alignCtrl.selectedSegment == 0 ? "left"
                    : alignCtrl.selectedSegment == 2 ? "right" : "center"
        }
        e.opacity = opacitySlider.doubleValue
        e.hidden = hiddenChk.state == .on
        current = e
        onUpdate?(e)
    }

    @objc private func stepChanged() {
        sizeField.stringValue = String(Int(sizeStep.doubleValue))
        propChanged()
    }

    @objc private func snapChanged() {
        let g = Double(gridPop.titleOfSelectedItem ?? "8") ?? 8
        onSnapChange?(snapChk.state == .on, g)
    }

    @objc private func replaceAsset() { onReplaceAsset?() }
    @objc private func fontFile() { onFontFile?() }
    @objc private func addText() { onAddText?() }
    @objc private func addImage() { onAddImage?() }

    /// Right-click "字体与颜色…" focuses the font controls here.
    func focusFontStyle() {
        window?.makeFirstResponder(fontPop)
        onFontStyleFocus?()
    }

    override func layout() {
        super.layout()
        let pad: CGFloat = 12
        let w = bounds.width - pad * 2
        var y: CGFloat = 12

        header.frame = NSRect(x: pad, y: y, width: w, height: 15); y += 22
        kindLabel.frame = NSRect(x: pad, y: y, width: w, height: 18); y += 25
        assetBtn.frame = NSRect(x: pad, y: y, width: w, height: 26); y += 33
        textLabel.frame = NSRect(x: pad, y: y, width: w, height: 14); y += 17
        textField.frame = NSRect(x: pad, y: y, width: w, height: 24); y += 31
        fontLabel.frame = NSRect(x: pad, y: y, width: 34, height: 16)
        fontPop.frame = NSRect(x: pad + 38, y: y - 2, width: w - 38, height: 24); y += 31
        sizeLabel.frame = NSRect(x: pad, y: y, width: 34, height: 16)
        sizeField.frame = NSRect(x: pad + 38, y: y - 2, width: 64, height: 24)
        sizeStep.frame = NSRect(x: pad + 108, y: y - 2, width: 18, height: 24)
        boldChk.frame = NSRect(x: pad + 136, y: y - 2, width: 70, height: 20); y += 31
        colorLabel.frame = NSRect(x: pad, y: y, width: 34, height: 16)
        colorWell.frame = NSRect(x: pad + 38, y: y - 4, width: 44, height: 26)
        alignLabel.frame = NSRect(x: pad + 96, y: y, width: 30, height: 16)
        alignCtrl.frame = NSRect(x: pad + 128, y: y - 2, width: w - 128, height: 22); y += 33
        opacityLabel.frame = NSRect(x: pad, y: y, width: 62, height: 16)
        opacitySlider.frame = NSRect(x: pad + 66, y: y - 2, width: w - 66, height: 20); y += 29
        hiddenChk.frame = NSRect(x: pad, y: y, width: w, height: 20); y += 27
        line.frame = NSRect(x: pad, y: y, width: w, height: 1); y += 9
        snapChk.frame = NSRect(x: pad, y: y, width: w, height: 20); y += 27
        gridLabel.frame = NSRect(x: pad, y: y, width: 34, height: 16)
        gridPop.frame = NSRect(x: pad + 38, y: y - 2, width: w - 38, height: 24); y += 31
        fontFileBtn.frame = NSRect(x: pad, y: y, width: w, height: 26); y += 33
        let bw = (w - 8) / 2
        addTextBtn.frame = NSRect(x: pad, y: y, width: bw, height: 26)
        addImageBtn.frame = NSRect(x: pad + bw + 8, y: y, width: bw, height: 26); y += 33
        let hintY = max(y, bounds.height - 104)
        hint.frame = NSRect(x: pad, y: hintY, width: w,
                            height: max(0, bounds.height - hintY - 10))
    }
}
