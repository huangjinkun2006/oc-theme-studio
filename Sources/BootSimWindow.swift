import AppKit

// MARK: - Simulated boot / startup
//
// A full-screen overlay that mimics a real Hackintosh powering on, in three
// stages that mirror actual firmware boot:
//
//   1. BIOS / UEFI firmware logo  — the *real host* EFI logo, shown centred on
//      black just like a motherboard POST screen.
//   2. OpenCore Boot Picker       — rendered from the *currently selected*
//      library theme (its background + entries), so the OC shown is the user's
//      chosen theme. Arrow keys choose, Enter "boots".
//   3. Verbose boot               — selecting macOS + Enter scrolls a realistic
//      Hackintosh `-v` log (Lilu / VirtualSMC / WhateverGreen …) like a real
//      black-screen Mac.
//
// The real host theme is read from EFI/OC/Resources into a throwaway scratch
// directory so the user's theme library is never polluted.

private func simIsDir(_ u: URL) -> Bool {
    var d: ObjCBool = false
    return FileManager.default.fileExists(atPath: u.path, isDirectory: &d) && d.boolValue
}

private func getAutoBootSim() -> Bool {
    (jsonRead(Paths.state)?["autoBootSim"] as? Bool) ?? false
}

private func setAutoBootSim(_ on: Bool) {
    var obj = jsonRead(Paths.state) ?? [:]
    obj["autoBootSim"] = on
    try? jsonWrite(obj, to: Paths.state)
}

/// Copy the OpenCore theme currently on the host's EFI into a scratch folder
/// and return a Theme built from it. Returns nil when no EFI theme is mounted.
private func readHostTheme() -> Theme? {
    let scan = EFIScanResult.scan()
    guard let p = scan.best ?? scan.partitions.first(where: { $0.mounted }),
          p.mounted else { return nil }
    let base = URL(fileURLWithPath: p.mountPoint)
        .appendingPathComponent("EFI/OC/Resources", isDirectory: true)
    guard simIsDir(base) else { return nil }
    let fm = FileManager.default
    let subdirs = ["Image", "Font", "Label", "Audio", "Sound"]
    var sources: [URL] = []
    for sub in subdirs {
        let d = base.appendingPathComponent(sub, isDirectory: true)
        guard let items = try? fm.contentsOfDirectory(at: d, includingPropertiesForKeys: nil) else { continue }
        sources += items.filter { !simIsDir($0) }
    }
    let images = sources.filter {
        ["png", "icns", "jpg", "jpeg"].contains($0.pathExtension.lowercased())
    }
    guard !images.isEmpty else { return nil }
    let dest = Paths.scratch.appendingPathComponent("hostsim_\(UUID().uuidString)",
                                                   isDirectory: true)
    try? fm.createDirectory(at: dest, withIntermediateDirectories: true)
    for src in sources {
        let t = dest.appendingPathComponent(src.lastPathComponent)
        if !fm.fileExists(atPath: t.path) { try? fm.copyItem(at: src, to: t) }
    }
    var mf = buildManifest(dest, name: "本机 EFI 主题", source: "Host EFI · \(p.device)")
    mf["fromEfi"] = ["device": p.device, "mountPoint": p.mountPoint,
                     "imported": stamp("yyyy-MM-dd HH:mm")]
    try? jsonWrite(mf, to: dest.appendingPathComponent("manifest.json"))
    return Theme(dir: dest)
}

