import AppKit

// MARK: - Settings sheet

private final class AISettingsPanel: NSView {
    override var isFlipped: Bool { true }
    let presetPopup = NSPopUpButton()
    let baseField = UI.field("https://api.deepseek.com/v1")
    let modelField = UI.field("deepseek-chat")
    let keyField = NSSecureTextField(string: "")
    let note = UI.label("", size: 10, color: .secondaryLabelColor)

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        for (i, p) in AISettings.presets.enumerated() {
            presetPopup.addItem(withTitle: p.name)
            presetPopup.item(at: i)?.tag = i
        }
        presetPopup.addItem(withTitle: "自定义")
        presetPopup.target = self
        presetPopup.action = #selector(presetChanged)
        keyField.placeholderString = "API Key（仅保存在本机）"
        keyField.font = .systemFont(ofSize: 12)
        keyField.bezelStyle = .roundedBezel
        note.stringValue = """
        兼容 OpenAI /chat/completions 的接口。密钥只写入 \
        ~/Library/Application Support/OCThemeStudio/ai.json（权限 600），不会上传。\
        不填或不可用时自动回退本地智能引擎，不影响一键生成。
        """
        note.lineBreakMode = .byWordWrapping
        note.maximumNumberOfLines = 4
        for v in [presetPopup, baseField, modelField, keyField, note] as [NSView] {
            addSubview(v)
        }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) unsupported") }

    func configure(_ s: AISettings) {
        baseField.stringValue = s.baseURL
        modelField.stringValue = s.model
        keyField.stringValue = s.apiKey
        let idx = AISettings.presets.firstIndex { $0.url == s.baseURL } ?? AISettings.presets.count
        presetPopup.selectItem(at: idx)
    }

    @objc private func presetChanged() {
        let i = presetPopup.indexOfSelectedItem
        guard i >= 0, i < AISettings.presets.count else { return }
        let p = AISettings.presets[i]
        baseField.stringValue = p.url
        modelField.stringValue = p.model
    }

    func read(_ current: AISettings) -> AISettings {
        var s = current
        s.baseURL = baseField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        s.model = modelField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        s.apiKey = keyField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.model.isEmpty { s.model = "deepseek-chat" }
        return s
    }

    override func layout() {
        super.layout()
        let w = bounds.width
        presetPopup.frame = NSRect(x: 0, y: 4, width: w, height: 26)
        baseField.frame = NSRect(x: 0, y: 38, width: w, height: 24)
        modelField.frame = NSRect(x: 0, y: 70, width: (w - 10) / 2, height: 24)
        keyField.frame = NSRect(x: (w + 10) / 2, y: 70, width: (w - 10) / 2, height: 24)
        note.frame = NSRect(x: 0, y: 104, width: w, height: 62)
    }
}

// MARK: - Root view

final class AIThemeRootView: NSView {
    override var isFlipped: Bool { true }

    let promptTitle = UI.section("提示词 · 描述你想要的风格")
    let promptScroll = NSTextView.scrollableTextView()
    var promptView: NSTextView { promptScroll.documentView as! NSTextView }

    let styleTitle = UI.section("灵感风格 · 点一下直接生成")
    var styleButtons: [NSButton] = []

    let optionTitle = UI.section("主题选项")
    let iconPopup = NSPopUpButton()
    let restyleChk = UI.checkbox("图标按主题改造", on: true)
    let iconStyleLbl = UI.label("图标风格", size: 11, color: .secondaryLabelColor)
    let iconStylePopup = NSPopUpButton()

    let aiTitle = UI.section("AI 增强 · 可选")
    let llmChk = UI.checkbox("使用大模型理解提示词", on: false)
    let settingsBtn = UI.button("设置…", height: 24)
    let llmNote = UI.label("", size: 10, color: .secondaryLabelColor)

    let previewTitle = UI.section("主题预览 · 16:9")
    let previewImage = NSImageView()
    let nameF = UI.label("", size: 16, weight: .semibold)
    let infoF = UI.label("", size: 11, color: .secondaryLabelColor)
    let swatchTitle = UI.section("配色方案")
    let swatches: [NSView] = (0..<5).map { _ in
        let v = NSView()
        v.wantsLayer = true
        v.layer?.cornerRadius = 4
        v.layer?.borderColor = NSColor.separatorColor.cgColor
        v.layer?.borderWidth = 1
        return v
    }
    let engineF = UI.label("", size: 10.5, color: .secondaryLabelColor)

