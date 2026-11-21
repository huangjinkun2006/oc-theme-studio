import AppKit

// MARK: - 商店账号界面（登录 / 注册 / 资料编辑 / 用户主页）
//
// 与网页端共用同一套后端接口。所有网络回调在主线程更新 UI，失败只提示、不改动本地登录态。

// MARK: 登录 / 注册

private final class StoreAccountView: NSView {
    let seg = NSSegmentedControl(labels: ["登录", "注册"], trackingMode: .selectOne,
                                 target: nil, action: nil)
    let userF = UI.field("用户名（2-20 位中文 / 字母 / 数字）")
    let nickF = UI.field("昵称（展示用，可留空）")
    let passF = NSSecureTextField()
    let pass2F = NSSecureTextField()
    let msg = UI.label("", size: 11, color: .systemRed)
    let cancelBtn = UI.button("取消", height: 28)
    let submitBtn = UI.button("登录", height: 28, accent: true)

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        for f in [passF, pass2F] {
            f.font = .systemFont(ofSize: 12)
            f.bezelStyle = .roundedBezel
            f.frame.size.height = 24
        }
        passF.placeholderString = "密码"
        pass2F.placeholderString = "确认密码"
        seg.font = .systemFont(ofSize: 12, weight: .semibold)
        seg.segmentStyle = .rounded
        for v in [seg, userF, nickF, passF, pass2F, msg, cancelBtn, submitBtn] as [NSView] {
            addSubview(v)
        }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) unsupported") }

    override func layout() {
        super.layout()
        let pad: CGFloat = 18
        let w = bounds.width - pad * 2
        seg.frame = NSRect(x: pad, y: 16, width: w, height: 26)
        var y: CGFloat = 56
        userF.frame = NSRect(x: pad, y: y, width: w, height: 24); y += 34
        if !nickF.isHidden {
            nickF.frame = NSRect(x: pad, y: y, width: w, height: 24); y += 34
        }
        passF.frame = NSRect(x: pad, y: y, width: w, height: 24); y += 34
        if !pass2F.isHidden {
            pass2F.frame = NSRect(x: pad, y: y, width: w, height: 24); y += 34
        }
        msg.frame = NSRect(x: pad, y: y + 2, width: w, height: 32)
        let bw = (w - 10) / 2
        cancelBtn.frame = NSRect(x: pad, y: bounds.height - 44, width: bw, height: 28)
        submitBtn.frame = NSRect(x: pad + bw + 10, y: bounds.height - 44, width: bw, height: 28)
    }
}

final class StoreAccountWindowController: NSWindowController {
    private let v = StoreAccountView()
    private var busy = false
    var onDone: (() -> Void)?

    init() {
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 390, height: 330),
                         styleMask: [.titled, .closable, .miniaturizable],
                         backing: .buffered, defer: false)
        w.title = "登录 / 注册"
        w.center()
        w.contentView = v
        super.init(window: w)
        v.seg.selectedSegment = 0
        v.seg.target = self
        v.seg.action = #selector(modeChanged)
        v.cancelBtn.target = self
        v.cancelBtn.action = #selector(cancel)
        v.submitBtn.target = self
        v.submitBtn.action = #selector(submit)
        modeChanged()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) unsupported") }

    @objc private func modeChanged() {
        let registering = v.seg.selectedSegment == 1
        v.nickF.isHidden = !registering
        v.pass2F.isHidden = !registering
        v.submitBtn.title = registering ? "注册" : "登录"
        v.msg.stringValue = ""
        v.needsLayout = true
    }

    @objc private func cancel() { window?.orderOut(nil) }

    @objc private func submit() {
        guard !busy else { return }
        let name = v.userF.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let pwd = v.passF.stringValue
        guard !name.isEmpty, !pwd.isEmpty else {
            v.msg.stringValue = "请输入用户名和密码"
            return
        }
        let registering = v.seg.selectedSegment == 1
        if registering && pwd != v.pass2F.stringValue {
            v.msg.stringValue = "两次输入的密码不一致"
            return
        }
        busy = true
        v.submitBtn.isEnabled = false
        v.msg.stringValue = registering ? "正在注册…" : "正在登录…"
        let done: (Result<StoreUser, Error>) -> Void = { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.busy = false
                self.v.submitBtn.isEnabled = true
                switch result {
                case .success:
                    self.window?.orderOut(nil)
                    self.onDone?()
                case .failure(let err):
                    self.v.msg.stringValue = err.localizedDescription
                }
            }
        }
        if registering {
            StoreClient.register(username: name, password: pwd,
                                 nickname: v.nickF.stringValue.trimmingCharacters(in: .whitespaces),
                                 completion: done)
        } else {
            StoreClient.login(username: name, password: pwd, completion: done)
        }
    }
}

