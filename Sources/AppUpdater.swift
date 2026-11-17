import Foundation
import AppKit
import CommonCrypto

// MARK: - 应用内更新（双通道：GitHub Release / 自有服务器 oc.mctop.top）
//
// 通道语义：
//   .github —— 请求 GitHub API 的 latest release，下载其 .dmg 附件；
//   .server —— 请求 https://oc.mctop.top/api/app/update，下载自有服务器发布包，
//              并按服务端下发的 sha256 校验完整性。
// 两通道在「应用菜单 → 更新通道」二选一，选择写入 state.json。
// 检查时机：启动后静默检查一次（有更新才弹窗）+ 菜单手动检查。

enum UpdateChannel: String {
    case github = "github"
    case server = "server"

    var label: String {
        switch self {
        case .github: return "GitHub Release"
        case .server: return "自有服务器 (oc.mctop.top)"
        }
    }
}

struct UpdateInfo {
    let version: String
    let notes: String
    let downloadURL: URL
    let sha256: String?
    let size: Int64
    let channel: UpdateChannel
}

final class AppUpdater: NSObject, URLSessionDownloadDelegate {

    static let shared = AppUpdater()

    static let githubRepo = "huangjinkun2006/oc-theme-studio"

    /// 自有服务器通道基址；state.json 的 updateServer 可覆盖（排障/测试用）。
    static var serverBase: String {
        let override = (jsonRead(Paths.state)?["updateServer"] as? String)?
            .trimmingCharacters(in: .whitespaces) ?? ""
        if !override.isEmpty, let u = URL(string: override), u.scheme == "http" || u.scheme == "https" {
            return override.hasSuffix("/") ? String(override.dropLast()) : override
        }
        return "https://oc.mctop.top"
    }

    static var currentVersion: String {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "0.0.0"
    }

    static var channel: UpdateChannel {
        get {
            let s = (jsonRead(Paths.state)?["updateChannel"] as? String) ?? ""
            return UpdateChannel(rawValue: s) ?? .server
        }
        set {
            var obj = jsonRead(Paths.state) ?? [:]
            obj["updateChannel"] = newValue.rawValue
            try? jsonWrite(obj, to: Paths.state)
        }
    }

    /// 语义化版本比较：remote 是否比 current 新。
    static func isNewer(_ remote: String, than current: String) -> Bool {
        let a = remote.split(separator: ".").compactMap { Int($0) }
        let b = current.split(separator: ".").compactMap { Int($0) }
        guard !a.isEmpty else { return false }
        for i in 0..<max(a.count, b.count) {
            let x = i < a.count ? a[i] : 0
            let y = i < b.count ? b[i] : 0
            if x != y { return x > y }
        }
        return false
    }

    // MARK: 检查更新

    private var checking = false

    func check(manual: Bool) {
        guard !checking else { return }
        checking = true
        switch Self.channel {
        case .github: checkGitHub(manual: manual)
        case .server: checkServer(manual: manual)
        }
    }

    private func finish(_ info: UpdateInfo?, manual: Bool, error: String?) {
        checking = false
        DispatchQueue.main.async {
            if let info = info {
                self.offerUpdate(info)
            } else if manual {
                let a = NSAlert()
                a.messageText = "检查更新"
                a.informativeText = error ?? "当前已是最新版本（\(Self.currentVersion)）。"
                a.alertStyle = error == nil ? .informational : .warning
                a.runModal()
            }
        }
    }

