import Foundation

// MARK: - Models

struct EFIPartition {
    let device: String
    let parent: String
    let volumeName: String
    let size: Int64
    let sizeText: String
    let mountPoint: String
    let mounted: Bool
    let sameDisk: Bool
    let hasOC: Bool
    let hasConfig: Bool
    var current: Bool = false

    /// Text shown in the EFI list.
    var title: String { device + (volumeName.isEmpty ? "" : " · " + volumeName) }
}

struct EFIScanResult {
    var physicalDisk: String = ""
    var rootVolume: String = ""
    var partitions: [EFIPartition] = []
    var privileged: Bool = false
    var ambiguous: Bool = false
    var systemDiskEfiCount: Int = 0

    var best: EFIPartition? { partitions.first { $0.current } }
}

struct EFIInspect {
    var mountPoint: String = ""
    var ocPath: String = ""
    var configPath: String = ""
    var hasOC = false
    var hasConfig = false
    var openCoreEfi = false
    var bootEfi = false
    var resources: [String: Int] = [:]
    var pickerMode: String = ""
    var pickerVariant: String = ""
    var configError: String = ""
    var canopyInConfig = false
    var canopyDriverFile = false
    var imageVariantPresent = false

    /// True when the graphical picker has everything it needs.
    var graphicalReady: Bool {
        pickerMode == "External" && canopyInConfig && canopyDriverFile && imageVariantPresent
    }

    var totalResources: Int { resources.values.filter { $0 > 0 }.reduce(0, +) }
}

struct BackupItem {
    let id: String
    let dir: URL
    let time: String
    let device: String
    let mountPoint: String
    let theme: String
    let sizeText: String
    let hasResources: Bool
}

struct ActionResult {
    var ok: Bool
    var message: String
    var backupId: String = ""
    var preRestoreBackup: String = ""
    var inspect: EFIInspect? = nil
    var scan: EFIScanResult? = nil

    static func fail(_ s: String) -> ActionResult { ActionResult(ok: false, message: s) }
    static func success(_ s: String) -> ActionResult { ActionResult(ok: true, message: s) }
}

// MARK: - EFI engine

private func efiIsDir(_ u: URL) -> Bool {
    var d: ObjCBool = false
    return FileManager.default.fileExists(atPath: u.path, isDirectory: &d) && d.boolValue
}

private func efiIsFile(_ u: URL) -> Bool {
    var d: ObjCBool = false
    return FileManager.default.fileExists(atPath: u.path, isDirectory: &d) && !d.boolValue
}

private func diskutilInfo(_ arg: String) -> [String: Any]? {
    let r = shellRun("/usr/sbin/diskutil", ["info", "-plist", arg], timeout: 30)
    guard r.ok, let d = r.out.data(using: .utf8) else { return nil }
    return plistRead(d)
}

private func diskutilList() -> [String: Any]? {
    let r = shellRun("/usr/sbin/diskutil", ["list", "-plist"], timeout: 30)
    guard r.ok, let d = r.out.data(using: .utf8) else { return nil }
    return plistRead(d)
}

private func asDict(_ v: Any?) -> [String: Any] { v as? [String: Any] ?? [:] }
private func asArray(_ v: Any?) -> [[String: Any]] { v as? [[String: Any]] ?? [] }
private func asString(_ v: Any?) -> String {
    if let s = v as? String { return s }
    if let n = v as? NSNumber { return n.stringValue }
    return ""
}
private func asInt(_ v: Any?) -> Int64 {
    if let n = v as? NSNumber { return n.int64Value }
    if let s = v as? String { return Int64(s) ?? 0 }
    return 0
}

/// OpenCore resolves `PickerVariant` as a UEFI path relative to
/// EFI/OC/Resources/Image, e.g. `Acidanthera\GoldenGate` (backslash!).
/// The importer uses "/" internally, so normalise here and return both the
/// config value and the matching filesystem relative directory. `Auto`
/// resolves to the default Acidanthera\GoldenGate set.
private func variantLayout(_ raw: String, fallback: String) -> (config: String, relative: String) {
    var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    if s.isEmpty { s = fallback }
    if s.isEmpty { s = "Acidanthera/GoldenGate" }
    s = s.replacingOccurrences(of: "\\", with: "/")
    var parts = s.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
    parts = parts.filter { $0 != "." && $0 != ".." && !$0.hasPrefix(".") }
    if parts.isEmpty { parts = ["Acidanthera", "GoldenGate"] }
    if parts.count == 1 {
        if parts[0].lowercased() == "auto" {
            return ("Auto", "Acidanthera/GoldenGate")
        }
        parts.insert("Acidanthera", at: 0)
    }
    return (parts.joined(separator: "\\"), parts.joined(separator: "/"))
}