// MARK: 编辑资料

private final class StoreProfileEditView: NSView {
    let avatarBtn = NSButton()
    let pickBtn = UI.button("选择头像…", height: 26)
    let clearBtn = UI.button("移除头像", height: 26)
    let loginF = UI.field("用户名（也是登录账号）")
    let nickF = UI.field("昵称（展示名）")
    let bioF = UI.field("个人简介")
    let oldPwdF = NSSecureTextField()
    let newPwdF = NSSecureTextField()
    let pwdHint = UI.label("修改密码：留空表示不修改", size: 10.5, color: StorePalette.muted)
    let msg = UI.label("", size: 11, color: .systemRed)
    let cancelBtn = UI.button("取消", height: 28)
    let saveBtn = UI.button("保存资料", height: 28, accent: true)

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        styleAvatarButton(avatarBtn, size: 56)
        avatarBtn.isEnabled = false
        bioF.lineBreakMode = .byWordWrapping
        bioF.maximumNumberOfLines = 3
        for f in [oldPwdF, newPwdF] {
            f.font = .systemFont(ofSize: 12)
            f.bezelStyle = .roundedBezel
            f.frame.size.height = 24
        }
        oldPwdF.placeholderString = "原密码"
        newPwdF.placeholderString = "新密码（6-64 位）"
        for v in [avatarBtn, pickBtn, clearBtn, loginF, nickF, bioF,
                  pwdHint, oldPwdF, newPwdF, msg, cancelBtn, saveBtn] as [NSView] {
            addSubview(v)
        }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) unsupported") }

    override func layout() {
        super.layout()
        let pad: CGFloat = 18
        let w = bounds.width - pad * 2
        avatarBtn.frame = NSRect(x: pad, y: 12, width: 56, height: 56)
        pickBtn.frame = NSRect(x: pad + 66, y: 30, width: 110, height: 26)
        clearBtn.frame = NSRect(x: pad + 182, y: 30, width: 90, height: 26)
        var y: CGFloat = 84
        loginF.frame = NSRect(x: pad, y: y, width: w, height: 24); y += 34
        nickF.frame = NSRect(x: pad, y: y, width: w, height: 24); y += 34
        bioF.frame = NSRect(x: pad, y: y, width: w, height: 54); y += 64
        pwdHint.frame = NSRect(x: pad, y: y, width: w, height: 16); y += 20
        oldPwdF.frame = NSRect(x: pad, y: y, width: w, height: 24); y += 30
        newPwdF.frame = NSRect(x: pad, y: y, width: w, height: 24); y += 34
        msg.frame = NSRect(x: pad, y: y, width: w, height: 30)
        let bw = (w - 10) / 2
        cancelBtn.frame = NSRect(x: pad, y: bounds.height - 44, width: bw, height: 28)
        saveBtn.frame = NSRect(x: pad + bw + 10, y: bounds.height - 44, width: bw, height: 28)
    }
}