/// A realistic-looking Hackintosh OpenCore verbose boot log.
private let verboseLog: [String] = [
    "OpenCore v1.0.4 (UEFI) starting on 'iMac20,2' (Rev. 0x0)",
    "Asserting OpenCore image signature ... done",
    "OC: Loaded configuration of 9 entries",
    "OC: Init imgui...",
    "OC: Setting default boot entry to 'macOS'",
    "OC: Found 1 bootable filesystems",
    "OCB: Archiving loaded OpenCore image... done",
    "OCB: Loading Apple OC 1.0.4 (x64)...",
    "OCB: Booting from 'macOS' (asset 'EFI\\OC\\OpenCore.efi')",
    "OCB: Starting OpenCore...",
    "AAPL: [EB|LOG:INIT] 2026-11-13T09:26:48",
    "AAPL: [EB|VERSION] bootbase.efi 540.80.1~12",
    "AAPL: [EB|BUILD] BUILD-INFO[...]:2026-...",
    "AAPL: [EB|CFG:DEV] r5 0x0 0x0",
    "AAPL: [EB|H:IS] 0",
    "AAPL: [EB|WL] 0 0 0x01 0x01   0 0x00",
    "AAPL: [EB|BRD:NV] Mac-...",
    "AAPL: [EB|WL] 0 0 0x01 0x01   2 0x00",
    "AAPL: [EB|LOG:DT] 2026-11-13T09:26:48",
    "AAPL: [EB|CFG:ARG] console       -v",
    "AAPL: [EB|CFG:ARG] lpnu         e0",
    "AAPL: [EB|RHF] usr 0",
    "AAPL: [EB|LOC] 0",
    "AAPL: [EB|PMC] 0x0",
    "AAPL: [EB|KMR] 0x0",
    "AAPL: [EB|LD:LIM] 0x7fc00000",
    "AAPL: [EB|MEM] 0 0 0x7fc00000, 0x80000000",
    "apfs_module_start:1689: load: com.apple.filesystems.apfs",
    "com.apple.AppleFSCompressionTypeZlib kmod start",
    "com.apple.AppleFSCompressionTypeDataless kmod start",
    "com.apple.AppleSystemInfo kmod start",
    "Lilu.kext v1.6.7 starting in kernel mode",
    "Lilu: @ autodetected as macOS 14.5 (23F79)",
    "VirtualSMC.kext v1.3.2 starting in kernel mode",
    "VirtualSMC: EfiBoot started, platform Win32Unsupported",
    "VirtualSMC: dram freq 1333MHz, front side bus freq 100MHz",
    "WhateverGreen.kext v1.6.6 starting in kernel mode",
    "WhateverGreen: @ boot, igfx = 0x9bc8, fb = 0x0",
    "AppleALC.kext v1.9.0 starting in kernel mode",
    "AppleALC: @ layout 7 injected for codec 0x10ec0892",
    "VirtualSMC: RTVariables activated, emulating NVRAM",
    "kernel: (AppleACPIPlatform) ACPI: EC already present",
    "kernel: (AppleAPIC) Local APIC version 0x10",
    "kernel: (AppleRTC) RTC: only singlestepping on ancient hardware",
    "kernel: (IOPCIFamily) PCI configuration begin",
    "kernel: (IOPCIFamily) mcfg 0xF0000000, segn 0, bus 0",
    "kernel: (AppleIntelCFLGraphics) Framebuffer patched by WhateverGreen",
    "kernel: (AppleIntelFramebuffer) Using ig-platform-id 07009B3E",
    "apfs: mount_apfs: mount starting",
    "apfs: volume 'Macintosh HD - Data' mounted (role 0x1)",
    "apfs: volume 'Macintosh HD' mounted (role 0x0)",
    "BSD root: disk1s5, major 1, minor 5",
    "IOConsoleUsers: time(0) 0->0, lin 0, llk 1,",
    "IOConsoleUsers: gIOScreenLockState 3, hs 0, bs 0, now 0, sm 0x0",
    "IOConsoleUsers: UI initialized, cnt 1",
    "hidedisk: disk1s5 hidden from desktop",
    "systemstats: snapshot taken",
    "configd[17]: bootp_session_init",
    "launchd[1]: *** 3 services failed to init",
    "kernel: (Sandbox) 0 deviations detected",
    "running boot hooks...",
    "Setting hostname: hackintosh.local",
    "loginwindow: Login window ready",
    "DSMOS has arrived",
    "AAPL: [EB|LOG:EXIT] 2026-11-13T09:26:53",
]