/// `UEFI -> Drivers` may contain plain strings or dictionaries with
/// Path / Enabled. OpenCanopy must be both listed and enabled.
private func canopyEnabled(_ pl: [String: Any]) -> Bool {
    let drivers = asDict(pl["UEFI"])["Drivers"] as? [Any] ?? []
    for raw in drivers {
        if let s = raw as? String {
            if s.lowercased() == "opencanopy.efi" { return true }
        } else {
            let d = raw as? [String: Any] ?? [:]
            let enabled = d["Enabled"] as? Bool ?? true
            if enabled && asString(d["Path"]).lowercased() == "opencanopy.efi" { return true }
        }
    }
    return false
}

/// "disk3" out of "disk3s2" / "disk3s2s1".
private func wholeDisk(_ s: String) -> String? {
    let pattern = "^(disk[0-9]+)"
    guard let r = s.range(of: pattern, options: .regularExpression) else { return nil }
    return String(s[r])
}

private func validDevice(_ s: String) -> Bool {
    s.range(of: "^disk[0-9]+s[0-9]+$", options: .regularExpression) != nil
}

private func mountedOCProbe(_ mount: String) -> (hasOC: Bool, hasConfig: Bool) {
    guard !mount.isEmpty else { return (false, false) }
    let oc = URL(fileURLWithPath: mount).appendingPathComponent("EFI/OC", isDirectory: true)
    return (efiIsDir(oc), efiIsFile(oc.appendingPathComponent("config.plist")))
}

// MARK: Scan

extension EFIScanResult {
    static func scan() -> EFIScanResult {
        var result = EFIScanResult()
        result.privileged = geteuid() == 0

        let info = diskutilInfo("/") ?? [:]
        let stores = asArray(info["APFSPhysicalStores"])
        var physical = ""
        if let first = stores.first {
            physical = wholeDisk(asString(first["APFSPhysicalStore"])) ?? ""
        }
        if physical.isEmpty {
            physical = wholeDisk(asString(info["ParentWholeDisk"])) ??
                       wholeDisk(asString(info["DeviceIdentifier"])) ?? ""
        }
        result.physicalDisk = physical
        result.rootVolume = asString(info["VolumeName"])

        let disks = asArray(diskutilList()?["AllDisksAndPartitions"])
        var scored: [(entry: EFIPartition, score: Int)] = []

        for disk in disks {
            for part in asArray(disk["Partitions"]) {
                // diskutil reports "EFI" as the Content of ESP partitions.
                guard asString(part["Content"]) == "EFI" else { continue }
                let dev = asString(part["DeviceIdentifier"])
                guard !dev.isEmpty else { continue }
                let mount = asString(diskutilInfo(dev)?["MountPoint"])
                let probe = mountedOCProbe(mount)
                let vol = asString(part["VolumeName"])
                let onSys = !physical.isEmpty && wholeDisk(dev) == physical
                var score = 0
                if onSys { score += 100 }
                if probe.hasConfig { score += 80 }
                else if probe.hasOC { score += 40 }
                let lowVol = vol.lowercased()
                if lowVol.contains("esp") || lowVol.contains("efi") { score += 15 }
                if dev.hasSuffix("s1") { score += 8 }
                if !mount.isEmpty { score += 3 }

                let entry = EFIPartition(
                    device: dev,
                    parent: asString(disk["DeviceIdentifier"]),
                    volumeName: vol,
                    size: asInt(part["Size"]),
                    sizeText: humanSize(asInt(part["Size"])),
                    mountPoint: mount,
                    mounted: !mount.isEmpty,
                    sameDisk: onSys,
                    hasOC: probe.hasOC,
                    hasConfig: probe.hasConfig)
                scored.append((entry, score))
            }
        }

        let best = scored.map(\.score).max() ?? 0
        result.systemDiskEfiCount = scored.filter { $0.entry.sameDisk }.count
        result.ambiguous = result.systemDiskEfiCount > 1
        result.partitions = scored.map { item in
            var e = item.entry
            e.current = best > 0 && item.score == best
            return e
        }.sorted {
            if $0.current != $1.current { return $0.current }
            if $0.sameDisk != $1.sameDisk { return $0.sameDisk }
            return $0.device < $1.device
        }
        return result
    }
}

// MARK: Validation / inspection

enum EFIError: LocalizedError {
    case message(String)
    var errorDescription: String? {
        switch self { case .message(let s): return s }
    }
}

private func validateMount(_ mount: String) throws -> String {
    let p = URL(fileURLWithPath: mount).standardizedFileURL.path
    guard p.hasPrefix("/Volumes/") && p != "/Volumes" else {
        throw EFIError.message("挂载点无效：只允许 /Volumes 下的 EFI 卷")
    }
    guard efiIsDir(URL(fileURLWithPath: p)) else {
        throw EFIError.message("挂载点不存在，请先挂载 EFI 分区")
    }
    return p
}