    private func checkServer(manual: Bool) {
        guard let url = URL(string: Self.serverBase + "/api/app/update") else {
            finish(nil, manual: manual, error: "更新地址无效"); return
        }
        var req = URLRequest(url: url)
        req.timeoutInterval = 15
        URLSession.shared.dataTask(with: req) { data, resp, err in
            if let err = err {
                self.finish(nil, manual: manual, error: "无法连接更新服务器：\(err.localizedDescription)"); return
            }
            guard let http = resp as? HTTPURLResponse, http.statusCode == 200,
                  let obj = try? JSONSerialization.jsonObject(with: data ?? Data()) as? [String: Any],
                  (obj["hasUpdate"] as? Bool) == true,
                  let ver = obj["version"] as? String,
                  Self.isNewer(ver, than: Self.currentVersion),
                  let rel = obj["url"] as? String,
                  let dl = URL(string: Self.serverBase + rel) else {
                self.finish(nil, manual: manual, error: nil); return
            }
            let info = UpdateInfo(
                version: ver,
                notes: (obj["notes"] as? String) ?? "",
                downloadURL: dl,
                sha256: obj["sha256"] as? String,
                size: Int64(truncating: obj["size"] as? NSNumber ?? 0),
                channel: .server)
            self.finish(info, manual: manual, error: nil)
        }.resume()
    }

    private func checkGitHub(manual: Bool) {
        let api = "https://api.github.com/repos/\(Self.githubRepo)/releases/latest"
        var req = URLRequest(url: URL(string: api)!)
        req.timeoutInterval = 15
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.setValue("OCThemeStudio/\(Self.currentVersion)", forHTTPHeaderField: "User-Agent")
        URLSession.shared.dataTask(with: req) { data, resp, err in
            if let err = err {
                self.finish(nil, manual: manual, error: "无法连接 GitHub：\(err.localizedDescription)"); return
            }
            guard let http = resp as? HTTPURLResponse, http.statusCode == 200,
                  let obj = try? JSONSerialization.jsonObject(with: data ?? Data()) as? [String: Any],
                  let tag = obj["tag_name"] as? String else {
                let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
                self.finish(nil, manual: manual,
                            error: code == 404 ? "GitHub 上还没有发布版本。" :
                            code == 403 ? "GitHub API 限流，请稍后再试或切换自有服务器通道。" :
                            "GitHub 响应异常（\(code)）。")
                return
            }
            let ver = tag.hasPrefix("v") || tag.hasPrefix("V") ? String(tag.dropFirst()) : tag
            guard Self.isNewer(ver, than: Self.currentVersion),
                  let assets = obj["assets"] as? [[String: Any]],
                  let asset = assets.first(where: { ($0["name"] as? String ?? "").hasSuffix(".dmg") }),
                  let dlStr = asset["browser_download_url"] as? String,
                  let dl = URL(string: dlStr) else {
                self.finish(nil, manual: manual, error: nil); return
            }
            let info = UpdateInfo(
                version: ver,
                notes: (obj["body"] as? String) ?? "",
                downloadURL: dl,
                sha256: nil,
                size: Int64(truncating: asset["size"] as? NSNumber ?? 0),
                channel: .github)
            self.finish(info, manual: manual, error: nil)
        }.resume()
    }

    // MARK: 询问与下载

    private func offerUpdate(_ info: UpdateInfo) {
        let a = NSAlert()
        a.messageText = "发现新版本 \(info.version)（当前 \(Self.currentVersion)）"
        var text = "更新通道：\(info.channel.label)\n"
        if !info.notes.isEmpty { text += "\n更新说明：\n\(info.notes)\n" }
        if info.size > 0 {
            text += "\n大小：\(String(format: "%.1f", Double(info.size) / 1048576.0)) MB"
        }
        a.informativeText = text
        a.alertStyle = .informational
        a.addButton(withTitle: "下载并安装")
        a.addButton(withTitle: "稍后")
        if a.runModal() == .alertFirstButtonReturn {
            self.download(info)
        }
    }

    private var progressWindow: NSWindow?
    private var progressBar: NSProgressIndicator?
    private var progressLabel: NSTextField?
    private var activeInfo: UpdateInfo?
    private var cancelled = false

    private func download(_ info: UpdateInfo) {
        cancelled = false
        activeInfo = info
        showProgress()
        let session = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
        session.downloadTask(with: info.downloadURL).resume()
    }