private enum SimPhase { case bios, picker, verbose }

final class BootSimWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

final class BootSimView: NSView {
    override var isFlipped: Bool { true }
    /// OpenCore theme shown in the picker — the *currently selected* library theme.
    var theme: Theme? { didSet { picker.theme = theme; picker.designLayout = theme?.layout; needsDisplay = true } }
    /// Firmware / motherboard logo shown first — the *real host* EFI theme.
    var logoTheme: Theme?
    fileprivate var phase: SimPhase = .bios { didSet { applyPhase() } }

    private let picker = BootPickerView()
    private let hint = UI.label("", size: 12.5, weight: .medium,
                                color: .white, align: .center)
    private let autoChk = NSButton(checkboxWithTitle: "下次启动软件时自动模拟", target: nil, action: nil)
    private var progress: CGFloat = 0
    private var progressTimer: Timer?
    private var verboseLines: [String] = []
    private var verboseIndex = 0
    private var bootLabel = ""
    private var onExit: (() -> Void)?
    private var onBoot: ((String) -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        picker.wantsLayer = true
        hint.wantsLayer = true
        hint.layer?.backgroundColor = NSColor(calibratedWhite: 0, alpha: 0.42).cgColor
        hint.layer?.cornerRadius = 7
        autoChk.title = "下次启动软件时自动模拟"
        autoChk.font = .systemFont(ofSize: 11)
        autoChk.state = getAutoBootSim() ? .on : .off
        autoChk.target = self
        autoChk.action = #selector(toggleAuto)
        autoChk.wantsLayer = true
        autoChk.layer?.backgroundColor = NSColor(calibratedWhite: 0, alpha: 0.32).cgColor
        autoChk.layer?.cornerRadius = 6
        addSubview(picker)
        addSubview(hint)
        addSubview(autoChk)
        picker.isHidden = true
        applyPhase()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) unsupported") }

    override var acceptsFirstResponder: Bool { true }

    func configure(bootTheme: Theme?, logoTheme: Theme?,
                   onExit: @escaping () -> Void, onBoot: @escaping (String) -> Void) {
        self.theme = bootTheme
        self.logoTheme = logoTheme
        self.onExit = onExit
        self.onBoot = onBoot
        startBios()
    }

    private func applyPhase() {
        picker.isHidden = (phase != .picker)
        hint.isHidden = (phase == .verbose)
        autoChk.isHidden = (phase != .picker)
        if phase == .bios {
            hint.stringValue = "正在加载主板固件…（点击或按任意键跳过）"
        } else if phase == .picker {
            hint.stringValue = "← → 选择启动项   ·   Enter 启动   ·   Esc 退出"
        }
        needsDisplay = true
    }

    /// Phase 1: motherboard / firmware POST logo (the real host EFI logo) centred
    /// on black, exactly like a board's BIOS splash, then enter OpenCore.
    private func startBios() {
        phase = .bios
        progress = 0
        progressTimer?.invalidate()
        progressTimer = Timer.scheduledTimer(withTimeInterval: 0.03, repeats: true) { [weak self] t in
            guard let self = self else { t.invalidate(); return }
            self.progress = min(1, self.progress + 0.016)
            self.needsDisplay = true
            if self.progress >= 1 {
                t.invalidate()
                self.phase = .picker
            }
        }
    }

    func skipToPicker() {
        guard phase == .bios else { return }
        progressTimer?.invalidate()
        phase = .picker
    }

    func startBoot(_ label: String) {
        guard phase == .picker else { return }
        bootLabel = label
        verboseLines = []
        verboseIndex = 0
        phase = .verbose
        startVerbose()
    }

    /// Phase 3: scroll a realistic Hackintosh verbose boot log.
    private func startVerbose() {
        verboseTimerInvalidate()
        verboseTimer = Timer.scheduledTimer(withTimeInterval: 0.035, repeats: true) { [weak self] t in
            guard let self = self else { t.invalidate(); return }
            let step = 1 + Int.random(in: 0...1)
            for _ in 0..<step where self.verboseIndex < verboseLog.count {
                self.verboseLines.append(verboseLog[self.verboseIndex])
                self.verboseIndex += 1
            }
            self.needsDisplay = true
            if self.verboseIndex >= verboseLog.count { t.invalidate() }
        }
    }