extension EFIInspect {
    static func inspect(mount: String) throws -> EFIInspect {
        let mp = try validateMount(mount)
        var r = EFIInspect(mountPoint: mp)
        let oc = URL(fileURLWithPath: mp).appendingPathComponent("EFI/OC", isDirectory: true)
        r.ocPath = oc.path
        r.hasOC = efiIsDir(oc)
        r.openCoreEfi = efiIsFile(oc.appendingPathComponent("OpenCore.efi"))
        r.bootEfi = efiIsFile(URL(fileURLWithPath: mp)
            .appendingPathComponent("EFI/BOOT/BOOTx64.efi"))
        let cfg = oc.appendingPathComponent("config.plist")
        if efiIsFile(cfg) {
            r.hasConfig = true
            r.configPath = cfg.path
            if let data = try? Data(contentsOf: cfg), let pl = plistRead(data) {
                let boot = asDict(asDict(pl["Misc"])["Boot"])
                r.pickerMode = asString(boot["PickerMode"])
                r.pickerVariant = asString(boot["PickerVariant"])
                r.canopyInConfig = canopyEnabled(pl)
            } else {
                r.configError = "config.plist 无法解析"
            }
        }
        let res = oc.appendingPathComponent("Resources", isDirectory: true)
        if efiIsDir(res) {
            for sub in ["Image", "Font", "Label", "Sound"] {
                let d = res.appendingPathComponent(sub, isDirectory: true)
                if !efiIsDir(d) { r.resources[sub] = 0; continue }
                let items = (try? FileManager.default.contentsOfDirectory(atPath: d.path)) ?? []
                r.resources[sub] = items.filter { !$0.hasPrefix(".") }.count
            }
        }
        r.canopyDriverFile = efiIsFile(oc.appendingPathComponent("Drivers/OpenCanopy.efi"))
        // A PickerVariant pointing at a directory that no longer exists is the
        // single most common reason OpenCore silently shows the text picker.
        let layout = variantLayout(r.pickerVariant, fallback: "")
        var variantDir = res.appendingPathComponent("Image", isDirectory: true)
        for c in layout.relative.split(separator: "/").map(String.init) {
            variantDir.appendPathComponent(c, isDirectory: true)
        }
        r.imageVariantPresent = efiIsDir(variantDir)
        return r
    }
}

// MARK: Mount / unmount

enum EFIActions {
    private static let fm = FileManager.default

    static func mount(device dev: String) -> ActionResult {
        guard validDevice(dev) else { return .fail("无效的分区标识") }
        let done = runRoot(["/usr/sbin/diskutil mount " + shq(dev)])
        if !done.ok { return .fail(done.message) }
        return ActionResult(ok: true, message: "已挂载 \(dev)", scan: EFIScanResult.scan())
    }

    static func unmount(device dev: String) -> ActionResult {
        guard validDevice(dev) else { return .fail("无效的分区标识") }
        let done = runRoot(["/usr/sbin/diskutil unmount " + shq(dev)])
        if !done.ok { return .fail(done.message) }
        return ActionResult(ok: true, message: "已卸载 \(dev)", scan: EFIScanResult.scan())
    }

    /// Confirm that the chosen mount point really belongs to the chosen device.
    private static func verify(device dev: String, mount: String) throws -> String {
        guard validDevice(dev) else { throw EFIError.message("无效的分区标识") }
        let mp = try validateMount(mount)
        guard let info = diskutilInfo(dev) else { throw EFIError.message("无法确认 EFI 设备") }
        let actual = asString(info["MountPoint"])
        guard !actual.isEmpty,
              URL(fileURLWithPath: actual).standardizedFileURL.path == mp else {
            throw EFIError.message("设备与挂载点不匹配，请重新扫描")
        }
        return mp
    }

    private static func copyTree(_ src: URL, _ dst: URL) throws {
        try fm.createDirectory(at: dst, withIntermediateDirectories: true)
        // The enumerator may return symlink-resolved absolute paths
        // (e.g. /private/tmp/... while `src` is /tmp/...). Resolve both sides
        // before computing the relative path, otherwise every nested item
        // falls back to `lastPathComponent` and the whole tree gets flattened.
        let base = src.resolvingSymlinksInPath().standardizedFileURL.path
        guard let e = fm.enumerator(at: src, includingPropertiesForKeys: nil,
                                    options: [.skipsHiddenFiles]) else { return }
        for case let u as URL in e {
            let full = u.resolvingSymlinksInPath().standardizedFileURL.path
            guard full.hasPrefix(base + "/") else { continue }
            let rel = String(full.dropFirst(base.count + 1))
            let target = dst.appendingPathComponent(rel)
            if efiIsDir(u) {
                try fm.createDirectory(at: target, withIntermediateDirectories: true)
            } else if !efiIsFile(target) {
                try fm.copyItem(at: u, to: target)
            }
        }
    }