final class StoreProfileEditWindowController: NSWindowController {
    private let v = StoreProfileEditView()
    private var busy = false
    var onDone: (() -> Void)?

    init() {
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 420, height: 430),
                         styleMask: [.titled, .closable, .miniaturizable],
                         backing: .buffered, defer: false)
        w.title = "编辑个人资料"
        w.center()
        w.contentView = v
        super.init(window: w)
        v.pickBtn.target = self; v.pickBtn.action = #selector(pickAvatar)
        v.clearBtn.target = self; v.clearBtn.action = #selector(clearAvatar)
        v.cancelBtn.target = self; v.cancelBtn.action = #selector(cancel)
        v.saveBtn.target = self; v.saveBtn.action = #selector(save)
        fill()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) unsupported") }

    private func fill() {
        let u = StoreClient.currentUser
        v.loginF.stringValue = u?.loginName ?? ""
        v.nickF.stringValue = u?.nick ?? u?.user ?? ""
        v.bioF.stringValue = u?.bio ?? ""
        setAvatarButton(v.avatarBtn, name: u?.displayName ?? "?", path: u?.avatar, size: 56)
        v.msg.stringValue = ""
    }

    @objc private func cancel() { window?.orderOut(nil) }

    @objc private func pickAvatar() {
        guard let win = window else { return }
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedFileTypes = ["png", "jpg", "jpeg", "webp", "gif"]
        panel.message = "选择头像图片（不超过 2 MB）"
        panel.beginSheetModal(for: win) { [weak self] resp in
            guard let self = self, resp == .OK, let url = panel.url else { return }
            self.v.msg.stringValue = "正在上传头像…"
            StoreClient.uploadAvatar(fileURL: url) { [weak self] result in
                DispatchQueue.main.async {
                    guard let self = self else { return }
                    switch result {
                    case .success(let u):
                        self.v.msg.stringValue = "头像已更新"
                        setAvatarButton(self.v.avatarBtn, name: u.displayName,
                                        path: u.avatar, size: 56)
                        self.onDone?()
                    case .failure(let err):
                        self.v.msg.stringValue = "头像上传失败：\(err.localizedDescription)"
                    }
                }
            }
        }
    }

    @objc private func clearAvatar() {
        v.msg.stringValue = "正在移除…"
        StoreClient.deleteAvatar { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self else { return }
                switch result {
                case .success(let u):
                    self.v.msg.stringValue = "已恢复默认头像"
                    setAvatarButton(self.v.avatarBtn, name: u.displayName, path: nil, size: 56)
                    self.onDone?()
                case .failure(let err):
                    self.v.msg.stringValue = err.localizedDescription
                }
            }
        }
    }

    @objc private func save() {
        guard !busy else { return }
        let login = v.loginF.stringValue.trimmingCharacters(in: .whitespaces)
        let nick = v.nickF.stringValue.trimmingCharacters(in: .whitespaces)
        let bio = v.bioF.stringValue.trimmingCharacters(in: .whitespaces)
        let oldPwd = v.oldPwdF.stringValue
        let newPwd = v.newPwdF.stringValue
        guard !login.isEmpty else { v.msg.stringValue = "用户名不能为空"; return }
        if !newPwd.isEmpty && newPwd.count < 6 {
            v.msg.stringValue = "新密码至少 6 位"
            return
        }
        busy = true
        v.saveBtn.isEnabled = false
        v.msg.stringValue = "正在保存…"
        StoreClient.updateProfile(login: login, nick: nick, bio: bio,
                                  oldPassword: oldPwd, newPassword: newPwd) { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.busy = false
                self.v.saveBtn.isEnabled = true
                switch result {
                case .success:
                    self.window?.orderOut(nil)
                    self.onDone?()
                case .failure(let err):
                    self.v.msg.stringValue = err.localizedDescription
                }
            }
        }
    }
}

// MARK: 用户主页

