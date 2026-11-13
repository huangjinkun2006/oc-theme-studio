import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    static var shared: AppDelegate?
    private var mainWindow: MainWindowController?
    /// Files handed over before the main window exists (Finder "open with").
    private var pendingFiles: [URL] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        buildMenu()
        let controller = MainWindowController()
        mainWindow = controller
        controller.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
        AppDelegate.shared = self
        // Optional auto boot simulation on launch (set from the sim overlay).
        if (jsonRead(Paths.state)?["autoBootSim"] as? Bool) == true {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
                self?.mainWindow?.openBootSim()
            }
        }
        if !pendingFiles.isEmpty {
            let files = pendingFiles
            pendingFiles.removeAll()
            DispatchQueue.main.async { self.dispatchOpen(files) }
        }
        handleDebugFlags()
    }

    /// Dragging a ZIP / folder onto the app icon installs a theme; dragging a
    /// JPG / PNG opens the ICNS converter with that picture already loaded.
    func application(_ sender: NSApplication, openFile filename: String) -> Bool {
        dispatchOpen([URL(fileURLWithPath: filename)])
        return true
    }

    func application(_ sender: NSApplication, openFiles filenames: [String]) {
        dispatchOpen(filenames.map { URL(fileURLWithPath: $0) })
        sender.reply(toOpenOrPrint: .success)
    }

    private func dispatchOpen(_ urls: [URL]) {
        guard let w = mainWindow else {
            pendingFiles += urls
            return
        }
        let images = urls.filter { ICNSConverter.isImage($0) }
        let packages = urls.filter { !ICNSConverter.isImage($0) }
        if !images.isEmpty { w.openICNSConverter(initialFile: images[0]) }
        if !packages.isEmpty { w.importURLs(packages) }
    }

    /// Optional introspection used when validating a build. Not active in
    /// normal launches (no flags passed by Finder / `open`).
    private func handleDebugFlags() {
        let args = CommandLine.arguments
        guard let idx = args.firstIndex(of: "--debug"),
              idx + 1 < args.count else { return }
        let base = args[idx + 1]
        var row: Int? = nil
        if let si = args.firstIndex(of: "--select"), si + 1 < args.count {
            row = Int(args[si + 1])
        }
        var assetRow: Int? = nil
        if let ai = args.firstIndex(of: "--asset"), ai + 1 < args.count {
            assetRow = Int(args[ai + 1])
        }
        NSApp.appearance = NSAppearance(named: .aqua)
        let debugImage: URL = {
            if let ii = args.firstIndex(of: "--image"), ii + 1 < args.count {
                return URL(fileURLWithPath: args[ii + 1])
            }
            return URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appendingPathComponent(".cache/icns_test/wide.jpg")
        }()
        if args.contains("--icns") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) { [weak self] in
                self?.mainWindow?.debugOpenConverter(debugImage)
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
                    guard let w = NSApp.windows.first(where: {
                        $0.title.hasPrefix("图片转 ICNS")
                    }) else { return }
                    w.makeKeyAndOrderFront(nil)
                    w.displayIfNeeded()
                    guard let cv = w.contentView else { return }
                    cv.layoutSubtreeIfNeeded()
                    self?.dump(cv, to: base + "_icns.txt")
                    self?.snapshot(cv, to: base + "_icns.png")
                }
            }
        }
        if args.contains("--editor-icns") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) { [weak self] in
                if let row = row { self?.mainWindow?.debugSelect(row) }
                self?.mainWindow?.debugOpenEditor()
                if let a = assetRow { self?.mainWindow?.debugSelectEditorAsset(a) }
                self?.mainWindow?.debugOpenEditorConverter(debugImage)
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
                    guard let w = NSApp.windows.first(where: {
                        $0.title.hasPrefix("图片转 ICNS")
                    }) else { return }
                    w.makeKeyAndOrderFront(nil)
                    w.displayIfNeeded()
                    guard let cv = w.contentView else { return }
                    cv.layoutSubtreeIfNeeded()
                    self?.dump(cv, to: base + "_editor_icns.txt")
                    self?.snapshot(cv, to: base + "_editor_icns.png")
                }
            }
        }
        if args.contains("--editor") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
                if let row = row { self?.mainWindow?.debugSelect(row) }
                self?.mainWindow?.debugOpenEditor()
                if let a = assetRow { self?.mainWindow?.debugSelectEditorAsset(a) }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    guard let w = NSApp.windows.first(where: {
                        $0.title.hasPrefix("主题编辑器")
                    }) else { return }
                    w.makeKeyAndOrderFront(nil)
                    w.displayIfNeeded()
                    guard let cv = w.contentView else { return }
                    cv.layoutSubtreeIfNeeded()
                    self?.dump(cv, to: base + "_editor.txt")
                    self?.snapshot(cv, to: base + "_editor.png")
                }
            }
        }
        if args.contains("--design") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) { [weak self] in
                if let row = row { self?.mainWindow?.debugSelect(row) }
                self?.mainWindow?.debugOpenDesign()
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
                    guard let w = NSApp.windows.first(where: {
                        $0.title.hasPrefix("可视化设计")
                    }) else { return }
                    w.makeKeyAndOrderFront(nil)
                    w.displayIfNeeded()
                    guard let cv = w.contentView else { return }
                    cv.layoutSubtreeIfNeeded()
                    self?.dump(cv, to: base + "_design.txt")
                    self?.snapshot(cv, to: base + "_design.png")
                }
            }
        }
        if args.contains("--bootscan") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) { [weak self] in
                if let row = row { self?.mainWindow?.debugSelect(row) }
                self?.mainWindow?.debugOpenBootScan()
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) {
                    guard let w = NSApp.windows.first(where: {
                        $0.title.hasPrefix("识别系统启动项")
                    }) else { return }
                    w.makeKeyAndOrderFront(nil)
                    w.displayIfNeeded()
                    guard let cv = w.contentView else { return }
                    cv.layoutSubtreeIfNeeded()
                    self?.dump(cv, to: base + "_bootscan.txt")
                    self?.snapshot(cv, to: base + "_bootscan.png")
                }
            }
        }
        if args.contains("--repair") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                guard let t = ThemeLibrary.shared.themes.first else {
                    try? "no themes".write(toFile: base + "_repair.txt",
                                           atomically: true, encoding: .utf8)
                    return
                }
                var report = "theme=\(t.id) \(t.name)\n"
                do {
                    let r = try repairTheme(t)
                    report += "changed=\(r.changed) flattened=\(r.flattened) "
                        + "removed=\(r.removedElements) regen=\(r.regeneratedLayout)\n"
                    report += r.summary + "\n"
                    if let t2 = Theme(dir: t.dir) {
                        report += "after icons=\(t2.icons.count) bg=\(t2.background ?? "nil") "
                            + "files=\(t2.fileCount) layout=\(t2.layout != nil)\n"
                    }
                } catch {
                    report += "ERR \(error.localizedDescription)\n"
                }
                try? report.write(toFile: base + "_repair.txt",
                                  atomically: true, encoding: .utf8)
            }
        }
        if args.contains("--bootadd") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                guard let t = ThemeLibrary.shared.themes.first else { return }
                let found = BootScanner.detect()
                var rep = "detected=\(found.count)\n"
                for e in found { rep += "  \(e.name) [\(e.kind)] -> \(e.iconStem)\n" }
                do {
                    let r = try addBootEntries(found, to: t)
                    rep += "added=\(r.added) layout=\(r.layoutUpdated)\n"
                    if let t2 = Theme(dir: t.dir) {
                        rep += "after icons=\(t2.icons.count)\n"
                        for ic in t2.icons { rep += "  \(ic.path) => \(ic.label)\n" }
                    }
                } catch {
                    rep += "ERR \(error.localizedDescription)\n"
                }
                try? rep.write(toFile: base + "_bootadd.txt",
                               atomically: true, encoding: .utf8)
            }
        }
        if let ni = args.firstIndex(of: "--newpreset"), ni + 1 < args.count {
            let pid = args[ni + 1]
            let preset = ThemePreset.all().first { $0.id == pid }
            var report = "presets=\(ThemePreset.all().map { $0.id }.joined(separator: ","))\n"
            do {
                let t = try makeTheme(name: "预设测试-\(pid)", preset: preset)
                report += "OK id=\(t.id) name=\(t.name) icons=\(t.icons.count) "
                    + "bg=\(t.background ?? "nil") layout=\(t.layout != nil) "
                    + "files=\(t.fileCount)\n"
                for ic in t.icons { report += "  icon \(ic.path) -> \(ic.label)\n" }
            } catch {
                report += "ERR \(error.localizedDescription)\n"
            }
            try? report.write(toFile: base + "_newpreset.txt", atomically: true, encoding: .utf8)
        }
        if args.contains("--design-test") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) { [weak self] in
                if let row = row { self?.mainWindow?.debugSelect(row) }
                self?.mainWindow?.debugOpenDesign()
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                    guard let mw = self?.mainWindow else { return }
                    mw.debugDesignAddText("可视化编辑验证")
                    mw.debugDesignMove(dx: 0.05, dy: -0.08)
                    mw.debugDesignResize(dw: 0.10, dh: 0.04)
                    mw.debugDesignFont("Helvetica Neue", size: 40)
                    mw.debugDesignPersist()
                    let dump = mw.debugDesignDump()
                    try? dump.write(toFile: base + "_design_layout.txt",
                                    atomically: true, encoding: .utf8)
                    mw.debugDesignExportPNG(to: base + "_design_export.png")
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
                        guard let w = NSApp.windows.first(where: {
                            $0.title.hasPrefix("可视化设计")
                        }), let cv = w.contentView else { return }
                        w.displayIfNeeded()
                        cv.layoutSubtreeIfNeeded()
                        self?.snapshot(cv, to: base + "_design_test.png")
                    }
                }
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 7) { [weak self] in
            guard let self = self, let w = self.mainWindow?.window else { return }
            NSApp.activate(ignoringOtherApps: true)
            w.makeKeyAndOrderFront(nil)
            if let row = row { self.mainWindow?.debugSelect(row) }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                guard let cv = w.contentView else { return }
                cv.window?.displayIfNeeded()
                cv.layoutSubtreeIfNeeded()
                self.dump(cv, to: base + ".txt")
                self.snapshot(cv, to: base + ".png")
            }
        }
    }

    private func dump(_ view: NSView, to path: String, depth: Int = 0) {
        var lines: [String] = []
        func walk(_ v: NSView, _ d: Int) {
            let f = v.frame
            lines.append(String(repeating: "  ", count: d) +
                "\(type(of: v)) frame=\(Int(f.origin.x)),\(Int(f.origin.y)) \(Int(f.width))x\(Int(f.height))" +
                " hidden=\(v.isHidden) layer=\(v.wantsLayer)")
            for s in v.subviews { walk(s, d + 1) }
        }
        walk(view, depth)
        try? lines.joined(separator: "\n").write(toFile: path, atomically: true, encoding: .utf8)
    }

    private func snapshot(_ view: NSView, to path: String) {
        let b = view.bounds
        guard b.width > 1, b.height > 1,
              let rep = NSBitmapImageRep(bitmapDataPlanes: nil,
                                         pixelsWide: Int(b.width), pixelsHigh: Int(b.height),
                                         bitsPerSample: 8, samplesPerPixel: 4,
                                         hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .deviceRGB,
                                         bytesPerRow: 0, bitsPerPixel: 0) else { return }
        rep.size = b.size
        NSGraphicsContext.saveGraphicsState()
        if let ctx = NSGraphicsContext(bitmapImageRep: rep) {
            NSGraphicsContext.current = ctx
            NSColor(calibratedWhite: 0.94, alpha: 1).setFill()
            NSBezierPath(rect: b).fill()
            view.cacheDisplay(in: b, to: rep)
        }
        NSGraphicsContext.restoreGraphicsState()
        try? rep.representation(using: .png, properties: [:])?
            .write(to: URL(fileURLWithPath: path))
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    private func buildMenu() {
        let menu = NSMenu()

        let appItem = NSMenuItem()
        menu.addItem(appItem)
        let appMenu = NSMenu()
        appItem.submenu = appMenu
        appMenu.addItem(withTitle: "关于 OC Theme Studio", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "隐藏 OC Theme Studio", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(.separator())
        let quit = NSMenuItem(title: "退出 OC Theme Studio", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appMenu.addItem(quit)

        let fileItem = NSMenuItem()
        menu.addItem(fileItem)
        let fileMenu = NSMenu(title: "文件")
        fileItem.submenu = fileMenu
        fileMenu.addItem(NSMenuItem(title: "导入主题包…", action: #selector(importZip(_:)), keyEquivalent: "o"))
        fileMenu.addItem(NSMenuItem(title: "导入文件夹…", action: #selector(importFolder(_:)), keyEquivalent: "O"))
        fileMenu.addItem(.separator())
        fileMenu.addItem(NSMenuItem(title: "编辑选中主题…", action: #selector(editTheme(_:)), keyEquivalent: "e"))
        fileMenu.addItem(NSMenuItem(title: "可视化设计…", action: #selector(designTheme(_:)), keyEquivalent: "d"))
        fileMenu.addItem(NSMenuItem(title: "重命名主题…", action: #selector(renameThemeAction(_:)), keyEquivalent: ""))
        fileMenu.addItem(NSMenuItem(title: "修复主题目录", action: #selector(repairThemeAction(_:)), keyEquivalent: ""))
        fileMenu.addItem(NSMenuItem(title: "识别系统启动项…", action: #selector(bootScanAction(_:)), keyEquivalent: "b"))
        fileMenu.addItem(NSMenuItem(title: "新建主题…", action: #selector(newTheme(_:)), keyEquivalent: "n"))
        fileMenu.addItem(NSMenuItem(title: "移除选中主题", action: #selector(removeTheme(_:)), keyEquivalent: "\u{8}"))
        fileMenu.addItem(.separator())
        fileMenu.addItem(NSMenuItem(title: "图片转 ICNS…", action: #selector(convertImage(_:)), keyEquivalent: "i"))
        fileMenu.addItem(NSMenuItem(title: "重新扫描 EFI", action: #selector(scanEFI(_:)), keyEquivalent: "r"))
        fileMenu.addItem(.separator())
        fileMenu.addItem(NSMenuItem(title: "关闭窗口", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w"))

        let toolsItem = NSMenuItem()
        menu.addItem(toolsItem)
        let toolsMenu = NSMenu(title: "工具")
        toolsItem.submenu = toolsMenu
        toolsMenu.addItem(NSMenuItem(title: "模拟引导启动…", action: #selector(openBootSimMenu(_:)), keyEquivalent: ""))
        toolsMenu.addItem(NSMenuItem(title: "主题商店…", action: #selector(openStoreMenu(_:)), keyEquivalent: ""))

        let helpItem = NSMenuItem()
        menu.addItem(helpItem)
        let helpMenu = NSMenu(title: "帮助")
        helpItem.submenu = helpMenu
        helpMenu.addItem(NSMenuItem(title: "使用说明", action: #selector(showHelp(_:)), keyEquivalent: "?"))

        NSApp.mainMenu = menu
        // Actions target the delegate (responder chain reaches it).
        for item in menu.items {
            for sub in item.submenu?.items ?? [] {
                if sub.action != nil && sub.target == nil,
                   sub.action != #selector(NSApplication.orderFrontStandardAboutPanel(_:)),
                   sub.action != #selector(NSApplication.hide(_:)),
                   sub.action != #selector(NSApplication.terminate(_:)),
                   sub.action != #selector(NSWindow.performClose(_:)) {
                    sub.target = self
                }
            }
        }
    }

    @objc func importZip(_ sender: Any?) { mainWindow?.chooseZip() }
    @objc func importFolder(_ sender: Any?) { mainWindow?.chooseFolder() }
    @objc func scanEFI(_ sender: Any?) { mainWindow?.scanEFI() }
    @objc func removeTheme(_ sender: Any?) { mainWindow?.removeSelectedTheme() }
    @objc func editTheme(_ sender: Any?) { mainWindow?.editSelectedTheme() }
    @objc func designTheme(_ sender: Any?) { mainWindow?.openDesignEditor() }
    @objc func renameThemeAction(_ sender: Any?) { mainWindow?.renameSelectedTheme() }
    @objc func repairThemeAction(_ sender: Any?) { mainWindow?.repairSelectedTheme() }
    @objc func bootScanAction(_ sender: Any?) { mainWindow?.scanBootEntries() }
    @objc func newTheme(_ sender: Any?) { mainWindow?.makeNewTheme() }
    @objc func showHelp(_ sender: Any?) { mainWindow?.showHelp() }
    @objc func convertImage(_ sender: Any?) { mainWindow?.openICNSConverter() }
    @objc func openBootSimMenu(_ sender: Any?) { mainWindow?.openBootSim() }
    @objc func openStoreMenu(_ sender: Any?) { mainWindow?.openStore() }

    /// Forward a store-downloaded theme to the main window's apply flow.
    func applyThemeFromStore(_ theme: Theme) {
        mainWindow?.applyThemeFromStore(theme)
    }
}