    private static func makeBackup(oc: URL, device: String, mount: String,
                                   theme: String, suffix: String) throws -> BackupItem {
        Paths.ensure()
        let id = stamp("yyyyMMdd-HHmmss") + "-" + suffix
        let dir = Paths.backups.appendingPathComponent(id, isDirectory: true)
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        let res = oc.appendingPathComponent("Resources", isDirectory: true)
        let hasRes = efiIsDir(res)
        if hasRes { try copyTree(res, dir.appendingPathComponent("Resources", isDirectory: true)) }
        let cfg = oc.appendingPathComponent("config.plist")
        if efiIsFile(cfg) { try fm.copyItem(at: cfg, to: dir.appendingPathComponent("config.plist")) }
        let meta: [String: Any] = [
            "time": stamp("yyyy-MM-dd HH:mm:ss"),
            "device": device,
            "mountPoint": mount,
            "theme": theme,
            "hasResources": hasRes,
            "sizeText": humanSize(sizeOfDirectory(dir)),
        ]
        try jsonWrite(meta, to: dir.appendingPathComponent("backup.json"))
        return BackupItem(id: id, dir: dir, time: meta["time"] as? String ?? "",
                          device: device, mountPoint: mount, theme: theme,
                          sizeText: meta["sizeText"] as? String ?? "", hasResources: hasRes)
    }

    static func listBackups() -> [BackupItem] {
        let items = (try? fm.contentsOfDirectory(at: Paths.backups,
                                                 includingPropertiesForKeys: nil)) ?? []
        return items.filter { efiIsDir($0) }.compactMap { dir in
            let meta = jsonRead(dir.appendingPathComponent("backup.json")) ?? [:]
            return BackupItem(id: dir.lastPathComponent, dir: dir,
                              time: meta["time"] as? String ?? "",
                              device: meta["device"] as? String ?? "",
                              mountPoint: meta["mountPoint"] as? String ?? "",
                              theme: meta["theme"] as? String ?? dir.lastPathComponent,
                              sizeText: meta["sizeText"] as? String ?? "",
                              hasResources: meta["hasResources"] as? Bool ?? false)
        }.sorted { $0.id > $1.id }
    }

    // MARK: EFI 配置包（按分区导出 / 安装）

    /// 从已选中的 EFI 分区生成可公开分享的配置包。
    /// 只包含 EFI/OC/Resources 与一个最小的 config.plist（PickerMode / PickerVariant），
    /// 明确排除 PlatformInfo、NVRAM、ACPI、Kexts、Drivers、Tools 等机器相关内容。
    static func makeConfigPackage(device dev: String, mount: String, to zip: URL) throws -> URL {
        let mp = try verify(device: dev, mount: mount)
        let oc = URL(fileURLWithPath: mp).appendingPathComponent("EFI/OC", isDirectory: true)
        let volume = asString(diskutilInfo(dev)?["VolumeName"])
        return try makeConfigPackage(oc: oc, volumeName: volume, to: zip)
    }