private final class StoreProfileContent: NSView {
    override var isFlipped: Bool { true }
    let avatarBtn = NSButton()
    let nameF = UI.label("", size: 18, weight: .bold)
    let loginF = UI.label("", size: 11, color: StorePalette.muted)
    let bioF = UI.label("", size: 12, color: .secondaryLabelColor)
    let statsF = UI.label("", size: 11, color: StorePalette.muted)
    let editBtn = UI.button("编辑资料", height: 26)
    let themeHead = UI.label("上传主题", size: 12, weight: .semibold)
    let commentHead = UI.label("评论", size: 12, weight: .semibold)
    var onPickTheme: ((StoreTheme) -> Void)?
    var onEdit: (() -> Void)?
    private var themes: [StoreTheme] = []
    private var themeBtns: [NSButton] = []
    private var commentBlocks: [NSView] = []
    private var preferredHeight: CGFloat = 300

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        styleAvatarButton(avatarBtn, size: 56)
        avatarBtn.isEnabled = false
        bioF.lineBreakMode = .byWordWrapping
        bioF.maximumNumberOfLines = 3
        statsF.lineBreakMode = .byWordWrapping
        editBtn.target = self
        editBtn.action = #selector(editClicked)
        for v in [avatarBtn, nameF, loginF, bioF, statsF, editBtn,
                  themeHead, commentHead] as [NSView] {
            addSubview(v)
        }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) unsupported") }

    func render(_ p: StoreProfile) {
        let nick = p.nick ?? p.login ?? "用户"
        nameF.stringValue = nick
        loginF.stringValue = "@" + (p.login ?? "")
        bioF.stringValue = p.bio ?? ""
        var stats = "上传主题 \(p.themeCount ?? 0)    发表评论 \(p.commentCount ?? 0)    主题下载 \(p.downloadCount ?? 0)"
        if let created = p.created { stats += "    注册于 \(String(created.prefix(10)))" }
        statsF.stringValue = stats
        setAvatarButton(avatarBtn, name: nick, path: p.avatar, size: 56)
        let mine = StoreClient.currentUser?.loginName.lowercased()
            == (p.login ?? "").lowercased() && !(p.login ?? "").isEmpty
        editBtn.isHidden = !mine

        themeBtns.forEach { $0.removeFromSuperview() }
        themeBtns = []
        commentBlocks.forEach { $0.removeFromSuperview() }
        commentBlocks = []
        themes = p.themes ?? []

        for (i, t) in themes.prefix(20).enumerated() {
            let b = NSButton(title: "\(t.name)   ·   \(t.categoryDisplay)   ·   \(t.downloads ?? 0) 次下载",
                             target: self, action: #selector(pickTheme(_:)))
            b.tag = i
            b.bezelStyle = .rounded
            b.isBordered = false
            b.font = .systemFont(ofSize: 12)
            b.contentTintColor = StorePalette.accent
            b.alignment = .left
            themeBtns.append(b)
            addSubview(b)
        }
        for c in (p.comments ?? []).prefix(30) {
            let block = NSView()
            block.wantsLayer = true
            block.layer?.backgroundColor = StorePalette.surface.cgColor
            block.layer?.cornerRadius = 8
            block.layer?.borderWidth = 1
            block.layer?.borderColor = StorePalette.line.cgColor
            let head = UI.label("\(c.time ?? "")   ·   \(c.user ?? "")", size: 10.5,
                                color: StorePalette.muted)
            let text = UI.label(c.text ?? "", size: 12)
            text.lineBreakMode = .byWordWrapping
            text.maximumNumberOfLines = 3
            block.addSubview(head)
            block.addSubview(text)
            commentBlocks.append(block)
            addSubview(block)
        }
        preferredHeight = 160 + CGFloat(themeBtns.count) * 30
            + (commentBlocks.isEmpty ? 0 : 30)
            + CGFloat(commentBlocks.count) * 76 + 30
        frame = NSRect(x: 0, y: 0, width: max(400, bounds.width), height: preferredHeight)
        needsLayout = true
    }

    @objc private func pickTheme(_ sender: NSButton) {
        guard sender.tag >= 0, sender.tag < themes.count else { return }
        onPickTheme?(themes[sender.tag])
    }
    @objc private func editClicked() { onEdit?() }

    override func layout() {
        super.layout()
        let w = bounds.width
        let pad: CGFloat = 20
        avatarBtn.frame = NSRect(x: pad, y: 18, width: 56, height: 56)
        nameF.frame = NSRect(x: pad + 68, y: 20, width: w - pad * 2 - 68, height: 22)
        loginF.frame = NSRect(x: pad + 68, y: 44, width: w - pad * 2 - 68, height: 16)
        bioF.frame = NSRect(x: pad + 68, y: 64, width: w - pad * 2 - 68, height: 40)
        statsF.frame = NSRect(x: pad, y: 86, width: w - pad * 2 - 110, height: 30)
        editBtn.frame = NSRect(x: w - pad - 100, y: 92, width: 100, height: 26)
        themeHead.frame = NSRect(x: pad, y: 122, width: w - pad * 2, height: 18)
        var y: CGFloat = 146
        for b in themeBtns {
            b.frame = NSRect(x: pad, y: y, width: w - pad * 2, height: 26)
            y += 30
        }
        if !themeBtns.isEmpty { y += 10 }
        commentHead.frame = NSRect(x: pad, y: y, width: w - pad * 2, height: 18)
        y += 26
        for block in commentBlocks {
            block.frame = NSRect(x: pad, y: y, width: w - pad * 2, height: 68)
            if block.subviews.count >= 2 {
                block.subviews[0].frame = NSRect(x: 10, y: 8, width: w - pad * 2 - 20, height: 16)
                block.subviews[1].frame = NSRect(x: 10, y: 27, width: w - pad * 2 - 20, height: 36)
            }
            y += 76
        }
    }
}