    private func showProgress() {
        DispatchQueue.main.async {
            let rect = NSRect(x: 0, y: 0, width: 420, height: 110)
            let win = NSWindow(contentRect: rect, styleMask: [.titled, .closable],
                               backing: .buffered, defer: false)
            win.title = "下载更新"
            win.isReleasedWhenClosed = false
            let bar = NSProgressIndicator(frame: NSRect(x: 20, y: 52, width: 380, height: 20))
            bar.isIndeterminate = false
            bar.minValue = 0; bar.maxValue = 1
            let label = NSTextField(labelWithString: "正在下载更新包…")
            label.frame = NSRect(x: 20, y: 80, width: 380, height: 20)
            let cancel = NSButton(title: "取消", target: self, action: #selector(self.cancelDownload(_:)))
            cancel.frame = NSRect(x: 320, y: 14, width: 80, height: 28)
            win.contentView?.addSubview(bar)
            win.contentView?.addSubview(label)
            win.contentView?.addSubview(cancel)
            win.center()
            win.makeKeyAndOrderFront(nil)
            self.progressWindow = win
            self.progressBar = bar
            self.progressLabel = label
        }
    }

    @objc private func cancelDownload(_ sender: Any?) {
        cancelled = true
        closeProgress()
    }

    private func closeProgress() {
        DispatchQueue.main.async {
            self.progressWindow?.orderOut(nil)
            self.progressWindow = nil
        }
    }

    private func failDownload(_ msg: String) {
        closeProgress()
        DispatchQueue.main.async {
            let a = NSAlert()
            a.messageText = "下载失败"
            a.informativeText = msg
            a.alertStyle = .warning
            a.runModal()
        }
    }

    // MARK: URLSessionDownloadDelegate

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64, totalBytesWritten: Int64,
                    totalBytesExpectedToWrite: Int64) {
        DispatchQueue.main.async {
            guard let bar = self.progressBar, !bar.isIndeterminate else { return }
            if totalBytesExpectedToWrite > 0 {
                bar.doubleValue = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
                self.progressLabel?.stringValue = String(
                    format: "正在下载… %.1f / %.1f MB",
                    Double(totalBytesWritten) / 1048576.0,
                    Double(totalBytesExpectedToWrite) / 1048576.0)
            }
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask,
                    didCompleteWithError error: Error?) {
        if let error = error, !cancelled {
            failDownload(error.localizedDescription)
        }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didFinishDownloadingTo location: URL) {
        guard !cancelled, let info = activeInfo else { return }
        let dest = FileManager.default.temporaryDirectory
            .appendingPathComponent("OCThemeStudio-update-\(info.version).dmg")
        do {
            try? FileManager.default.removeItem(at: dest)
            try FileManager.default.moveItem(at: location, to: dest)
        } catch {
            failDownload("保存下载文件失败：\(error.localizedDescription)"); return
        }
        // 自有服务器通道校验 sha256
        if let expect = info.sha256, !expect.isEmpty {
            progressLabelDispatch("正在校验完整性…")
            DispatchQueue.global(qos: .userInitiated).async {
                let digest = Self.sha256(of: dest)
                DispatchQueue.main.async {
                    if digest?.lowercased() != expect.lowercased() {
                        try? FileManager.default.removeItem(at: dest)
                        self.failDownload("校验失败：下载包与服务器记录不一致（sha256 不匹配），已丢弃。")
                    } else {
                        self.closeProgress()
                        self.confirmInstall(dmg: dest, info: info)
                    }
                }
            }
        } else {
            closeProgress()
            confirmInstall(dmg: dest, info: info)
        }
    }

    private func progressLabelDispatch(_ s: String) {
        DispatchQueue.main.async { self.progressLabel?.stringValue = s }
    }

    static func sha256(of url: URL) -> String? {
        guard let handle = FileHandle(forReadingAtPath: url.path) else { return nil }
        defer { try? handle.close() }
        var ctx = CC_SHA256_CTX()
        CC_SHA256_Init(&ctx)
        while autoreleasepool(invoking: {
            let chunk = handle.readData(ofLength: 1024 * 1024)
            guard !chunk.isEmpty else { return false }
            chunk.withUnsafeBytes { _ = CC_SHA256_Update(&ctx, $0.baseAddress, CC_LONG(chunk.count)) }
            return true
        }) {}
        var out = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        CC_SHA256_Final(&out, &ctx)
        return out.map { String(format: "%02x", $0) }.joined()
    }

    // MARK: 安装

    private func confirmInstall(dmg: URL, info: UpdateInfo) {
        let a = NSAlert()
        a.messageText = "下载完成，是否立即安装 \(info.version)？"
        a.informativeText = "安装会替换当前应用（\(Bundle.main.bundleURL.lastPathComponent)），并自动重启。旧版本会保留一份备份以便回退。"
        a.alertStyle = .informational
        a.addButton(withTitle: "安装并重启")
        a.addButton(withTitle: "取消")
        guard a.runModal() == .alertFirstButtonReturn else {
            try? FileManager.default.removeItem(at: dmg)
            return
        }
        do {
            try Self.install(dmg: dmg)
        } catch {
            let e = NSAlert()
            e.messageText = "安装失败"
            e.informativeText = error.localizedDescription
            e.alertStyle = .critical
            e.runModal()
        }
    }

    /// 挂载 DMG → 找到 .app → 替换当前 bundle → 重启。
    static func install(dmg: URL) throws {
        let fm = FileManager.default
        let before = Set((try? fm.contentsOfDirectory(atPath: "/Volumes")) ?? [])

        let attach = Process()
        attach.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
        attach.arguments = ["attach", "-nobrowse", "-readonly", dmg.path]
        let pipe = Pipe()
        attach.standardOutput = pipe
        attach.standardError = pipe
        try attach.run()
        attach.waitUntilExit()
        guard attach.terminationStatus == 0 else {
            let out = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            throw NSError(domain: "Updater", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "挂载 DMG 失败：\(out.prefix(200))"])
        }

        let after = Set((try? fm.contentsOfDirectory(atPath: "/Volumes")) ?? [])
        let mounted = after.subtracting(before)
        guard let volName = mounted.first else {
            throw NSError(domain: "Updater", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: "找不到挂载的卷"])
        }
        let vol = URL(fileURLWithPath: "/Volumes").appendingPathComponent(volName)
        defer {
            let det = Process()
            det.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
            det.arguments = ["detach", vol.path, "-force"]
            try? det.run()
            det.waitUntilExit()
            try? fm.removeItem(at: dmg)
        }

