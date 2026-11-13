import Foundation
import AppKit
import Darwin

// MARK: - Locations

enum Paths {
    /// Deliberately the same directory as the previous Python build, so the
    /// user's imported themes and EFI backups carry over to the native app.
    static let support: URL = {
        if let env = ProcessInfo.processInfo.environment["OCTHEME_DATA"], !env.isEmpty {
            return URL(fileURLWithPath: (env as NSString).expandingTildeInPath,
                       isDirectory: true)
        }
        let base = FileManager.default.urls(for: .applicationSupportDirectory,
                                           in: .userDomainMask)[0]
        return base.appendingPathComponent("OCThemeStudio", isDirectory: true)
    }()
    static let themes = support.appendingPathComponent("themes", isDirectory: true)
    static let backups = support.appendingPathComponent("backups", isDirectory: true)
    static let state = support.appendingPathComponent("state.json")
    static let scratch = support.appendingPathComponent(".scratch", isDirectory: true)
    static let bundledThemes = Bundle.main.resourceURL?
        .appendingPathComponent("themes", isDirectory: true)

    static func ensure() {
        let fm = FileManager.default
        try? fm.createDirectory(at: themes, withIntermediateDirectories: true)
        try? fm.createDirectory(at: backups, withIntermediateDirectories: true)
        try? fm.createDirectory(at: scratch, withIntermediateDirectories: true)
        try? fm.createDirectory(at: support, withIntermediateDirectories: true)
        seedThemes()
    }

    static func seedThemes() {
        let fm = FileManager.default
        guard let src = bundledThemes, fm.fileExists(atPath: src.path) else { return }
        let existing = (try? fm.contentsOfDirectory(atPath: themes.path)) ?? []
        let manifests = existing.filter {
            fm.fileExists(atPath: themes.appendingPathComponent($0)
                .appendingPathComponent("manifest.json").path)
        }
        if !manifests.isEmpty { return }
        let items = (try? fm.contentsOfDirectory(atPath: src.path)) ?? []
        for item in items where item.hasPrefix("t_") {
            let from = src.appendingPathComponent(item)
            let to = themes.appendingPathComponent(item)
            if !fm.fileExists(atPath: to.path) {
                try? fm.copyItem(at: from, to: to)
            }
        }
    }
}

// MARK: - Process helpers

struct CmdResult {
    let code: Int32
    let out: String
    let err: String
    var ok: Bool { code == 0 }
}

func appLog(_ items: Any...) {
    let text = items.map { "\($0)" }.joined(separator: " ")
    NSLog("[OCThemeSwift] %@", text)
}

/// Run a command and collect both streams without deadlocking on a full pipe.
@discardableResult
func shellRun(_ path: String, _ args: [String], timeout: TimeInterval = 60) -> CmdResult {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: path)
    process.arguments = args
    let outPipe = Pipe()
    let errPipe = Pipe()
    process.standardOutput = outPipe
    process.standardError = errPipe
    do {
        try process.run()
    } catch {
        return CmdResult(code: -1, out: "", err: "\(error)")
    }

    let outData = NSMutableData()
    let errData = NSMutableData()
    let lock = NSLock()
    let group = DispatchGroup()
    group.enter()
    DispatchQueue.global().async {
        let d = outPipe.fileHandleForReading.readDataToEndOfFile()
        lock.lock(); outData.append(d); lock.unlock()
        group.leave()
    }
    group.enter()
    DispatchQueue.global().async {
        let d = errPipe.fileHandleForReading.readDataToEndOfFile()
        lock.lock(); errData.append(d); lock.unlock()
        group.leave()
    }

    let deadline = Date().addingTimeInterval(timeout)
    while process.isRunning && Date() < deadline {
        Thread.sleep(forTimeInterval: 0.05)
    }
    if process.isRunning { process.terminate() }
    process.waitUntilExit()
    group.wait()
    return CmdResult(code: process.terminationStatus,
                     out: String(data: outData as Data, encoding: .utf8) ?? "",
                     err: String(data: errData as Data, encoding: .utf8) ?? "")
}

func shq(_ s: String) -> String {
    "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
}