    /// 内部实现：只依赖一个 EFI/OC 目录，便于离线验证打包内容而不必挂载真实分区。
    static func makeConfigPackage(oc: URL, volumeName: String, to zip: URL) throws -> URL {
        guard efiIsDir(oc) else {
            throw EFIError.message("该 EFI 分区中未找到 EFI/OC 目录，请确认选择了正确的分区")
        }
        let cfg = oc.appendingPathComponent("config.plist")
        guard let cfgData = try? Data(contentsOf: cfg), let pl = plistRead(cfgData) else {
            throw EFIError.message("未找到或无法解析 EFI/OC/config.plist")
        }
        let res = oc.appendingPathComponent("Resources", isDirectory: true)
        guard efiIsDir(res) else {
            throw EFIError.message("该分区没有 EFI/OC/Resources，无法生成 EFI 配置包")
        }

        let stage = Paths.scratch.appendingPathComponent(
            "efi_pkg_" + UUID().uuidString, isDirectory: true)
        defer { try? fm.removeItem(at: stage) }
        try fm.createDirectory(at: stage, withIntermediateDirectories: true)
        let stageOC = stage.appendingPathComponent("EFI/OC", isDirectory: true)
        try fm.createDirectory(at: stageOC, withIntermediateDirectories: true)
        try copyTree(res, stageOC.appendingPathComponent("Resources", isDirectory: true))

        let misc = asDict(pl["Misc"])
        let boot = asDict(misc["Boot"])
        let mode = asString(boot["PickerMode"])
        let variant = variantLayout(asString(boot["PickerVariant"]), fallback: "")
        let minimal: [String: Any] = [
            "Misc": ["Boot": [
                "PickerMode": mode.isEmpty ? "External" : mode,
                "PickerVariant": variant.config,
            ]]
        ]
        let outCfg = try PropertyListSerialization.data(fromPropertyList: minimal,
                                                         format: .xml, options: 0)
        try outCfg.write(to: stageOC.appendingPathComponent("config.plist"))

        let manifest: [String: Any] = [
            "kind": "oc-efi-config",
            "version": 1,
            "created": stamp("yyyy-MM-dd HH:mm:ss"),
            "sourceVolume": volumeName,
            "pickerMode": mode.isEmpty ? "External" : mode,
            "pickerVariant": variant.config,
            "variantRelative": variant.relative,
            "includes": ["EFI/OC/Resources", "EFI/OC/config.plist (minimal)"],
            "excluded": ["PlatformInfo", "NVRAM", "ACPI", "Kexts", "Drivers",
                         "Tools", "UEFI", "DeviceProperties", "Booter"],
            "target": "EFI/OC",
        ]
        try jsonWrite(manifest, to: stage.appendingPathComponent("oc-efi-manifest.json"))

        if fm.fileExists(atPath: zip.path) { try fm.removeItem(at: zip) }
        let r = shellRun("/usr/bin/ditto",
                         ["-c", "-k", "--norsrc", "--noextattr", stage.path, zip.path],
                         timeout: 240)
        if !r.ok {
            throw EFIError.message("打包失败：" + (r.err.isEmpty ? r.out : r.err))
        }
        return zip
    }

    /// 只把包里的 PickerMode / PickerVariant 合并进目标 config.plist，
    /// 其余键值（PlatformInfo / NVRAM / ACPI / Kernel / UEFI / …）原样保留。
    static func mergePickerSettings(target pl: [String: Any],
                                    packageBoot: [String: Any],
                                    variant configValue: String) -> [String: Any] {
        var out = pl
        var misc = asDict(out["Misc"])
        var boot = asDict(misc["Boot"])
        let mode = asString(packageBoot["PickerMode"])
        boot["PickerMode"] = mode.isEmpty ? "External" : mode
        boot["PickerVariant"] = configValue
        misc["Boot"] = boot
        out["Misc"] = misc
        return out
    }