final class StoreUserProfileWindowController: NSWindowController {
    private final class Root: NSView {
        let scroll = NSScrollView()
        let status = UI.label("加载中…", size: 11, color: StorePalette.muted)
        override init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            wantsLayer = true
            layer?.backgroundColor = StorePalette.bg.cgColor
            scroll.drawsBackground = false
            scroll.hasVerticalScroller = true
            addSubview(scroll)
            addSubview(status)
        }
        required init?(coder: NSCoder) { fatalError("init(coder:) unsupported") }
        override func layout() {
            super.layout()
            scroll.frame = NSRect(x: 0, y: 30, width: bounds.width, height: max(0, bounds.height - 30))
            status.frame = NSRect(x: 16, y: 8, width: max(0, bounds.width - 32), height: 16)
        }
    }

    private let content = StoreProfileContent()
    private let root = Root()
    private var login = ""
    var onPickTheme: ((StoreTheme) -> Void)?
    var onEdit: (() -> Void)?

    init(login: String) {
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 680, height: 620),
                         styleMask: [.titled, .closable, .miniaturizable, .resizable],
                         backing: .buffered, defer: false)
        w.title = "用户主页"
        w.minSize = NSSize(width: 480, height: 360)
        w.center()
        let root = self.root
        root.scroll.documentView = content
        w.contentView = root
        super.init(window: w)
        self.login = login
        content.onPickTheme = { [weak self] t in self?.onPickTheme?(t) }
        content.onEdit = { [weak self] in self?.onEdit?() }
        load()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) unsupported") }

    private func load() {
        StoreClient.profile(login: login) { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self else { return }
                switch result {
                case .success(let p):
                    self.content.render(p)
                    self.root.status.stringValue = "主页加载完成"
                case .failure(let err):
                    self.root.status.stringValue = "加载失败：\(err.localizedDescription)"
                }
            }
        }
    }
}