    private var verboseTimer: Timer?
    private func verboseTimerInvalidate() { verboseTimer?.invalidate() }

    func abortBoot() {
        verboseTimerInvalidate()
        phase = .picker
    }

    @objc private func toggleAuto() {
        setAutoBootSim(autoChk.state == .on)
    }

    override func layout() {
        super.layout()
        picker.frame = bounds
        let w: CGFloat = min(560, bounds.width - 80)
        hint.frame = NSRect(x: (bounds.width - w) / 2, y: bounds.height - 52,
                            width: w, height: 26)
        autoChk.frame = NSRect(x: 16, y: 14, width: 280, height: 20)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        NSColor.black.setFill()
        bounds.fill()
        if phase == .bios { drawBios(in: bounds) }
        else if phase == .verbose { drawVerbose(in: bounds) }
    }

    /// Firmware POST splash: the real host EFI logo centred on black, with a
    /// progress ring and a faux BIOS hint line at the bottom.
    private func drawBios(in b: NSRect) {
        NSColor.black.setFill()
        b.fill()

        let box = min(b.width, b.height) * 0.22
        let logo: NSImage? = logoTheme?.logoImage

        if let lg = logo, lg.size.width > 0, lg.size.height > 0 {
            let s = lg.size
            let scale = box / max(s.width, s.height)
            let w = s.width * scale, h = s.height * scale
            let origin = NSPoint(x: b.midX - w / 2, y: b.midY - h / 2 - box * 0.18)
            lg.draw(in: NSRect(x: origin.x, y: origin.y, width: w, height: h),
                    from: .zero, operation: .sourceOver, fraction: 1,
                    respectFlipped: true, hints: [.interpolation: NSImageInterpolation.high])
        } else {
            // No host EFI logo available: a generic UEFI BIOS splash.
            NSGradient(starting: NSColor(calibratedRed: 0.04, green: 0.10, blue: 0.22, alpha: 1),
                       ending: NSColor(calibratedRed: 0.01, green: 0.03, blue: 0.08, alpha: 1))?
                .draw(in: b, angle: -90)
            let title = "UEFI BIOS"
            let tattrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 34, weight: .bold),
                .foregroundColor: NSColor.white.withAlphaComponent(0.92),
            ]
            let ts = (title as NSString).size(withAttributes: tattrs)
            (title as NSString).draw(at: NSPoint(x: b.midX - ts.width / 2, y: b.midY - 30),
                                    withAttributes: tattrs)
        }

        // Boot progress ring beneath the logo.
        let c = NSPoint(x: b.midX, y: b.midY + box * 0.5 + 22)
        let r: CGFloat = 22
        NSColor(calibratedWhite: 1, alpha: 0.18).setStroke()
        NSBezierPath(ovalIn: NSRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
            .stroke()
        let arc = NSBezierPath()
        arc.appendArc(withCenter: c, radius: r,
                      startAngle: -90,
                      endAngle: -90 + 360 * Double(progress))
        NSColor(calibratedWhite: 1, alpha: 0.9).setStroke()
        arc.lineWidth = 3
        arc.stroke()

        // Faux BIOS hot-key hint at the bottom.
        let hint1 = "Press F2: Setup     F11: Boot Menu     F12: Network"
        let hattrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12, weight: .regular),
            .foregroundColor: NSColor.white.withAlphaComponent(0.55),
        ]
        let hs = (hint1 as NSString).size(withAttributes: hattrs)
        (hint1 as NSString).draw(at: NSPoint(x: b.midX - hs.width / 2, y: b.height - 40),
                                 withAttributes: hattrs)
    }

    /// Verbose boot: scrolling Hackintosh `-v` log, anchored at the bottom like
    /// a real terminal, plus a header naming the booted entry.
    private func drawVerbose(in b: NSRect) {
        NSColor.black.setFill()
        b.fill()

        let topInset: CGFloat = 40
        let bottomInset: CGFloat = 24
        let fontSize: CGFloat = 12
        let lineH: CGFloat = 16
        let font = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor(calibratedWhite: 0.82, alpha: 1),
        ]

        // Header.
        let header = "Booting \(bootLabel)  (verbose / -v)"
        let hattrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 13, weight: .medium),
            .foregroundColor: NSColor(calibratedWhite: 0.95, alpha: 1),
        ]
        (header as NSString).draw(at: NSPoint(x: 24, y: 14), withAttributes: hattrs)

        let usable = b.height - topInset - bottomInset
        let maxLines = max(1, Int(usable / lineH))
        let tail = verboseLines.suffix(maxLines)
        var y = b.height - bottomInset - CGFloat(tail.count) * lineH
        for line in tail {
            (line as NSString).draw(at: NSPoint(x: 24, y: y), withAttributes: attrs)
            y += lineH
        }

        // Completion marker once the whole log has scrolled past.
        if verboseIndex >= verboseLog.count {
            let done = "✓ \(bootLabel) 启动完成 — 按 Esc 退出"
            let dattrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.monospacedSystemFont(ofSize: 13, weight: .medium),
                .foregroundColor: NSColor(srgbRed: 0.45, green: 0.85, blue: 0.45, alpha: 1),
            ]
            (done as NSString).draw(at: NSPoint(x: 24, y: y + 6), withAttributes: dattrs)
        }
    }

    override func mouseDown(with event: NSEvent) {
        if phase == .bios { skipToPicker() }
    }

    override func keyDown(with event: NSEvent) {
        switch phase {
        case .bios:
            skipToPicker()
        case .picker:
            switch event.keyCode {
            case 53: // Esc
                onExit?()
            case 36, 76: // Enter / Return
                let icons = theme?.icons ?? []
                let label = (icons.indices.contains(picker.selectedIndex)
                    ? icons[picker.selectedIndex].label : "选中项")
                startBoot(label)
            case 123: // Left
                picker.selectedIndex = max(0, picker.selectedIndex - 1)
            case 124: // Right
                picker.selectedIndex = min((theme?.icons.count ?? 1) - 1, picker.selectedIndex + 1)
            default:
                break
            }
        case .verbose:
            if event.keyCode == 53 { abortBoot() }
        }
    }
}