    let bottomLine = UI.hLine()
    let statusF = UI.label("", size: 10.5, color: .secondaryLabelColor)
    let inspireBtn = UI.button("🎲 一键灵感", height: 28)
    let generateBtn = UI.button("✨ 生成预览", height: 28)
    let rerollBtn = UI.button("🔄 换个感觉", height: 28)
    let saveBtn = UI.button("💾 保存到主题库", height: 28, accent: true)
    let closeBtn = UI.button("关闭", height: 28)

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        promptView.font = .systemFont(ofSize: 12)
        promptView.isRichText = false
        promptView.textContainerInset = NSSize(width: 6, height: 6)
        promptScroll.drawsBackground = true
        promptScroll.wantsLayer = true
        promptScroll.layer?.cornerRadius = 6
        promptScroll.layer?.borderColor = NSColor.separatorColor.cgColor
        promptScroll.layer?.borderWidth = 1

        for st in AIThemeEngine.styles {
            let b = UI.button(st.name, height: 24)
            b.tag = styleButtons.count
            styleButtons.append(b)
        }
        iconPopup.addItems(withTitles: ["标准 8 图标", "极简 4 图标", "多发行版 10 图标", "全量 15 图标"])
        iconStylePopup.addItems(withTitles: AIIconStyle.allCases.map { $0.title })
        iconStylePopup.toolTip = "在原有系统图标造型上叠加不同风格；「自动」会跟随壁纸风格选择。"
        llmNote.stringValue = "未启用大模型时由本地智能引擎解析提示词，完全离线可用。"

        previewImage.imageScaling = .scaleProportionallyUpOrDown
        previewImage.imageAlignment = .alignCenter
        previewImage.wantsLayer = true
        previewImage.layer?.cornerRadius = 8
        previewImage.layer?.masksToBounds = true
        previewImage.layer?.backgroundColor = NSColor.black.cgColor
        infoF.lineBreakMode = .byWordWrapping
        infoF.maximumNumberOfLines = 2

        var views: [NSView] = [promptTitle, promptScroll, styleTitle, optionTitle,
                              iconPopup, restyleChk, iconStyleLbl, iconStylePopup,
                              aiTitle, llmChk, settingsBtn, llmNote,
                              previewTitle, previewImage, nameF, infoF, swatchTitle,
                              engineF, bottomLine, statusF, inspireBtn, generateBtn,
                              rerollBtn, saveBtn, closeBtn]
        views += styleButtons as [NSView]
        views += swatches as [NSView]
        for v in views { addSubview(v) }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) unsupported") }

    override func layout() {
        super.layout()
        let pad: CGFloat = 16
        let top: CGFloat = 30
        let leftW: CGFloat = 340
        let rightX = pad + leftW + 16
        let rightW = bounds.width - rightX - pad
        let w = bounds.width - pad * 2

        promptTitle.frame = NSRect(x: pad, y: top + 8, width: leftW, height: 15)
        promptScroll.frame = NSRect(x: pad, y: top + 26, width: leftW, height: 104)
        styleTitle.frame = NSRect(x: pad, y: top + 140, width: leftW, height: 15)
        let bw = (leftW - 8) / 2
        for (i, b) in styleButtons.enumerated() {
            let col = CGFloat(i % 2), row = CGFloat(i / 2)
            b.frame = NSRect(x: pad + col * (bw + 8), y: top + 160 + row * 28,
                             width: bw, height: 24)
        }
        optionTitle.frame = NSRect(x: pad, y: top + 336, width: leftW, height: 15)
        iconPopup.frame = NSRect(x: pad, y: top + 356, width: 190, height: 26)
        restyleChk.frame = NSRect(x: pad + 200, y: top + 359, width: leftW - 200, height: 20)
        iconStyleLbl.frame = NSRect(x: pad, y: top + 392, width: 70, height: 20)
        iconStylePopup.frame = NSRect(x: pad + 72, y: top + 388, width: leftW - 72, height: 26)
        aiTitle.frame = NSRect(x: pad, y: top + 426, width: leftW, height: 15)
        llmChk.frame = NSRect(x: pad, y: top + 446, width: 190, height: 20)
        settingsBtn.frame = NSRect(x: pad + 200, y: top + 444, width: 110, height: 24)
        llmNote.frame = NSRect(x: pad, y: top + 474, width: leftW, height: 34)
        llmNote.lineBreakMode = .byWordWrapping
        llmNote.maximumNumberOfLines = 2

        previewTitle.frame = NSRect(x: rightX, y: top + 8, width: rightW, height: 15)
        let ph = rightW * 9 / 16
        previewImage.frame = NSRect(x: rightX, y: top + 26, width: rightW, height: ph)
        var y = top + 34 + ph
        nameF.frame = NSRect(x: rightX, y: y, width: rightW, height: 22)
        y += 26
        infoF.frame = NSRect(x: rightX, y: y, width: rightW, height: 34)
        y += 42
        swatchTitle.frame = NSRect(x: rightX, y: y, width: rightW, height: 15)
        y += 20
        for (i, v) in swatches.enumerated() {
            v.frame = NSRect(x: rightX + CGFloat(i) * 56, y: y, width: 48, height: 24)
        }
        y += 32
        engineF.frame = NSRect(x: rightX, y: y, width: rightW, height: 16)

        bottomLine.frame = NSRect(x: pad, y: bounds.height - 58, width: w, height: 1)
        let by = bounds.height - 46
        let widths: [CGFloat] = [110, 110, 110, 140, 76]
        let buttons: [NSButton] = [inspireBtn, generateBtn, rerollBtn, saveBtn, closeBtn]
        var total: CGFloat = 0
        for wd in widths { total += wd }
        total += 8 * CGFloat(buttons.count - 1)
        var x = bounds.width - pad - total
        for (i, b) in buttons.enumerated() {
            b.frame = NSRect(x: x, y: by, width: widths[i], height: 28)
            x += widths[i] + 8
        }
        statusF.frame = NSRect(x: pad, y: by + 6,
                               width: max(60, inspireBtn.frame.minX - pad - 10), height: 16)
    }
}