        guard let appURL = try? fm.contentsOfDirectory(at: vol, includingPropertiesForKeys: nil)
            .first(where: { $0.pathExtension == "app" }) else {
            throw NSError(domain: "Updater", code: 3,
                          userInfo: [NSLocalizedDescriptionKey: "DMG 内没有找到 .app"])
        }

        let dest = Bundle.main.bundleURL
        let parent = dest.deletingLastPathComponent()
        let backup = parent.appendingPathComponent(dest.lastPathComponent + ".updating-old")
        try? fm.removeItem(at: backup)
        try fm.moveItem(at: dest, to: backup)
        do {
            try fm.copyItem(at: appURL, to: dest)
        } catch {
            // 回滚
            try? fm.moveItem(at: backup, to: dest)
            throw error
        }

        // 下次启动清理备份；这里先派一个延时清理
        let cleaner = Process()
        cleaner.executableURL = URL(fileURLWithPath: "/bin/bash")
        cleaner.arguments = ["-c", "sleep 5; rm -rf '\(backup.path)'"]
        try? cleaner.run()

        let open = Process()
        open.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        open.arguments = ["-n", dest.path]
        try open.run()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            NSApp.terminate(nil)
        }
    }

    /// 启动时清理上次更新留下的备份目录。
    static func cleanupStaleBackup() {
        let dest = Bundle.main.bundleURL
        let backup = dest.deletingLastPathComponent()
            .appendingPathComponent(dest.lastPathComponent + ".updating-old")
        try? FileManager.default.removeItem(at: backup)
    }
}
