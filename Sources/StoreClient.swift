import Foundation
import AppKit

// MARK: - Theme store model & client
//
// The store talks to a self-hosted HTTP backend (see store_server.py). When no
// server is configured, or the server is unreachable, it falls back to a bundled
// offline catalog of demo themes so the UI is never empty. Everything is
// dependency-free (URLSession).

/// 商店分类：完整主题为默认类型；图标区 / 背景区 / 字体区用于分享单类资源，
/// EFI 配置包由已挂载分区生成（脱敏）并按目标分区安装。
/// slug 与后端 `store_server.py` 的 CATEGORIES 保持一致。
enum StoreCategory: String {
    case all = "all"
    case theme = "theme"
    case icons = "icons"
    case background = "background"
    case fonts = "fonts"
    case efi = "efi"

    var label: String {
        switch self {
        case .all: return "全部"
        case .theme: return "完整主题"
        case .icons: return "图标区"
        case .background: return "背景区"
        case .fonts: return "字体区"
        case .efi: return "EFI 配置包"
        }
    }

    static let selectable: [StoreCategory] = [.all, .theme, .icons, .background, .fonts, .efi]
    static let uploadable: [StoreCategory] = [.theme, .icons, .background, .fonts, .efi]
}

struct StoreTheme: Codable, Identifiable {
    let id: String
    let name: String
    let author: String
    let description: String
    let version: String?
    let tags: [String]
    let category: String?       // "theme" / "icons" / "background" / "fonts"
    let categoryLabel: String?  // 服务端下发的中文显示名
    let thumbnail: String?     // "preset://<id>" or "/files/<id>/preview/0.png"
    let download: String?      // "preset://<id>" or "/api/themes/<id>/download"
    let sizeText: String?
    let updated: String?
    let downloads: Int?
    let commentCount: Int?       // 评论数（详情页统计条）
    let previews: [String]?      // 详情页多预览图 URL（封面排最前）
    let cover: String?           // 自定义封面文件名（服务端 meta.cover）

    /// 多预览图 URL（远程 /files/... 拼基址；preset:// 用内置背景）。
    var previewPaths: [String] {
        if let ps = previews, !ps.isEmpty { return ps }
        if let t = thumbnail, !t.isEmpty { return [t] }
        return []
    }

    var categoryKind: StoreCategory {
        StoreCategory(rawValue: category ?? StoreCategory.theme.rawValue) ?? .theme
    }
    var categoryDisplay: String { categoryLabel ?? categoryKind.label }
    var localDemo: Bool { (thumbnail ?? "").hasPrefix("preset://") }
    var presetId: String? {
        guard localDemo, let t = thumbnail else { return nil }
        return String(t.dropFirst("preset://".count))
    }
}

enum StoreDownloadResult {
    case local(presetId: String)
    case remote(zipURL: URL)
}

enum StoreError: LocalizedError {
    case message(String)
    var errorDescription: String? {
        switch self { case .message(let s): return s }
    }
}

final class StoreClient {

    // MARK: Configuration

    /// 内置默认主题商店地址（HTTPS 域名，Let's Encrypt 证书）。
    /// 用户也可在商店窗口顶部「服务器地址」栏覆盖（写入 state.json）。
    static let defaultBaseURL = "https://mctop.top"

    /// 旧版内置的明文 IP 地址。用户配置里仍存着它时自动升级到 HTTPS 域名，
    /// 避免老用户升级后被 ATS 拦截或直接连不上。
    private static let legacyBaseURL = "http://120.53.88.48"

    static var baseURL: URL? {
        let s = (jsonRead(Paths.state)?["storeURL"] as? String)?.trimmingCharacters(in: .whitespaces) ?? ""
        var effective = s.isEmpty ? Self.defaultBaseURL : s
        if effective == Self.legacyBaseURL || effective == Self.legacyBaseURL + "/" {
            effective = Self.defaultBaseURL
        }
        guard let u = URL(string: effective), u.scheme == "http" || u.scheme == "https" else {
            return nil
        }
        return u
    }

    static func saveBaseURL(_ s: String) {
        var obj = jsonRead(Paths.state) ?? [:]
        let v = s.trimmingCharacters(in: .whitespaces)
        if v.isEmpty { obj.removeValue(forKey: "storeURL") } else { obj["storeURL"] = v }
        try? jsonWrite(obj, to: Paths.state)
    }