/// Execute a shell script as root. When not root, macOS shows the standard
/// administrator password dialog via AppleScript, exactly like_diskutil GUI tools.
func runRoot(_ lines: [String]) -> (ok: Bool, message: String) {
    let script = "#!/bin/bash\nset -e\n" + lines.joined(separator: "\n") + "\necho OCTHEME_OK\n"
    // Validation hook: generate and print the privileged script without ever
    // executing it. Used by the build's end-to-end dry-run tests.
    if ProcessInfo.processInfo.environment["OCTHEME_DRY_RUN"] == "1" {
        print("----- DRY RUN SCRIPT -----\n" + script + "--------------------------")
        return (true, "dry-run")
    }
    var result: CmdResult
    if geteuid() == 0 {
        result = shellRun("/bin/bash", ["-c", script], timeout: 300)
    } else {
        try? FileManager.default.createDirectory(at: Paths.scratch, withIntermediateDirectories: true)
        let tmp = Paths.scratch.appendingPathComponent("octheme_\(UUID().uuidString).sh")
        do {
            try script.write(to: tmp, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o700],
                                                  ofItemAtPath: tmp.path)
        } catch {
            return (false, "无法创建临时脚本：\(error.localizedDescription)")
        }
        defer { try? FileManager.default.removeItem(at: tmp) }
        let cmd = "/bin/bash " + shq(tmp.path)
        let escaped = cmd.replacingOccurrences(of: "\\", with: "\\\\")
                         .replacingOccurrences(of: "\"", with: "\\\"")
        let osa = "do shell script \"\(escaped)\" with administrator privileges"
        result = shellRun("/usr/bin/osascript", ["-e", osa], timeout: 300)
    }
    if result.ok && result.out.contains("OCTHEME_OK") {
        return (true, result.out.replacingOccurrences(of: "OCTHEME_OK", with: "")
                        .trimmingCharacters(in: .whitespacesAndNewlines))
    }
    var msg = (result.err.isEmpty ? result.out : result.err)
        .trimmingCharacters(in: .whitespacesAndNewlines)
    if msg.contains("User canceled") || msg.contains("-128") { msg = "已取消管理员授权" }
    return (false, msg.isEmpty ? "命令执行失败" : msg)
}

// MARK: - JSON / formatting

func jsonRead(_ url: URL) -> [String: Any]? {
    guard let d = try? Data(contentsOf: url) else { return nil }
    return (try? JSONSerialization.jsonObject(with: d)) as? [String: Any]
}

func jsonWrite(_ obj: [String: Any], to url: URL) throws {
    let d = try JSONSerialization.data(withJSONObject: obj,
                                       options: [.prettyPrinted, .withoutEscapingSlashes])
    try d.write(to: url, options: .atomic)
}

func plistRead(_ data: Data) -> [String: Any]? {
    try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
}

func humanSize(_ bytes: Int64) -> String {
    var n = Double(bytes)
    for unit in ["B", "KB", "MB", "GB"] {
        if n < 1024 || unit == "GB" {
            return unit == "B" ? "\(Int(n)) B" : String(format: "%.1f %@", n, unit)
        }
        n /= 1024
    }
    return "\(bytes) B"
}

func fileSize(_ url: URL) -> Int64 {
    (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?
        .int64Value ?? 0
}

func slugId(_ name: String) -> String {
    let salt = "\(name)\(Date().timeIntervalSinceReferenceDate)\(UUID().uuidString)"
    // Stable 8-hex id from a simple FNV-1a hash (no CryptoKit dependency).
    var hash: UInt64 = 14695981039346656037
    for b in salt.utf8 {
        hash ^= UInt64(b)
        hash = hash &* 1099511628211
    }
    return "t_" + String(format: "%08x", hash & 0xffffffff)
}

func stamp(_ format: String) -> String {
    let f = DateFormatter()
    f.dateFormat = format
    f.locale = Locale(identifier: "en_US_POSIX")
    return f.string(from: Date())
}

func sizeOfDirectory(_ url: URL) -> Int64 {
    let fm = FileManager.default
    guard let e = fm.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey]) else { return 0 }
    var total: Int64 = 0
    for case let u as URL in e {
        total += fileSize(u)
    }
    return total
}

// MARK: - Errors

enum AppError: LocalizedError {
    case message(String)
    var errorDescription: String? {
        switch self { case .message(let s): return s }
    }
}