    private static func packageRoot(in dir: URL) throws -> URL {
        if fm.fileExists(atPath: dir.appendingPathComponent("oc-efi-manifest.json").path) {
            return dir
        }
        let children = (try? fm.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: nil)) ?? []
        for c in children where efiIsDir(c) {
            if fm.fileExists(atPath: c.appendingPathComponent("oc-efi-manifest.json").path) {
                return c
            }
        }
        throw EFIError.message("EFI 配置包缺少 oc-efi-manifest.json，已中止安装")
    }

    /// 把下载的 EFI 配置包写入用户所选的目标 EFI 分区。
    /// 只合并 PickerMode / PickerVariant，不覆盖机器相关配置；写入前自动备份。
    static func installConfigPackage(zip: URL, device dev: String, mount: String) -> ActionResult {
        do {
            let mp = try verify(device: dev, mount: mount)
            let oc = URL(fileURLWithPath: mp).appendingPathComponent("EFI/OC", isDirectory: true)
            return try installConfigPackage(zip: zip, oc: oc, device: dev, mount: mp)
        } catch {
            return .fail(error.localizedDescription)
        }
    }

    /// 内部实现：只依赖目标 EFI/OC 目录，便于离线 dry-run 验证安装脚本，
    /// 不必挂载真实 EFI 分区。公开入口仍会先做 device / mount 一致性校验。
    static func installConfigPackage(zip: URL, oc: URL, device dev: String,
                                     mount: String) throws -> ActionResult {
        do {
            guard efiIsDir(oc) else {
                throw EFIError.message("目标分区中未找到 EFI/OC 目录，已中止安装")
            }
            let cfg = oc.appendingPathComponent("config.plist")
            guard let cfgData = try? Data(contentsOf: cfg), let pl = plistRead(cfgData) else {
                throw EFIError.message("目标分区的 config.plist 不存在或无法解析，已中止安装")
            }

            let extract = Paths.scratch.appendingPathComponent(
                "efi_install_" + UUID().uuidString, isDirectory: true)
            defer { try? fm.removeItem(at: extract) }
            try fm.createDirectory(at: extract, withIntermediateDirectories: true)
            try safeExtractZip(zip, into: extract)
            let root = try packageRoot(in: extract)
            let mf = jsonRead(root.appendingPathComponent("oc-efi-manifest.json")) ?? [:]
            guard asString(mf["kind"]) == "oc-efi-config" else {
                throw EFIError.message("EFI 配置包格式不正确，已中止安装")
            }
            let pkgOC = root.appendingPathComponent("EFI/OC", isDirectory: true)
            let pkgRes = pkgOC.appendingPathComponent("Resources", isDirectory: true)
            guard efiIsDir(pkgRes) else {
                throw EFIError.message("EFI 配置包中缺少 EFI/OC/Resources，已中止安装")
            }
            let pkgCfg = pkgOC.appendingPathComponent("config.plist")
            guard let pkgData = try? Data(contentsOf: pkgCfg), let pkgPl = plistRead(pkgData) else {
                throw EFIError.message("EFI 配置包中缺少最小 config.plist，已中止安装")
            }
            let pkgBoot = asDict(asDict(pkgPl["Misc"])["Boot"])
            let layout = variantLayout(asString(pkgBoot["PickerVariant"]),
                                       fallback: asString(mf["variantRelative"]))
            let imageComps = layout.relative.split(separator: "/").map(String.init)
            guard !imageComps.isEmpty else {
                throw EFIError.message("EFI 配置包没有有效的 PickerVariant，已中止安装")
            }

            // 备份编号需匹配 restore() 的白名单正则，后缀用 t_ + 十六进制串；
            // 用随机十六进制避免同一秒内连续安装时备份目录重名。
            let suffix = "t_" + String(UUID().uuidString.prefix(8)).lowercased()
            let backup = try makeBackup(oc: oc, device: dev, mount: mount,
                                        theme: "EFI 配置包", suffix: suffix)
            let stage = Paths.scratch.appendingPathComponent(
                "efi_stage_" + UUID().uuidString, isDirectory: true)
            defer { try? fm.removeItem(at: stage) }
            try fm.createDirectory(at: stage, withIntermediateDirectories: true)

            var srcImage = pkgRes.appendingPathComponent("Image", isDirectory: true)
            var stageImage = stage.appendingPathComponent("Image", isDirectory: true)
            for c in imageComps {
                srcImage.appendPathComponent(c, isDirectory: true)
                stageImage.appendPathComponent(c, isDirectory: true)
            }
            if efiIsDir(srcImage) { try copyTree(srcImage, stageImage) }
            for folder in ["Font", "Label", "Sound"] {
                let s = pkgRes.appendingPathComponent(folder, isDirectory: true)
                if efiIsDir(s) {
                    try copyTree(s, stage.appendingPathComponent(folder, isDirectory: true))
                }
            }

            let mergedPl = mergePickerSettings(target: pl, packageBoot: pkgBoot,
                                               variant: layout.config)
            let merged = try PropertyListSerialization.data(fromPropertyList: mergedPl,
                                                            format: .xml, options: 0)
            try merged.write(to: stage.appendingPathComponent("config.plist"))

            var lines = [
                "test -d " + shq(oc.path),
                "mkdir -p " + [oc.appendingPathComponent("Resources/Image").path,
                               oc.appendingPathComponent("Resources/Font").path,
                               oc.appendingPathComponent("Resources/Label").path,
                               oc.appendingPathComponent("Resources/Sound").path]
                    .map(shq).joined(separator: " "),
            ]
            var imageDst = oc.appendingPathComponent("Resources/Image", isDirectory: true)
            for c in imageComps { imageDst.appendPathComponent(c, isDirectory: true) }
            lines.append("rm -rf " + shq(imageDst.path))
            lines.append("mkdir -p " + shq(imageDst.path))
            if efiIsDir(stageImage) {
                lines.append("cp -R " + shq(stageImage.path + "/.") + " " + shq(imageDst.path + "/"))
            }
            for folder in ["Font", "Label", "Sound"] {
                let s = stage.appendingPathComponent(folder, isDirectory: true)
                if !efiIsDir(s) { continue }
                let d = oc.appendingPathComponent("Resources/" + folder, isDirectory: true)
                lines.append("mkdir -p " + shq(d.path))
                lines.append("cp -R " + shq(s.path + "/.") + " " + shq(d.path + "/"))
            }
            lines.append("cp " + shq(stage.appendingPathComponent("config.plist").path)
                         + " " + shq(cfg.path))
            let done = runRoot(lines)
            if !done.ok {
                return ActionResult(ok: false, message: done.message, backupId: backup.id)
            }
            var warning = ""
            let canopyFile = efiIsFile(oc.appendingPathComponent("Drivers/OpenCanopy.efi"))
            if !canopyFile {
                warning = "\n⚠️ 目标分区 EFI/OC/Drivers 缺少 OpenCanopy.efi，图形菜单不会加载。"
            } else if !canopyEnabled(pl) {
                warning = "\n⚠️ 目标 config.plist 的 UEFI → Drivers 未启用 OpenCanopy.efi，图形菜单不会加载。"
            }
            return ActionResult(ok: true,
                                message: "已把 EFI 配置包写入 \(dev) 的 EFI/OC/Resources，"
                                    + "PickerVariant = \(layout.config)" + warning,
                                backupId: backup.id,
                                inspect: try? EFIInspect.inspect(mount: mount))
        } catch {
            return .fail(error.localizedDescription)
        }
    }

    // MARK: Apply

    static func apply(theme: Theme, device dev: String, mount: String,
                      replace: Bool, enablePicker: Bool, variant: String) -> ActionResult {
        do {
            let mp = try verify(device: dev, mount: mount)
            let oc = URL(fileURLWithPath: mp).appendingPathComponent("EFI/OC", isDirectory: true)
            guard efiIsDir(oc) else {
                throw EFIError.message("该 EFI 分区中未找到 EFI/OC 目录，请确认选择了正确的分区")
            }
            let cfg = oc.appendingPathComponent("config.plist")
            guard efiIsFile(cfg) else {
                throw EFIError.message("未找到 EFI/OC/config.plist，已中止以避免误操作")
            }
            guard let cfgData = try? Data(contentsOf: cfg), var pl = plistRead(cfgData) else {
                throw EFIError.message("config.plist 无法解析")
            }

            // 1) Local backup, no privilege needed.
            let backup = try makeBackup(oc: oc, device: dev, mount: mp,
                                        theme: theme.name, suffix: theme.id)

            // 2) Stage the theme files locally.
            try fm.createDirectory(at: Paths.scratch, withIntermediateDirectories: true)
            let stage = Paths.scratch.appendingPathComponent("stage_" + UUID().uuidString,
                                                             isDirectory: true)
            // In dry-run validation keep the staged payload so the generated
            // config.plist and directory layout can be inspected afterwards.
            defer {
                if ProcessInfo.processInfo.environment["OCTHEME_DRY_RUN"] != "1" {
                    try? fm.removeItem(at: stage)
                }
            }
            try fm.createDirectory(at: stage, withIntermediateDirectories: true)

            // Icons MUST land in the exact directory that PickerVariant points
            // at. Writing them flat into Resources/Image while config still says
            // "Acidanthera\GoldenGate" makes OpenCanopy fail to load its theme
            // and OpenCore falls back to the built-in text picker.
            let layout = variantLayout(variant, fallback: theme.pickerVariant)
            let imageComps = layout.relative.split(separator: "/").map(String.init)
            let canopyListed = canopyEnabled(pl)

            let buckets: [(String, String)] = [("Image", "image"), ("Font", "font"),
                                                ("Label", "label"), ("Sound", "sound")]
            for (folder, key) in buckets {
                var seen = Set<String>()
                let rels = theme.installList(key).filter { seen.insert($0).inserted }
                let paths = rels.compactMap { theme.url($0) }
                    .filter { $0.pathExtension.lowercased() != "json" }
                    .sorted { fileSize($0) < fileSize($1) }   // highest-resolution last wins
                var bucket = stage.appendingPathComponent(folder, isDirectory: true)
                if folder == "Image" {
                    for c in imageComps { bucket.appendPathComponent(c, isDirectory: true) }
                }
                for p in paths {
                    let out = bucket.appendingPathComponent(p.lastPathComponent)
                    if efiIsFile(out) && fileSize(out) > fileSize(p) { continue }
                    try fm.createDirectory(at: out.deletingLastPathComponent(),
                                           withIntermediateDirectories: true)
                    if efiIsFile(out) { try fm.removeItem(at: out) }
                    try fm.copyItem(at: p, to: out)
                }
            }

            // Always rewrite PickerVariant. Leaving a stale value that points at
            // a variant directory we just removed is a classic text-picker bug.
            var misc = asDict(pl["Misc"])
            var boot = asDict(misc["Boot"])
            if enablePicker { boot["PickerMode"] = "External" }
            boot["PickerVariant"] = layout.config
            misc["Boot"] = boot
            pl["Misc"] = misc
            let data = try PropertyListSerialization.data(fromPropertyList: pl,
                                                          format: .xml, options: 0)
            try data.write(to: stage.appendingPathComponent("config.plist"))

            // 3) Privileged copy. Only the target variant directory is ever
            // cleared — the other variants must survive a theme switch.
            let ocPath = oc.path
            var lines = [
                "test -d " + shq(ocPath),
                "mkdir -p " + [oc.appendingPathComponent("Resources/Image").path,
                               oc.appendingPathComponent("Resources/Font").path,
                               oc.appendingPathComponent("Resources/Label").path,
                               oc.appendingPathComponent("Resources/Sound").path]
                    .map(shq).joined(separator: " "),
            ]
            var imageDst = oc.appendingPathComponent("Resources/Image", isDirectory: true)
            for c in imageComps { imageDst.appendPathComponent(c, isDirectory: true) }
            if replace {
                lines.append("rm -rf " + shq(imageDst.path))
            }
            lines.append("mkdir -p " + shq(imageDst.path))
            for (folder, _) in buckets {
                var src = stage.appendingPathComponent(folder, isDirectory: true)
                var dst = oc.appendingPathComponent("Resources/" + folder, isDirectory: true)
                if folder == "Image" {
                    for c in imageComps {
                        src.appendPathComponent(c, isDirectory: true)
                        dst.appendPathComponent(c, isDirectory: true)
                    }
                }
                guard efiIsDir(src),
                      let children = try? fm.contentsOfDirectory(atPath: src.path),
                      !children.isEmpty else { continue }
                lines.append("mkdir -p " + shq(dst.path))
                lines.append("cp -R " + shq(src.path + "/.") + " " + shq(dst.path + "/"))
            }
            let stagedCfg = stage.appendingPathComponent("config.plist")
            if efiIsFile(stagedCfg) {
                lines.append("cp " + shq(stagedCfg.path) + " " + shq(cfg.path))
            }
            let canopyFile = efiIsFile(oc.appendingPathComponent("Drivers/OpenCanopy.efi"))
            let done = runRoot(lines)
            if !done.ok {
                return ActionResult(ok: false, message: done.message, backupId: backup.id)
            }
            var warning = ""
            if !canopyFile {
                warning = "\n⚠️ EFI/OC/Drivers 缺少 OpenCanopy.efi，图形菜单不会加载。请放入与 OpenCore 同版本的驱动。"
            } else if !canopyListed {
                warning = "\n⚠️ config.plist 的 UEFI → Drivers 未启用 OpenCanopy.efi，图形菜单不会加载。"
            }
            return ActionResult(ok: true,
                                message: "已把「\(theme.name)」写入 EFI/OC/Resources/Image/\(layout.relative)，"
                                    + "PickerVariant = \(layout.config)" + warning,
                                backupId: backup.id,
                                inspect: try? EFIInspect.inspect(mount: mp))
        } catch {
            return .fail(error.localizedDescription)
        }
    }

    // MARK: Restore (exact)

    static func restore(backupId: String, device dev: String, mount: String) -> ActionResult {
        do {
            guard backupId.range(of: "^[0-9]{8}-[0-9]{6}-t_[0-9a-fA-F]+$",
                                 options: .regularExpression) != nil else {
                throw EFIError.message("无效的备份编号")
            }
            let bdir = Paths.backups.appendingPathComponent(backupId, isDirectory: true)
            guard efiIsDir(bdir) else { throw EFIError.message("备份不存在") }
            let mp = try verify(device: dev, mount: mount)
            let oc = URL(fileURLWithPath: mp).appendingPathComponent("EFI/OC", isDirectory: true)
            guard efiIsDir(oc) else {
                throw EFIError.message("该分区中未找到 EFI/OC 目录，已中止恢复")
            }

            // Snapshot the current state first, so the restore itself is reversible.
            let pre = try makeBackup(oc: oc, device: dev, mount: mp,
                                     theme: "恢复前自动快照（用于回退 \(backupId)）",
                                     suffix: "t_" + String(UUID().uuidString.prefix(8)).lowercased())

            // Exact restore: remove Resources entirely, then copy the backup back.
            var lines = ["test -d " + shq(oc.path),
                         "rm -rf " + shq(oc.appendingPathComponent("Resources").path)]
            let bres = bdir.appendingPathComponent("Resources", isDirectory: true)
            if efiIsDir(bres) {
                lines.append("cp -R " + shq(bres.path) + " " + shq(oc.appendingPathComponent("Resources").path))
            }
            let bcfg = bdir.appendingPathComponent("config.plist")
            if efiIsFile(bcfg) {
                lines.append("cp " + shq(bcfg.path) + " " + shq(oc.appendingPathComponent("config.plist").path))
            }
            let done = runRoot(lines)
            if !done.ok {
                return ActionResult(ok: false, message: done.message,
                                    preRestoreBackup: pre.id)
            }
            return ActionResult(ok: true,
                                message: "已精确还原应用前的 Resources 与 config.plist",
                                preRestoreBackup: pre.id,
                                inspect: try? EFIInspect.inspect(mount: mp))
        } catch {
            return .fail(error.localizedDescription)
        }
    }
}