    // MARK: Offline catalog

    static func loadOffline() -> [StoreTheme] {
        guard let url = Bundle.main.url(forResource: "catalog", withExtension: "json",
                                        subdirectory: "Store"),
              let data = try? Data(contentsOf: url),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let arr = obj["themes"] as? [[String: Any]] else { return [] }
        return arr.compactMap { decode($0) }
    }

    /// 离线示例也按分类过滤：内置示例都是完整主题，单类资源区为空。
    static func loadOffline(category: StoreCategory) -> [StoreTheme] {
        let all = loadOffline()
        guard category != .all else { return all }
        return all.filter { $0.categoryKind == category }
    }

    /// 读取服务端各分类数量，用于商店窗口的分类下拉标题。
    static func categories(completion: @escaping ([StoreCategory: Int]) -> Void) {
        guard let base = baseURL else {
            completion([:])
            return
        }
        var req = URLRequest(url: base.appendingPathComponent("api/categories"))
        req.timeoutInterval = 10
        URLSession.shared.dataTask(with: req) { data, _, _ in
            var counts: [StoreCategory: Int] = [:]
            var total = 0
            if let data = data,
               let arr = (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]] {
                for d in arr {
                    guard let raw = d["id"] as? String,
                          let c = StoreCategory(rawValue: raw) else { continue }
                    let n = d["count"] as? Int ?? 0
                    counts[c] = n
                    total += n
                }
                counts[.all] = total
            }
            completion(counts)
        }.resume()
    }

    private static func decode(_ d: [String: Any]) -> StoreTheme? {
        guard let id = d["id"] as? String,
              let name = d["name"] as? String,
              let author = d["author"] as? String,
              let desc = d["description"] as? String else { return nil }
        return StoreTheme(
            id: id, name: name, author: author, description: desc,
            version: d["version"] as? String,
            tags: d["tags"] as? [String] ?? [],
            category: d["category"] as? String,
            categoryLabel: d["categoryLabel"] as? String,
            thumbnail: d["thumbnail"] as? String,
            download: d["download"] as? String,
            sizeText: d["sizeText"] as? String,
            updated: d["updated"] as? String,
            downloads: d["downloads"] as? Int,
            commentCount: d["commentCount"] as? Int,
            previews: d["previews"] as? [String],
            cover: d["cover"] as? String)
    }

    // MARK: Thumbnails

    static func thumbnailURL(for theme: StoreTheme) -> URL? {
        if let pid = theme.presetId,
           let p = ThemePreset.all().first(where: { $0.id == pid }),
           let root = ThemePreset.root, !p.background.isEmpty {
            let u = root.appendingPathComponent("icons", isDirectory: true)
                .appendingPathComponent(p.background)
            if FileManager.default.fileExists(atPath: u.path) { return u }
        }
        return imageURL(for: theme.thumbnail)
    }

    /// 任意商店图片路径 -> 可加载 URL（preset:// / 绝对 URL / 相对 /files/...）。
    static func imageURL(for path: String?) -> URL? {
        guard let t = path, !t.isEmpty else { return nil }
        if t.hasPrefix("http://") || t.hasPrefix("https://") {
            return URL(string: t)
        }
        if t.hasPrefix("preset://") {
            let pid = String(t.dropFirst("preset://".count))
            if let p = ThemePreset.all().first(where: { $0.id == pid }),
               let root = ThemePreset.root, !p.background.isEmpty {
                let u = root.appendingPathComponent("icons", isDirectory: true)
                    .appendingPathComponent(p.background)
                if FileManager.default.fileExists(atPath: u.path) { return u }
            }
            return nil
        }
        guard let base = baseURL, t.hasPrefix("/") else { return nil }
        return base.appendingPathComponent(t)
    }

    // MARK: List

    static func list(category: StoreCategory = .all,
                     completion: @escaping (Result<[StoreTheme], Error>) -> Void) {
        guard let base = baseURL else {
            completion(.success(loadOffline(category: category)))
            return
        }
        var url = base.appendingPathComponent("api/themes")
        if category != .all {
            var comps = URLComponents(url: url, resolvingAgainstBaseURL: false)
            comps?.queryItems = [URLQueryItem(name: "category", value: category.rawValue)]
            url = comps?.url ?? url
        }
        var req = URLRequest(url: url)
        req.timeoutInterval = 20
        URLSession.shared.dataTask(with: req) { data, _, _ in
            guard let data = data,
                  let arr = (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]] else {
                // Network failure → fall back to offline demo catalog.
                completion(.success(loadOffline(category: category)))
                return
            }
            completion(.success(arr.compactMap { decode($0) }))
        }.resume()
    }

    // MARK: Download

    static func download(_ theme: StoreTheme,
                         completion: @escaping (Result<StoreDownloadResult, Error>) -> Void) {
        if let pid = theme.presetId {
            completion(.success(.local(presetId: pid)))
            return
        }
        guard let base = baseURL, let d = theme.download,
              let url = URL(string: d, relativeTo: base) else {
            completion(.failure(StoreError.message("该主题没有可用的下载地址（离线示例请使用 preset 主题）。")))
            return
        }
        let task = URLSession.shared.downloadTask(with: url) { fileURL, resp, err in
            if let err = err {
                completion(.failure(StoreError.message("下载失败：\(err.localizedDescription)")))
                return
            }
            guard let fileURL = fileURL else {
                completion(.failure(StoreError.message("下载失败：未返回文件")))
                return
            }
            let dest = Paths.scratch.appendingPathComponent("store_\(theme.id).zip")
            try? FileManager.default.createDirectory(at: Paths.scratch,
                                                    withIntermediateDirectories: true)
            try? FileManager.default.removeItem(at: dest)
            do {
                try FileManager.default.moveItem(at: fileURL, to: dest)
                completion(.success(.remote(zipURL: dest)))
            } catch {
                completion(.failure(error))
            }
        }
        task.resume()
    }

    // MARK: Upload

    struct UploadSpec {
        var name: String
        var author: String
        var description: String
        var version: String
        var tags: [String]
        var category: String = StoreCategory.theme.rawValue  // 上传时选择的资源类型
        var package: URL?        // a .zip theme package
        var previews: [URL]      // preview images
    }

    static func upload(_ spec: UploadSpec,
                       completion: @escaping (Result<StoreTheme, Error>) -> Void) {
        guard let base = baseURL else {
            completion(.failure(StoreError.message("未配置主题商店服务器地址，无法上传。")))
            return
        }
        let url = base.appendingPathComponent("api/themes")
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 120

        let boundary = "OCThemeStudioFormBoundary\(UUID().uuidString)"
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()
        func append(_ name: String, _ value: String) {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".data(using: .utf8)!)
            body.append("\(value)\r\n".data(using: .utf8)!)
        }
        append("name", spec.name)
        append("author", spec.author)
        append("description", spec.description)
        append("version", spec.version)
        append("tags", spec.tags.joined(separator: ","))
        append("category", spec.category)

        if let pkg = spec.package {
            if let data = try? Data(contentsOf: pkg) {
                body.append("--\(boundary)\r\n".data(using: .utf8)!)
                body.append("Content-Disposition: form-data; name=\"package\"; filename=\"\(pkg.lastPathComponent)\"\r\n".data(using: .utf8)!)
                body.append("Content-Type: application/zip\r\n\r\n".data(using: .utf8)!)
                body.append(data)
                body.append("\r\n".data(using: .utf8)!)
            }
        }
        for (i, p) in spec.previews.enumerated() {
            if let data = try? Data(contentsOf: p) {
                let mime = (p.pathExtension.lowercased() == "png") ? "image/png" : "image/jpeg"
                body.append("--\(boundary)\r\n".data(using: .utf8)!)
                body.append("Content-Disposition: form-data; name=\"previews\"; filename=\"preview\(i).\(p.pathExtension)\"\r\n".data(using: .utf8)!)
                body.append("Content-Type: \(mime)\r\n\r\n".data(using: .utf8)!)
                body.append(data)
                body.append("\r\n".data(using: .utf8)!)
            }
        }
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        req.httpBody = body

        URLSession.shared.dataTask(with: req) { data, _, _ in
            guard let data = data,
                  let d = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
                  let t = decode(d) else {
                let raw = data.flatMap { String(data: $0, encoding: .utf8) } ?? "未知错误"
                completion(.failure(StoreError.message("上传失败：" + raw)))
                return
            }
            completion(.success(t))
        }.resume()
    }
}