// MARK: - Window controller

final class AIThemeWindowController: NSWindowController, NSWindowDelegate {

    var onSaved: ((String) -> Void)?
    var onClose: (() -> Void)?

    private var design = AIThemeEngine.design(prompt: "")
    private var settings = AISettings.load()
    private var busy = false

    private var root: AIThemeRootView { window!.contentView as! AIThemeRootView }

    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1000, height: 700),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered, defer: false)
        window.title = "AI 主题生成器"
        window.minSize = NSSize(width: 940, height: 650)
        window.center()
        window.setFrameAutosaveName("OCThemeStudioSwiftAITheme")
        self.init(window: window)
        let size = window.contentRect(forFrameRect: window.frame).size
        window.contentView = AIThemeRootView(frame: NSRect(origin: .zero, size: size))
        window.delegate = self
        setup()
    }

    private func setup() {
        let r = root
        for (b, sel) in [(r.inspireBtn, #selector(inspire)),
                         (r.generateBtn, #selector(generateFromPrompt)),
                         (r.rerollBtn, #selector(reroll)),
                         (r.saveBtn, #selector(saveToLibrary)),
                         (r.closeBtn, #selector(closeWindow)),
                         (r.settingsBtn, #selector(openSettings))] as [(NSButton, Selector)] {
            b.target = self; b.action = sel
        }
        for b in r.styleButtons {
            b.target = self
            b.action = #selector(styleTapped(_:))
        }
        r.llmChk.target = self
        r.llmChk.action = #selector(llmToggled)
        r.llmChk.state = settings.enabled ? .on : .off
        r.iconPopup.target = self
        r.iconPopup.action = #selector(optionChanged)
        r.restyleChk.target = self
        r.restyleChk.action = #selector(optionChanged)
        r.restyleChk.toolTip = "保留原有系统图标造型（Apple / Windows / Linux 等），按当前主题配色重新着色；取消勾选则原样使用内置 ICNS。"
        r.iconStylePopup.target = self
        r.iconStylePopup.action = #selector(optionChanged)
        updateLLMLabels()
        inspire()
    }

    private func status(_ s: String) { root.statusF.stringValue = s }

    private func updateLLMLabels() {
        let r = root
        r.llmNote.stringValue = settings.enabled
            ? "已启用 \(settings.model)。生成时会先让大模型设计配色与风格，失败自动回退本地引擎。"
            : "未启用大模型时由本地智能引擎解析提示词，完全离线可用。"
        r.llmNote.lineBreakMode = .byWordWrapping
        r.llmNote.maximumNumberOfLines = 2
    }

    // MARK: Generation

    private func apply(_ d: AIThemeDesign, note: String) {
        design = d
        let r = root
        r.previewImage.image = AIThemeRenderer.preview(d)
        r.nameF.stringValue = d.name
        r.infoF.stringValue = "风格「\(d.style)」 · \(d.decorationName) · \(d.iconSetName)"
            + "\n" + d.summary
            + (d.restyleIcons ? "（图标风格：\(d.iconStyleName)）" : "")
        let colors = d.palette + [d.accent, d.glow]
        for (i, v) in r.swatches.enumerated() where i < colors.count {
            v.layer?.backgroundColor = aiNSColor(colors[i]).cgColor
        }
        r.engineF.stringValue = "设计来源：\(d.engine)" +
            (d.prompt.isEmpty ? "" : " · 提示词：\(d.prompt)")
        r.engineF.lineBreakMode = .byTruncatingTail
        status(note)
        r.saveBtn.isEnabled = true
        syncOptionControls()
    }

    private func syncOptionControls() {
        let r = root
        let idx: Int
        switch design.iconSet {
        case "minimal": idx = 1
        case "linux": idx = 2
        case "full": idx = 3
        default: idx = 0
        }
        r.iconPopup.selectItem(at: idx)
        r.restyleChk.state = design.restyleIcons ? .on : .off
        let styles = AIIconStyle.allCases.map { $0.rawValue }
        r.iconStylePopup.selectItem(at: styles.firstIndex(of: design.iconStyle) ?? 0)
        r.iconStylePopup.isEnabled = design.restyleIcons
    }

    private func generate(prompt: String, allowLLM: Bool = true) {
        guard !busy else { return }
        if allowLLM && settings.enabled && !settings.apiKey.isEmpty {
            busy = true
            root.saveBtn.isEnabled = false
            status("正在咨询大模型…")
            AIThemeEngine.refineWithLLM(prompt: prompt, settings: settings) {
                [weak self] result in
                guard let self = self else { return }
                self.busy = false
                switch result {
                case .success(let d):
                    self.apply(d, note: "大模型已生成设计方案 · 可保存或换个感觉")
                case .failure(let e):
                    self.apply(AIThemeEngine.design(prompt: prompt),
                               note: "大模型不可用（\(e.localizedDescription)），已回退本地引擎")
                }
            }
        } else {
            apply(AIThemeEngine.design(prompt: prompt),
                  note: settings.enabled && settings.apiKey.isEmpty
                    ? "未填写 API Key，已使用本地智能引擎"
                    : "本地智能引擎已生成 · 可保存或换个感觉")
        }
    }

    @objc private func inspire() {
        let p = AIThemeEngine.inspirations.randomElement() ?? ""
        root.promptView.string = p
        generate(prompt: p)
    }

    @objc private func generateFromPrompt() {
        generate(prompt: root.promptView.string)
    }

    @objc private func reroll() {
        let p = root.promptView.string
        var d = AIThemeEngine.design(prompt: p, seed: UInt64.random(in: 1...UInt64.max))
        if design.fromLLM { d.fromLLM = true; d.engine = design.engine }
        apply(d, note: "已换一套配色与构图 · 可保存")
    }

    @objc private func styleTapped(_ sender: NSButton) {
        guard sender.tag >= 0, sender.tag < AIThemeEngine.styles.count else { return }
        let st = AIThemeEngine.styles[sender.tag]
        let p = "\(st.name)，\(st.keywords.first ?? "")风格"
        root.promptView.string = p
        generate(prompt: p)
    }

    @objc private func optionChanged() {
        let map = ["standard", "minimal", "linux", "full"]
        design.iconSet = map[root.iconPopup.indexOfSelectedItem]
        design.restyleIcons = root.restyleChk.state == .on
        let styles = AIIconStyle.allCases.map { $0.rawValue }
        let i = root.iconStylePopup.indexOfSelectedItem
        if i >= 0 && i < styles.count { design.iconStyle = styles[i] }
        apply(design, note: "已更新主题选项 · 预览已刷新")
    }

    @objc private func llmToggled() {
        settings.enabled = root.llmChk.state == .on
        settings.save()
        updateLLMLabels()
        status(settings.enabled ? "已启用大模型增强，请在「设置…」里填写密钥" : "已切换为本地智能引擎")
        if settings.enabled && settings.apiKey.isEmpty { openSettings() }
    }

    @objc private func openSettings() {
        let panel = AISettingsPanel(frame: NSRect(x: 0, y: 0, width: 360, height: 170))
        panel.configure(settings)
        let a = NSAlert()
        a.messageText = "大模型设置"
        a.informativeText = "填写任意 OpenAI 兼容接口即可让提示词理解更准确。"
        a.accessoryView = panel
        a.addButton(withTitle: "保存")
        a.addButton(withTitle: "取消")
        guard let w = window else { return }
        a.beginSheetModal(for: w) { [weak self] resp in
            guard resp == .alertFirstButtonReturn, let self = self else { return }
            self.settings = panel.read(self.settings)
            self.settings.save()
            self.root.llmChk.state = self.settings.enabled ? .on : .off
            self.updateLLMLabels()
            self.status("AI 设置已保存")
        }
    }

    @objc private func saveToLibrary() {
        guard !busy else { return }
        do {
            let id = try AIThemeBuilder.build(design)
            onSaved?(id)
            status("已保存「\(design.name)」到主题库 · 可直接应用到 EFI")
        } catch {
            let a = NSAlert()
            a.messageText = "生成主题失败"
            a.informativeText = error.localizedDescription
            a.alertStyle = .critical
            a.addButton(withTitle: "好")
            if let w = window { a.beginSheetModal(for: w, completionHandler: nil) }
        }
    }

    @objc private func closeWindow() { window?.close() }

    func windowWillClose(_ notification: Notification) { onClose?() }

    /// Hook for the offline validation harness.
    func debugGenerate(_ prompt: String) {
        root.promptView.string = prompt
        generate(prompt: prompt, allowLLM: false)
    }
    func debugSave() { saveToLibrary() }
}