final class BootSimWindowController: NSWindowController {
    private var simView: BootSimView?
    var onClosed: (() -> Void)?
    private let hostTheme: Theme?

    init(fallback: Theme?) {
        hostTheme = readHostTheme()
        let screen = NSScreen.main?.frame ?? NSRect(x: 0, y: 0, width: 1280, height: 720)
        let win = BootSimWindow(contentRect: screen,
                                styleMask: [.borderless, .fullSizeContentView],
                                backing: .buffered, defer: false)
        win.backgroundColor = .black
        win.isOpaque = true
        win.hasShadow = false
        win.level = .modalPanel
        win.collectionBehavior = [.fullScreenAuxiliary, .canJoinAllSpaces]
        win.title = "模拟引导启动"
        let view = BootSimView(frame: NSRect(origin: .zero, size: screen.size))
        win.contentView = view
        super.init(window: win)
        // OpenCore picker = the *currently selected* theme; firmware logo = real host.
        let bootTheme = fallback
        view.configure(bootTheme: bootTheme, logoTheme: hostTheme,
                       onExit: { [weak self] in self?.closeBoot() },
                       onBoot: { [weak self] label in self?.closeBoot() })
        simView = view
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) unsupported") }

    func showBoot() {
        window?.makeKeyAndOrderFront(nil)
        window?.makeFirstResponder(simView)
    }

    func closeBoot() {
        window?.orderOut(nil)
        onClosed?()
    }
}
