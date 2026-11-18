import AppKit
import CoreGraphics
import Foundation

// MARK: - Design model
//
// "AI 生成主题" is a three-stage pipeline:
//   prompt -> ThemeDesign (semantic engine, optionally upgraded by an LLM)
//          -> Core Graphics rendering of a COMPLETE OpenCore resource set
//          -> makeTheme() skeleton + rebuildThemeManifest()
// Rendering happens locally so the feature works offline and produces real
// files (PNG / ICNS / Font.ttf) that the existing apply-to-EFI flow can use.

/// Visual treatment applied ON TOP of the original OpenCore icon artwork.
/// `auto` derives the treatment from the wallpaper style so different themes
/// produce visibly different icons instead of just a different tint.
enum AIIconStyle: String, CaseIterable {
    case auto, badge, glass, neon, ring, plain

    var title: String {
        switch self {
        case .auto:   return "自动（跟随主题风格）"
        case .badge:  return "圆角徽章 · 渐变底牌"
        case .glass:  return "玻璃拟态 · 半透光"
        case .neon:   return "霓虹发光 · 描边"
        case .ring:   return "圆形光环 · 徽章"
        case .plain:  return "原图染色 · 不加装饰"
        }
    }
    var short: String {
        switch self {
        case .auto:   return "自动风格"
        case .badge:  return "圆角徽章"
        case .glass:  return "玻璃拟态"
        case .neon:   return "霓虹发光"
        case .ring:   return "圆形光环"
        case .plain:  return "原图染色"
        }
    }
}

/// Wallpaper treatment. `plain` is the old flat gradient, kept as an explicit
/// opt-in; everything else draws a real scene so the background is not just a
/// solid colour.
enum AIBackgroundStyle: String, CaseIterable {
    case auto, mountains, aurora, grid, mist, plain

    var title: String {
        switch self {
        case .auto:      return "自动（有画面，跟随主题风格）"
        case .mountains: return "山峦剪影 · 远山与薄雾"
        case .aurora:    return "极光光带 · 星云"
        case .grid:      return "透视网格 · 霓虹落日"
        case .mist:      return "柔光雾面 · 光斑"
        case .plain:     return "纯色渐变 · 无图案"
        }
    }
    var short: String {
        switch self {
        case .auto:      return "自动场景"
        case .mountains: return "山峦剪影"
        case .aurora:    return "极光光带"
        case .grid:      return "透视网格"
        case .mist:      return "柔光雾面"
        case .plain:     return "纯色渐变"
        }
    }
}

struct AIThemeDesign {
    var name = "AI 主题"
    var style = "极光"
    var prompt = ""
    var palette: [String] = ["#101A32", "#1B2A50", "#0A1020"]
    var accent = "#5AC8FA"
    var glow = "#7B61FF"
    var decoration = "stars"       // stars / grid / rings / waves / none
    var density = 0.5
    var iconSet = "standard"       // standard / minimal / linux / full
    /// Re-colour the bundled OpenCore system icons into the generated palette
    /// while KEEPING their original artwork (Apple / Windows / Tux / drive…).
    /// Turning it off copies the stock ICNS verbatim.
    var restyleIcons = true
    /// auto / badge / glass / neon / ring / plain
    var iconStyle = "auto"
    /// auto / mountains / aurora / grid / mist / plain
    var backgroundStyle = "auto"
    var brightness: Double = 0
    var seed: UInt64 = 1
    var engine = "本地智能引擎"
    var fromLLM = false

    /// Resolve `auto` into a concrete treatment based on the wallpaper style.
    var resolvedIconStyle: String {
        if iconStyle != "auto" { return iconStyle }
        switch style {
        case "赛博霓虹", "电竞", "蒸汽波": return "neon"
        case "极光", "深空宇宙", "深海":   return "glass"
        case "水墨", "单色灰", "极简":     return "ring"
        default:                            return "badge"
        }
    }
    var iconStyleName: String {
        AIIconStyle(rawValue: resolvedIconStyle)?.short ?? "圆角徽章"
    }
    /// Resolve `auto` into a concrete wallpaper scene based on the style.
    var resolvedBackgroundStyle: String {
        if backgroundStyle != "auto" { return backgroundStyle }
        switch style {
        case "赛博霓虹", "蒸汽波", "电竞": return "grid"
        case "极光", "深空宇宙":           return "aurora"
        case "极简", "单色灰":             return "mist"
        default:                            return "mountains"
        }
    }
    var backgroundStyleName: String {
        AIBackgroundStyle(rawValue: resolvedBackgroundStyle)?.short ?? "山峦剪影"
    }
    var summary: String {
        let icons = restyleIcons ? "主题配色图标 · \(iconStyleName)" : "原样系统图标"
        return "\(style) · \(decorationName) · \(iconSetName) · \(backgroundStyleName) · \(icons)"
    }
    var decorationName: String {
        switch decoration {
        case "grid": return "网格"
        case "rings": return "光环"
        case "waves": return "波纹"
        case "none": return "纯净"
        default: return "星点"
        }
    }
    var iconSetName: String {
        switch iconSet {
        case "minimal": return "极简 4 图标"
        case "linux": return "多发行版 10 图标"
        case "full": return "全量图标"
        default: return "标准 8 图标"
        }
    }
}

// MARK: - Colours & deterministic randomness

func aiNSColor(_ hex: String, alpha: CGFloat = 1) -> NSColor {
    var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
    if s.hasPrefix("#") { s.removeFirst() }
    if s.count == 3 { s = s.map { "\($0)\($0)" }.joined() }
    guard s.count == 6, let v = UInt32(s, radix: 16) else {
        return NSColor(calibratedRed: 0.12, green: 0.16, blue: 0.28, alpha: alpha)
    }
    return NSColor(calibratedRed: CGFloat((v >> 16) & 0xff) / 255,
                   green: CGFloat((v >> 8) & 0xff) / 255,
                   blue: CGFloat(v & 0xff) / 255, alpha: alpha)
}

func aiCGColor(_ hex: String, alpha: CGFloat = 1) -> CGColor {
    aiNSColor(hex, alpha: alpha).cgColor
}

func aiAdjust(_ hex: String, delta: CGFloat, alpha: CGFloat = 1) -> CGColor {
    let c = aiNSColor(hex)
    var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
    c.getRed(&r, green: &g, blue: &b, alpha: &a)
    return NSColor(calibratedRed: min(1, max(0, r + delta)),
                   green: min(1, max(0, g + delta)),
                   blue: min(1, max(0, b + delta)), alpha: alpha).cgColor
}

struct AIRandom {
    var state: UInt64
    init(_ seed: UInt64) { state = seed == 0 ? 0x9E3779B97F4A7C15 : seed }
    mutating func next() -> Double {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return Double((state >> 17) & 0xffffff) / Double(0xffffff)
    }
    mutating func range(_ lo: CGFloat, _ hi: CGFloat) -> CGFloat {
        lo + CGFloat(next()) * (hi - lo)
    }
}

// MARK: - AI settings (OpenAI-compatible chat completions)

struct AISettings: Codable {
    var enabled = false
    var baseURL = "https://api.deepseek.com/v1"
    var apiKey = ""
    var model = "deepseek-chat"

    static var file: URL { Paths.support.appendingPathComponent("ai.json") }

    static func load() -> AISettings {
        guard let d = try? Data(contentsOf: file),
              let s = try? JSONDecoder().decode(AISettings.self, from: d) else {
            return AISettings()
        }
        return s
    }

    func save() {
        try? FileManager.default.createDirectory(at: Paths.support,
                                                  withIntermediateDirectories: true)
        guard let d = try? JSONEncoder().encode(self) else { return }
        try? d.write(to: AISettings.file, options: .atomic)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600],
                                               ofItemAtPath: AISettings.file.path)
    }

    static let presets: [(name: String, url: String, model: String)] = [
        ("DeepSeek", "https://api.deepseek.com/v1", "deepseek-chat"),
        ("OpenAI", "https://api.openai.com/v1", "gpt-4o-mini"),
        ("通义千问", "https://dashscope.aliyuncs.com/compatible-mode/v1", "qwen-plus"),
        ("Moonshot", "https://api.moonshot.cn/v1", "moonshot-v1-8k"),
        ("本地 Ollama", "http://localhost:11434/v1", "qwen2.5"),
    ]
}

// MARK: - Semantic style library

struct AIStyleTemplate {
    let key: String
    let name: String
    let keywords: [String]
    let palette: [String]
    let accent: String
    let glow: String
    let decoration: String
    let density: Double
}

enum AIThemeEngine {
    static let styles: [AIStyleTemplate] = [
        AIStyleTemplate(key: "cyberpunk", name: "赛博霓虹",
                        keywords: ["赛博", "霓虹", "cyber", "neon", "科幻", "未来", "黑客", "matrix"],
                        palette: ["#2A0B3F", "#120A2E", "#06122B"],
                        accent: "#FF4FD8", glow: "#22D3EE", decoration: "grid", density: 0.8),
        AIStyleTemplate(key: "aurora", name: "极光",
                        keywords: ["极光", "aurora", "梦幻", "渐变", "星空渐变"],
                        palette: ["#101A32", "#1B2A50", "#0A1020"],
                        accent: "#7AE7C7", glow: "#7B61FF", decoration: "stars", density: 0.6),
        AIStyleTemplate(key: "space", name: "深空宇宙",
                        keywords: ["星空", "宇宙", "银河", "太空", "space", "galaxy", "星云", "夜晚"],
                        palette: ["#0B1030", "#18103A", "#050713"],
                        accent: "#A5B4FC", glow: "#6D5AE6", decoration: "stars", density: 1.0),
        AIStyleTemplate(key: "ocean", name: "深海",
                        keywords: ["海", "海洋", "深海", "ocean", "蓝", "水", "青"],
                        palette: ["#062A38", "#0A3C50", "#04141F"],
                        accent: "#4FD1C5", glow: "#1E7FA8", decoration: "waves", density: 0.55),
        AIStyleTemplate(key: "forest", name: "森林",
                        keywords: ["森林", "自然", "绿", "forest", "草木", "清新", "苔"],
                        palette: ["#10281E", "#1B3D2B", "#07120E"],
                        accent: "#9BE58C", glow: "#3F9A6D", decoration: "rings", density: 0.5),
        AIStyleTemplate(key: "sunset", name: "落日",
                        keywords: ["日落", "黄昏", "夕阳", "sunset", "橙", "暖", "晚霞", "秋"],
                        palette: ["#3A1630", "#5A2530", "#160E20"],
                        accent: "#FFB27A", glow: "#E0625B", decoration: "waves", density: 0.45),
        AIStyleTemplate(key: "minimal", name: "极简",
                        keywords: ["极简", "简约", "干净", "minimal", "黑白", "商务", "素", "苹果", "mac"],
                        palette: ["#22262E", "#171A20", "#0C0E12"],
                        accent: "#E8EDF5", glow: "#5B6472", decoration: "none", density: 0.15),
        AIStyleTemplate(key: "sakura", name: "樱花",
                        keywords: ["樱花", "粉", "少女", "sakura", "粉彩", "可爱", "浪漫"],
                        palette: ["#3A1836", "#4A2246", "#1A0E22"],
                        accent: "#FFB3D9", glow: "#F173AC", decoration: "stars", density: 0.7),
        AIStyleTemplate(key: "retro", name: "蒸汽波",
                        keywords: ["复古", "蒸汽波", "retro", "vapor", "80年代", "怀旧", "像素"],
                        palette: ["#2B1250", "#5B1E63", "#100A2E"],
                        accent: "#FF8FD8", glow: "#43C6E8", decoration: "grid", density: 0.75),
        AIStyleTemplate(key: "ink", name: "水墨",
                        keywords: ["水墨", "中国风", "国风", "东方", "墨", "金", "山水", "禅"],
                        palette: ["#1A1C1E", "#25282B", "#0A0B0C"],
                        accent: "#D8B978", glow: "#8A7340", decoration: "rings", density: 0.35),
        AIStyleTemplate(key: "gaming", name: "电竞",
                        keywords: ["游戏", "电竞", "gaming", "rgb", "酷", "燃", "红黑"],
                        palette: ["#2B0A12", "#3A0D18", "#0A0508"],
                        accent: "#FF5A5F", glow: "#C0264A", decoration: "grid", density: 0.85),
        AIStyleTemplate(key: "mono", name: "单色灰",
                        keywords: ["单色", "灰", "mono", "冷", "银", "金属", "工业"],
                        palette: ["#232833", "#1A1F28", "#0D1016"],
                        accent: "#C7D0DD", glow: "#6B7688", decoration: "none", density: 0.2),
    ]

    static let inspirations = [
        "赛博朋克霓虹夜色，品红与青色对比，带细密网格",
        "清晨极光掠过深蓝湖面，安静通透",
        "深空宇宙与银河星尘，紫色星云",
        "极简黑白，干净克制，不要任何装饰",
        "雨后森林，苔绿与薄雾，同心光环",
        "落日余晖，暖橙与玫瑰紫，柔和波纹",
        "樱花夜，粉紫渐变，飘落的光点",
        "80 年代蒸汽波，紫色网格与霓虹",
        "水墨留白，墨黑与淡金，东方气质",
        "深海寂静，青蓝渐变，微微的水波",
        "电竞红黑，锐利光线与网格",
        "冷调金属灰，工业感，单色",
    ]

    private static let suffixes = ["夜航", "序曲", "余晖", "边界", "序章", "回声", "浮光",
                                   "静默", "远山", "潮汐", "微光", "轨迹", "之间", "彼端"]

    /// Turn a free-form prompt into a concrete design. Fully offline, always
    /// succeeds; the LLM path only refines the same structure.
    static func design(prompt: String, seed: UInt64? = nil) -> AIThemeDesign {
        let p = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let low = p.lowercased()
        let s = seed ?? (UInt64.random(in: 1...UInt64.max) ^ UInt64(abs(p.hashValue) & 0xffff))
        var rng = AIRandom(s)

        var best: AIStyleTemplate?
        var bestScore = 0
        for st in styles {
            let score = st.keywords.filter { low.contains($0.lowercased()) }.count
            if score > bestScore { bestScore = score; best = st }
        }
        let style = best ?? styles[Int(rng.range(0, CGFloat(styles.count))) % styles.count]

        var d = AIThemeDesign()
        d.prompt = p
        d.seed = s
        d.style = style.name
        d.palette = style.palette
        d.accent = style.accent
        d.glow = style.glow
        d.decoration = style.decoration
        d.density = style.density
        d.engine = "本地智能引擎"

        // Modifiers override parts of the template.
        if low.contains("明亮") || low.contains("浅色") || low.contains("bright") || low.contains("light") {
            d.brightness = 0.16
        } else if low.contains("更深") || low.contains("深黑") || low.contains("dark") {
            d.brightness = -0.07
        }
        if low.contains("网格") || low.contains("grid") { d.decoration = "grid" }
        if low.contains("圆环") || low.contains("光环") || low.contains("ring") { d.decoration = "rings" }
        if low.contains("波纹") || low.contains("波浪") || low.contains("wave") { d.decoration = "waves" }
        if low.contains("星") || low.contains("star") { d.decoration = "stars" }
        if low.contains("不要装饰") || low.contains("纯净") || low.contains("无装饰") || low.contains("clean") {
            d.decoration = "none"; d.density = 0.1
        }
        if low.contains("密集") || low.contains("丰富") { d.density = min(1, d.density + 0.3) }
        if low.contains("稀疏") || low.contains("少量") { d.density = max(0.1, d.density - 0.35) }
        if low.contains("极简") || low.contains("少量图标") || low.contains("四个图标") { d.iconSet = "minimal" }
        if low.contains("发行版") || low.contains("多系统") || low.contains("linux") { d.iconSet = "linux" }
        if low.contains("全部图标") || low.contains("全量") { d.iconSet = "full" }
        if low.contains("单色图标") || low.contains("统一色调") || low.contains("剪影")
            || low.contains("配色图标") || low.contains("改造图标") {
            d.restyleIcons = true
        }
        if low.contains("原样图标") || low.contains("保留原图标") || low.contains("原始图标")
            || low.contains("不要改图标") || low.contains("系统原版图标") {
            d.restyleIcons = false
        }
        // Explicit icon-style overrides. Without one, `auto` picks a treatment
        // that matches the wallpaper style (see resolvedIconStyle).
        if low.contains("霓虹图标") || low.contains("发光图标") || low.contains("描边图标") {
            d.iconStyle = "neon"
        }
        if low.contains("玻璃图标") || low.contains("毛玻璃") || low.contains("半透明图标") {
            d.iconStyle = "glass"
        }
        if low.contains("圆形图标") || low.contains("光环图标") || low.contains("圆环图标") {
            d.iconStyle = "ring"
        }
        if low.contains("徽章图标") || low.contains("方牌图标") || low.contains("卡片图标") {
            d.iconStyle = "badge"
        }
        if low.contains("原图染色") || low.contains("只换颜色") || low.contains("不要图标风格") {
            d.iconStyle = "plain"
        }
        if low.contains("自动图标风格") { d.iconStyle = "auto" }
        // Background: plain is an explicit opt-in, never the default.
        if low.contains("纯色背景") || low.contains("纯色壁纸") || low.contains("简洁背景")
            || low.contains("不要背景图案") || low.contains("素色背景") {
            d.backgroundStyle = "plain"
        }
        if low.contains("山峦背景") || low.contains("山水背景") || low.contains("远山背景") {
            d.backgroundStyle = "mountains"
        }
        if low.contains("极光背景") || low.contains("星云背景") {
            d.backgroundStyle = "aurora"
        }
        if low.contains("网格背景") || low.contains("透视背景") || low.contains("霓虹落日") {
            d.backgroundStyle = "grid"
        }
        if low.contains("雾面背景") || low.contains("柔和背景") || low.contains("光斑背景") {
            d.backgroundStyle = "mist"
        }
        if low.contains("自动背景") { d.backgroundStyle = "auto" }
        d.name = extractName(p) ?? "\(style.name) · \(suffixes[Int(rng.range(0, CGFloat(suffixes.count))) % suffixes.count])"
        return d
    }

    private static func extractName(_ p: String) -> String? {
        for pair in [("「", "」"), ("《", "》"), ("\"", "\""), ("'", "'")] {
            if let a = p.range(of: pair.0), let b = p.range(of: pair.1, range: a.upperBound..<p.endIndex) {
                let s = String(p[a.upperBound..<b.lowerBound]).trimmingCharacters(in: .whitespaces)
                if !s.isEmpty && s.count <= 24 { return s }
            }
        }
        for key in ["叫", "命名为", "名字叫", "主题名", "name:"] {
            if let r = p.range(of: key) {
                let tail = String(p[r.upperBound...])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                let name = tail.components(separatedBy: CharacterSet(charactersIn: "，,。.;； ")).first ?? ""
                if !name.isEmpty && name.count <= 24 { return name }
            }
        }
        return nil
    }

    // MARK: LLM refinement

    private static let systemPrompt = """
    你是 OpenCore 启动菜单主题设计师。用户会用中文描述想要的风格，请输出严格 JSON（不要 markdown 代码块、不要解释），字段：
    {"name":"主题名（<=16字，中文）","style":"风格名","palette":["#RRGGBB","#RRGGBB","#RRGGBB"],"accent":"#RRGGBB","glow":"#RRGGBB","decoration":"stars|grid|rings|waves|none","density":0.0~1.0,"iconSet":"standard|minimal|linux|full","restyleIcons":true,"iconStyle":"auto|badge|glass|neon|ring|plain","backgroundStyle":"auto|mountains|aurora|grid|mist|plain"}
    palette 是壁纸的三段渐变色，必须是深色（启动菜单图标是白色的），accent 是选中框/光标的高亮色，glow 是光晕色。restyleIcons 为 true 时把原有系统图标按主题配色重新着色（保留造型），false 时使用原样图标。iconStyle 决定图标风格：auto 跟随整体风格，badge 圆角渐变底牌，glass 玻璃拟态，neon 霓虹发光，ring 圆形光环，plain 只染色不加装饰。backgroundStyle 决定壁纸画面：auto 跟随整体风格（默认有画面），mountains 山峦剪影，aurora 极光光带，grid 透视网格与霓虹落日，mist 柔光雾面，plain 纯色渐变无图案。除非用户明确要纯色，不要选 plain。整体要协调且符合用户描述。
    """

    /// Parse the model's free-form reply into a design. Tolerates markdown
    /// fences and partial JSON: missing fields keep the offline engine's values.
    /// Extract a JSON object from arbitrary LLM prose without ever forming an
    /// invalid String range. Tries every "{" as a potential start, walks with a
    /// brace-depth counter (ignoring braces inside string literals), and returns
    /// the first candidate that actually parses as a JSON dictionary.
    /// A naive first-"{" + last-"}" slice crashes (String.index(after:)
    /// assertion) when a stray "}" appears before the "{", which DeepSeek and
    /// some CN models emit — so we validate each candidate instead.
    static func jsonObject(from text: String) -> [String: Any]? {
        var i = text.startIndex
        while i < text.endIndex {
            if text[i] == "{" {
                if let end = balancedEnd(in: text, from: i),
                   let obj = (try? JSONSerialization.jsonObject(
                       with: Data(text[i...end].utf8))) as? [String: Any] {
                    return obj
                }
            }
            i = text.index(after: i)
        }
        return nil
    }

    /// Given the index of an opening "{", return the index of its matching "}".
    private static func balancedEnd(in text: String, from start: String.Index) -> String.Index? {
        var depth = 0
        var inString = false
        var escaped = false
        var i = start
        while i < text.endIndex {
            let c = text[i]
            if inString {
                if escaped { escaped = false }
                else if c == "\\" { escaped = true }
                else if c == "\"" { inString = false }
            } else {
                if c == "\"" { inString = true }
                else if c == "{" { depth += 1 }
                else if c == "}" {
                    depth -= 1
                    if depth == 0 { return i }
                }
            }
            i = text.index(after: i)
        }
        return nil
    }

    static func parseLLMDesign(_ content: String, prompt: String,
                               model: String) -> AIThemeDesign? {
        let text = content.replacingOccurrences(of: "```json", with: "")
                          .replacingOccurrences(of: "```", with: "")
        guard let obj = jsonObject(from: text) else { return nil }
        var d = AIThemeEngine.design(prompt: prompt)
        if let s = obj["name"] as? String, !s.isEmpty { d.name = String(s.prefix(24)) }
        if let s = obj["style"] as? String, !s.isEmpty { d.style = s }
        if let p = obj["palette"] as? [String], p.count >= 3 { d.palette = Array(p.prefix(3)) }
        if let s = obj["accent"] as? String, !s.isEmpty { d.accent = s }
        if let s = obj["glow"] as? String, !s.isEmpty { d.glow = s }
        if let s = obj["decoration"] as? String,
           ["stars", "grid", "rings", "waves", "none"].contains(s) { d.decoration = s }
        if let n = obj["density"] as? Double { d.density = min(1, max(0, n)) }
        if let s = obj["iconSet"] as? String,
           ["standard", "minimal", "linux", "full"].contains(s) { d.iconSet = s }
        if let b = obj["restyleIcons"] as? Bool { d.restyleIcons = b }
        // Backwards compatibility with older model replies / presets.
        else if let b = obj["monochromeIcons"] as? Bool { d.restyleIcons = b }
        if let s = obj["iconStyle"] as? String,
           AIIconStyle.allCases.map({ $0.rawValue }).contains(s) { d.iconStyle = s }
        if let s = obj["backgroundStyle"] as? String,
           AIBackgroundStyle.allCases.map({ $0.rawValue }).contains(s) {
            d.backgroundStyle = s
        }
        d.fromLLM = true
        d.engine = "大模型 · \(model)"
        return d
    }

    /// Ask an OpenAI-compatible endpoint for a design. Always calls back on the
    /// main thread; the caller falls back to the offline design on any failure.
    static func refineWithLLM(prompt: String, settings: AISettings,
                              done: @escaping (Result<AIThemeDesign, Error>) -> Void) {
        guard settings.enabled, !settings.apiKey.isEmpty else {
            done(.failure(AppError.message("未启用大模型增强")))
            return
        }
        let base = settings.baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: base + "/chat/completions") else {
            done(.failure(AppError.message("API 地址格式不正确")))
            return
        }
        let body: [String: Any] = [
            "model": settings.model,
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": prompt.isEmpty ? "随机设计一个好看的深色启动主题" : prompt],
            ] as [[String: String]],
            "temperature": 0.9,
        ]
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 30
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer " + settings.apiKey, forHTTPHeaderField: "Authorization")
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)

        URLSession.shared.dataTask(with: req) { data, resp, err in
            let finish: (Result<AIThemeDesign, Error>) -> Void = { r in
                DispatchQueue.main.async { done(r) }
            }
            if let err = err { finish(.failure(err)); return }
            guard let data = data else {
                finish(.failure(AppError.message("大模型没有返回内容"))); return
            }
            guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
                finish(.failure(AppError.message("大模型返回无法解析"))); return
            }
            if let e = root["error"] as? [String: Any], let m = e["message"] as? String {
                finish(.failure(AppError.message(m))); return
            }
            guard let choices = root["choices"] as? [[String: Any]],
                  let msg = choices.first?["message"] as? [String: Any],
                  let text = msg["content"] as? String else {
                finish(.failure(AppError.message("大模型返回缺少 choices"))); return
            }
            guard let d = parseLLMDesign(text, prompt: prompt, model: settings.model) else {
                finish(.failure(AppError.message("大模型没有返回有效的 JSON 设计"))); return
            }
            finish(.success(d))
        }.resume()
    }
}

// MARK: - Core Graphics rendering

enum AIThemeRenderer {
    static let wallpaperSize = CGSize(width: 1600, height: 900)

    static func png(_ size: CGSize, draw: (CGContext, CGSize) -> Void) -> Data? {
        let w = Int(size.width), h = Int(size.height)
        guard w > 0, h > 0,
              let ctx = CGContext(data: nil, width: w, height: h,
                                  bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        draw(ctx, size)
        guard let cg = ctx.makeImage() else { return nil }
        return NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:])
    }

    static func wallpaper(_ d: AIThemeDesign) -> Data? {
        png(wallpaperSize) { ctx, sz in
            let W = sz.width, H = sz.height
            let shift = CGFloat(d.brightness)
            let p = d.palette
            let cs = CGColorSpaceCreateDeviceRGB()
            let grad = CGGradient(colorsSpace: cs,
                                  colors: [aiAdjust(p[0], delta: shift),
                                           aiAdjust(p[1], delta: shift),
                                           aiAdjust(p[2], delta: shift)] as CFArray,
                                  locations: [0, 0.52, 1])!
            ctx.drawLinearGradient(grad, start: CGPoint(x: 0, y: H),
                                   end: CGPoint(x: W, y: 0), options: [])

            var rng = AIRandom(d.seed)
            // `plain` is the old flat look, now an explicit opt-in.
            if d.resolvedBackgroundStyle != "plain" {
                let glowA = aiCGColor(d.glow, alpha: 0.42)
                let glowB = aiCGColor(d.glow, alpha: 0)
                let g = CGGradient(colorsSpace: cs, colors: [glowA, glowB] as CFArray,
                                   locations: [0, 1])!
                let cA = CGPoint(x: W * rng.range(0.15, 0.45), y: H * rng.range(0.35, 0.75))
                let cB = CGPoint(x: W * rng.range(0.6, 0.9), y: H * rng.range(0.2, 0.7))
                ctx.drawRadialGradient(g, startCenter: cA, startRadius: 0,
                                       endCenter: cA, endRadius: W * 0.55, options: [])
                ctx.drawRadialGradient(g, startCenter: cB, startRadius: 0,
                                       endCenter: cB, endRadius: W * 0.42, options: [])

                drawScene(d.resolvedBackgroundStyle, d, ctx: ctx, size: sz, rng: &rng)
                drawDecoration(d, ctx: ctx, size: sz, rng: &rng)
                drawGrain(ctx, W: W, H: H, rng: &rng)
            }

            // Vignette keeps white boot icons readable near the edges.
            let clear = NSColor(calibratedRed: 0, green: 0, blue: 0, alpha: 0).cgColor
            let dark = NSColor(calibratedRed: 0.01, green: 0.02, blue: 0.04, alpha: 0.48).cgColor
            let vig = CGGradient(colorsSpace: cs, colors: [clear, dark] as CFArray,
                                 locations: [0.5, 1])!
            let center = CGPoint(x: W / 2, y: H / 2)
            ctx.drawRadialGradient(vig, startCenter: center, startRadius: 0,
                                   endCenter: center, endRadius: W * 0.78, options: [])
        }
    }

    /// A real, procedurally drawn scene so the wallpaper is not just a solid
    /// gradient. All geometry stays low-contrast and below the icon row so the
    /// boot picker labels remain readable.
    private static func drawScene(_ kind: String, _ d: AIThemeDesign,
                                  ctx: CGContext, size: CGSize,
                                  rng: inout AIRandom) {
        let W = size.width, H = size.height
        let cs = CGColorSpaceCreateDeviceRGB()
        let transparent = aiCGColor(d.glow, alpha: 0)

        switch kind {
        case "mountains":
            // Distant moon / halo.
            let mx = W * rng.range(0.66, 0.86), my = H * rng.range(0.66, 0.80)
            let halo = CGGradient(colorsSpace: cs,
                                  colors: [aiCGColor(d.accent, alpha: 0.22),
                                           transparent] as CFArray,
                                  locations: [0, 1])!
            ctx.drawRadialGradient(halo, startCenter: CGPoint(x: mx, y: my),
                                   startRadius: 0,
                                   endCenter: CGPoint(x: mx, y: my),
                                   endRadius: H * 0.42, options: [])
            ctx.setFillColor(NSColor(calibratedWhite: 1, alpha: 0.10).cgColor)
            ctx.fillEllipse(in: CGRect(x: mx - 44, y: my - 44, width: 88, height: 88))

            // Four ridges, far (high, hazy) to near (low, dark).
            for i in 0..<4 {
                let t = CGFloat(i)
                let base = H * (0.31 - 0.062 * t)
                let amp = H * (0.030 + 0.014 * t)
                let phase = rng.range(0, 6)
                let fill = cg(mix(rgb(d.palette[2]),
                                  rgb(d.glow), 0.13 - 0.03 * t), alpha: 0.92)
                ctx.beginPath()
                ctx.move(to: CGPoint(x: 0, y: 0))
                var x: CGFloat = 0
                while x <= W + 12 {
                    let y = base + sin(x / 265 + phase) * amp
                              + sin(x / 96 + phase * 1.7) * amp * 0.34
                    ctx.addLine(to: CGPoint(x: x, y: y))
                    x += 12
                }
                ctx.addLine(to: CGPoint(x: W, y: 0))
                ctx.closePath()
                ctx.setFillColor(fill)
                ctx.fillPath()
                // A hairline of accent on each ridge reads as atmospheric haze.
                ctx.beginPath()
                x = 0
                while x <= W + 12 {
                    let y = base + sin(x / 265 + phase) * amp
                              + sin(x / 96 + phase * 1.7) * amp * 0.34
                    if x == 0 { ctx.move(to: CGPoint(x: x, y: y)) }
                    else { ctx.addLine(to: CGPoint(x: x, y: y)) }
                    x += 12
                }
                ctx.setStrokeColor(aiCGColor(d.accent, alpha: 0.10 + 0.03 * t))
                ctx.setLineWidth(1.5)
                ctx.strokePath()
            }
            // Low fog bands blend the ridges into the wallpaper.
            for i in 0..<3 {
                ctx.setFillColor(NSColor(calibratedWhite: 1, alpha: 0.022).cgColor)
                ctx.fill(CGRect(x: 0, y: H * (0.12 + 0.09 * CGFloat(i)),
                                width: W, height: H * 0.055))
            }

        case "aurora":
            for _ in 0..<5 {
                let x0 = W * rng.range(0.08, 0.88)
                let w = W * rng.range(0.11, 0.26)
                let phase = rng.range(0, 6)
                let bend = W * rng.range(0.03, 0.09)
                ctx.saveGState()
                ctx.setBlendMode(.screen)
                ctx.beginPath()
                var y: CGFloat = -20
                while y <= H + 20 {
                    let cx = x0 + sin(y / 190 + phase) * bend
                    if y <= -20 { ctx.move(to: CGPoint(x: cx - w / 2, y: y)) }
                    else { ctx.addLine(to: CGPoint(x: cx - w / 2, y: y)) }
                    y += 22
                }
                y = H + 20
                while y >= -20 {
                    let cx = x0 + sin(y / 190 + phase) * bend
                    ctx.addLine(to: CGPoint(x: cx + w / 2, y: y))
                    y -= 22
                }
                ctx.closePath()
                ctx.clip()
                let band = CGGradient(colorsSpace: cs,
                                      colors: [transparent,
                                               aiCGColor(d.accent, alpha: 0.30),
                                               aiCGColor(d.glow, alpha: 0.16),
                                               transparent] as CFArray,
                                      locations: [0, 0.35, 0.68, 1])!
                ctx.drawLinearGradient(band, start: CGPoint(x: 0, y: 0),
                                       end: CGPoint(x: 0, y: H), options: [])
                ctx.restoreGState()
            }
            // Brighter foreground stars.
            for _ in 0..<70 {
                let x = rng.range(0, W), y = rng.range(H * 0.25, H)
                let r = rng.range(0.8, 2.2)
                ctx.setFillColor(NSColor(calibratedWhite: 1,
                                         alpha: CGFloat(0.20 + rng.next() * 0.45)).cgColor)
                ctx.fillEllipse(in: CGRect(x: x - r, y: y - r,
                                           width: r * 2, height: r * 2))
            }

        case "grid":
            // Neon sun disc with horizontal cut-outs, above the icon row.
            let sx = W * 0.5, sy = H * 0.70, r = H * 0.155
            let halo = CGGradient(colorsSpace: cs,
                                  colors: [aiCGColor(d.accent, alpha: 0.28),
                                           transparent] as CFArray,
                                  locations: [0, 1])!
            ctx.drawRadialGradient(halo, startCenter: CGPoint(x: sx, y: sy),
                                   startRadius: 0,
                                   endCenter: CGPoint(x: sx, y: sy),
                                   endRadius: r * 2.4, options: [])
            ctx.saveGState()
            ctx.addEllipse(in: CGRect(x: sx - r, y: sy - r, width: r * 2, height: r * 2))
            ctx.clip()
            let sun = CGGradient(colorsSpace: cs,
                                 colors: [aiCGColor(d.accent, alpha: 0.55),
                                          aiCGColor(d.glow, alpha: 0.32)] as CFArray,
                                 locations: [0, 1])!
            ctx.drawLinearGradient(sun, start: CGPoint(x: sx, y: sy + r),
                                   end: CGPoint(x: sx, y: sy - r), options: [])
            ctx.setBlendMode(.destinationOut)
            for i in 0..<7 {
                let y = sy - r * 0.12 - CGFloat(i) * r * 0.15
                ctx.setFillColor(NSColor(calibratedWhite: 1, alpha: 1).cgColor)
                ctx.fill(CGRect(x: sx - r, y: y, width: r * 2,
                                height: 3 + CGFloat(i) * 1.5))
            }
            ctx.restoreGState()

            // Perspective floor: vanishing rays + rows that widen downwards.
            let hy = H * 0.40
            ctx.setStrokeColor(aiCGColor(d.accent, alpha: 0.30))
            ctx.setLineWidth(1.5)
            ctx.beginPath()
            for i in -12...12 {
                ctx.move(to: CGPoint(x: sx, y: hy))
                ctx.addLine(to: CGPoint(x: sx + CGFloat(i) * W * 0.11, y: 0))
            }
            ctx.strokePath()
            ctx.beginPath()
            for i in 1...12 {
                let t = CGFloat(i) / 12
                let y = hy * (1 - pow(t, 1.7))
                ctx.move(to: CGPoint(x: 0, y: y))
                ctx.addLine(to: CGPoint(x: W, y: y))
            }
            ctx.strokePath()
            ctx.setStrokeColor(aiCGColor(d.accent, alpha: 0.55))
            ctx.setLineWidth(2.5)
            ctx.beginPath()
            ctx.move(to: CGPoint(x: 0, y: hy)); ctx.addLine(to: CGPoint(x: W, y: hy))
            ctx.strokePath()

        case "mist":
            // Restrained, but still a picture: layered bokeh + fog + a soft
            // diagonal light shaft. Kept for 极简 / 单色灰.
            for _ in 0..<10 {
                let c = CGPoint(x: rng.range(0, W), y: rng.range(H * 0.18, H * 0.95))
                let rr = rng.range(H * 0.12, H * 0.34)
                let g = CGGradient(colorsSpace: cs,
                                   colors: [aiCGColor(d.glow, alpha: 0.26),
                                            transparent] as CFArray,
                                   locations: [0, 1])!
                ctx.drawRadialGradient(g, startCenter: c, startRadius: 0,
                                       endCenter: c, endRadius: rr, options: [])
            }
            for _ in 0..<7 {
                let x = rng.range(W * 0.08, W * 0.92)
                let y = rng.range(H * 0.20, H * 0.88)
                let r = rng.range(18, 74)
                ctx.setStrokeColor(NSColor(calibratedWhite: 1, alpha: 0.055).cgColor)
                ctx.setLineWidth(1.5)
                ctx.strokeEllipse(in: CGRect(x: x - r, y: y - r,
                                             width: r * 2, height: r * 2))
            }
            let shaft = CGGradient(colorsSpace: cs,
                                   colors: [transparent,
                                            NSColor(calibratedWhite: 1, alpha: 0.055).cgColor,
                                            transparent] as CFArray,
                                   locations: [0, 0.5, 1])!
            ctx.drawLinearGradient(shaft,
                                   start: CGPoint(x: W * 0.10, y: H * 0.95),
                                   end: CGPoint(x: W * 0.72, y: H * 0.15),
                                   options: [])
            for i in 0..<4 {
                ctx.setFillColor(NSColor(calibratedWhite: 1, alpha: 0.035).cgColor)
                ctx.fill(CGRect(x: 0, y: H * (0.16 + 0.17 * CGFloat(i)),
                                width: W, height: H * 0.055))
            }

        default:
            break
        }
    }

    /// Fine film grain keeps large gradients from reading as flat solid colour.
    private static func drawGrain(_ ctx: CGContext, W: CGFloat, H: CGFloat,
                                  rng: inout AIRandom) {
        for _ in 0..<1500 {
            let x = rng.range(0, W), y = rng.range(0, H)
            let light = rng.next() > 0.5
            let a = CGFloat(0.015 + rng.next() * 0.045)
            ctx.setFillColor(NSColor(calibratedWhite: light ? 1 : 0, alpha: a).cgColor)
            ctx.fill(CGRect(x: x, y: y, width: 1.3, height: 1.3))
        }
    }

    private static func drawDecoration(_ d: AIThemeDesign, ctx: CGContext,
                                       size: CGSize, rng: inout AIRandom) {
        let W = size.width, H = size.height
        switch d.decoration {
        case "grid":
            ctx.setStrokeColor(aiCGColor(d.accent, alpha: 0.075))
            ctx.setLineWidth(1)
            let step: CGFloat = 76
            var x: CGFloat = 0
            while x <= W { ctx.move(to: CGPoint(x: x, y: 0)); ctx.addLine(to: CGPoint(x: x, y: H)); ctx.strokePath(); x += step }
            var y: CGFloat = 0
            while y <= H { ctx.move(to: CGPoint(x: 0, y: y)); ctx.addLine(to: CGPoint(x: W, y: y)); ctx.strokePath(); y += step }
            ctx.setStrokeColor(aiCGColor(d.accent, alpha: 0.16))
            ctx.setLineWidth(2)
            ctx.stroke(CGRect(x: W * 0.08, y: H * 0.12, width: W * 0.84, height: H * 0.76))
        case "rings":
            ctx.setStrokeColor(aiCGColor(d.accent, alpha: 0.10))
            for i in 0..<6 {
                let r = W * (0.12 + CGFloat(i) * 0.075)
                ctx.setLineWidth(i % 2 == 0 ? 2 : 1)
                ctx.strokeEllipse(in: CGRect(x: W * 0.68 - r, y: H * 0.42 - r,
                                             width: r * 2, height: r * 2))
            }
        case "waves":
            ctx.setStrokeColor(aiCGColor(d.accent, alpha: 0.12))
            for i in 0..<5 {
                ctx.setLineWidth(i == 0 ? 2 : 1)
                let baseY = H * (0.18 + CGFloat(i) * 0.16)
                ctx.move(to: CGPoint(x: 0, y: baseY))
                var px: CGFloat = 0
                while px <= W {
                    let y = baseY + sin(px / 170 + CGFloat(i) * 0.8) * 26
                    ctx.addLine(to: CGPoint(x: px, y: y))
                    px += 8
                }
                ctx.strokePath()
            }
        case "stars":
            let count = Int(90 + d.density * 210)
            for _ in 0..<count {
                let x = rng.range(0, W), y = rng.range(0, H)
                let r = rng.range(0.5, 1.8)
                let a = CGFloat(0.12 + rng.next() * 0.5)
                ctx.setFillColor(NSColor(calibratedRed: 0.92, green: 0.95, blue: 1,
                                         alpha: a).cgColor)
                ctx.fillEllipse(in: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2))
            }
            for _ in 0..<6 {
                let x = rng.range(0, W), y = rng.range(0, H), r = rng.range(3, 7)
                ctx.setFillColor(aiCGColor(d.accent, alpha: 0.22))
                ctx.fillEllipse(in: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2))
            }
        default:
            break
        }
        // A very subtle accent line grounds the composition in every style.
        ctx.setStrokeColor(aiCGColor(d.accent, alpha: 0.10))
        ctx.setLineWidth(2)
        ctx.move(to: CGPoint(x: W * 0.06, y: H * 0.09))
        ctx.addLine(to: CGPoint(x: W * 0.06 + 110, y: H * 0.09))
        ctx.strokePath()
    }

    static func selectionBox(_ d: AIThemeDesign) -> Data? {
        png(CGSize(width: 200, height: 200)) { ctx, sz in
            let r = CGRect(x: 7, y: 7, width: sz.width - 14, height: sz.height - 14)
            let path = CGPath(roundedRect: r, cornerWidth: 20, cornerHeight: 20,
                              transform: nil)
            ctx.setFillColor(aiCGColor(d.accent, alpha: 0.13))
            ctx.addPath(path); ctx.fillPath()
            ctx.setStrokeColor(aiCGColor(d.accent, alpha: 0.95))
            ctx.setLineWidth(5)
            ctx.addPath(path); ctx.strokePath()
            ctx.setFillColor(aiCGColor(d.accent, alpha: 0.95))
            for p in [CGPoint(x: 7, y: 7), CGPoint(x: sz.width - 7, y: 7),
                      CGPoint(x: 7, y: sz.height - 7), CGPoint(x: sz.width - 7, y: sz.height - 7)] {
                ctx.fillEllipse(in: CGRect(x: p.x - 5, y: p.y - 5, width: 10, height: 10))
            }
        }
    }

    static func cursor(_ d: AIThemeDesign) -> Data? {
        png(CGSize(width: 24, height: 24)) { ctx, _ in
            ctx.beginPath()
            ctx.move(to: CGPoint(x: 2, y: 22))
            ctx.addLine(to: CGPoint(x: 2, y: 2))
            ctx.addLine(to: CGPoint(x: 8.5, y: 16))
            ctx.addLine(to: CGPoint(x: 12.5, y: 16))
            ctx.addLine(to: CGPoint(x: 17, y: 21))
            ctx.addLine(to: CGPoint(x: 20, y: 19))
            ctx.addLine(to: CGPoint(x: 15.5, y: 14))
            ctx.addLine(to: CGPoint(x: 20, y: 13.5))
            ctx.closePath()
            ctx.setFillColor(aiCGColor(d.accent))
            ctx.fillPath()
            ctx.setStrokeColor(NSColor(calibratedWhite: 1, alpha: 0.85).cgColor)
            ctx.setLineWidth(1)
            ctx.strokePath()
        }
    }

    static func dot(_ d: AIThemeDesign) -> Data? {
        png(CGSize(width: 12, height: 12)) { ctx, sz in
            ctx.setFillColor(aiCGColor(d.accent))
            ctx.fillEllipse(in: CGRect(x: 1, y: 1, width: sz.width - 2, height: sz.height - 2))
        }
    }

    static func focusBox(_ d: AIThemeDesign) -> Data? {
        png(CGSize(width: 220, height: 48)) { ctx, sz in
            let r = CGRect(x: 2, y: 2, width: sz.width - 4, height: sz.height - 4)
            let path = CGPath(roundedRect: r, cornerWidth: 10, cornerHeight: 10, transform: nil)
            ctx.setFillColor(aiCGColor(d.accent, alpha: 0.14))
            ctx.addPath(path); ctx.fillPath()
            ctx.setStrokeColor(aiCGColor(d.accent, alpha: 0.85))
            ctx.setLineWidth(2)
            ctx.addPath(path); ctx.strokePath()
        }
    }

    // MARK: - System icons: restyle the ORIGINAL OpenCore artwork
    //
    // The bundled ICNS set holds the real macOS / Windows / Linux / drive
    // artwork. Recolouring it with `.sourceIn` flattened everything into a
    // solid square, because most of those icons are a light glyph on an opaque
    // dark tile. Instead we map each source pixel's LUMINANCE onto a three-stop
    // palette (dark tile -> accent -> near white). The glyph, the 3D shading
    // and the alpha all survive, so icons stay recognisable while picking up
    // the generated theme's colours.

    private struct AIRGB { var r: CGFloat, g: CGFloat, b: CGFloat }

    private static func rgb(_ hex: String) -> AIRGB {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        aiNSColor(hex).getRed(&r, green: &g, blue: &b, alpha: &a)
        return AIRGB(r: r, g: g, b: b)
    }

    private static func mix(_ a: AIRGB, _ b: AIRGB, _ t: CGFloat) -> AIRGB {
        let k = min(1, max(0, t))
        return AIRGB(r: a.r + (b.r - a.r) * k,
                     g: a.g + (b.g - a.g) * k,
                     b: a.b + (b.b - a.b) * k)
    }

    private static func cg(_ c: AIRGB, alpha: CGFloat = 1) -> CGColor {
        NSColor(calibratedRed: c.r, green: c.g, blue: c.b, alpha: alpha).cgColor
    }

    /// Fixed-layout RGBA bitmap: premultiplied, R,G,B,A order in memory.
    private static func rgbaContext(_ side: Int) -> CGContext? {
        let info = CGBitmapInfo.byteOrder32Big.rawValue
                 | CGImageAlphaInfo.premultipliedLast.rawValue
        return CGContext(data: nil, width: side, height: side,
                         bitsPerComponent: 8, bytesPerRow: 0,
                         space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: info)
    }

    static func iconSource(_ file: String) -> URL? {
        guard let dir = ThemePreset.iconsDir else { return nil }
        let u = dir.appendingPathComponent(file)
        return FileManager.default.fileExists(atPath: u.path) ? u : nil
    }

    /// Recolour one bundled ICNS into a themed PNG, preserving its artwork.
    /// When `extractGlyph` is set, icons that ship with an opaque dark square
    /// tile (Apple / Linux / Ubuntu) have that tile keyed out, leaving a clean
    /// transparent logo that can be dropped onto a styled backdrop.
    static func styledIconPNG(_ src: URL, _ d: AIThemeDesign,
                              side: Int = 256,
                              extractGlyph: Bool = false) -> Data? {
        guard let img = NSImage(contentsOf: src),
              let cg = img.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let srcCtx = rgbaContext(side), let dstCtx = rgbaContext(side),
              let srcData = srcCtx.data, let dstData = dstCtx.data else { return nil }
        srcCtx.draw(cg, in: CGRect(x: 0, y: 0, width: side, height: side))
        let inp = srcData.assumingMemoryBound(to: UInt8.self)
        let outp = dstData.assumingMemoryBound(to: UInt8.self)

        let dark = mix(rgb(d.palette.first ?? "#101A32"),
                       AIRGB(r: 0, g: 0, b: 0), 0.32)
        let mid = rgb(d.accent)
        let light = mix(mid, AIRGB(r: 1, g: 1, b: 1), 0.80)

        // Apple / Linux / Ubuntu ship a ROUNDED dark tile: the absolute corners
        // are transparent, so sample just inside the round corners instead.
        // Those four points are bright artwork on the drive/terminal icons and
        // dark background on the glyph-on-tile icons — a reliable discriminator.
        var cornerLum: CGFloat = 0
        var opaqueCorners = true
        if extractGlyph {
            let f: [CGFloat] = [0.16, 0.84]
            let pts: [(CGFloat, CGFloat)] = [(f[0], f[0]), (f[1], f[0]),
                                             (f[0], f[1]), (f[1], f[1])]
            for (fx, fy) in pts {
                let x = Int(fx * CGFloat(side)), y = Int(fy * CGFloat(side))
                let o = (y * side + x) * 4
                let a = CGFloat(inp[o + 3]) / 255
                if a < 0.85 { opaqueCorners = false }
                let inv: CGFloat = a > 0.004 ? 1 / a : 0
                let r = min(1, CGFloat(inp[o])     / 255 * inv)
                let g = min(1, CGFloat(inp[o + 1]) / 255 * inv)
                let b = min(1, CGFloat(inp[o + 2]) / 255 * inv)
                cornerLum += 0.2126 * r + 0.7152 * g + 0.0722 * b
            }
            cornerLum /= CGFloat(pts.count)
        }
        let hasDarkTile = extractGlyph && opaqueCorners && cornerLum < 0.45
        let lo = cornerLum + 0.03, hi = cornerLum + 0.22

        for i in 0..<(side * side) {
            let o = i * 4
            let a = CGFloat(inp[o + 3]) / 255
            let inv: CGFloat = a > 0.004 ? 1 / a : 0   // undo premultiplication
            let r = min(1, CGFloat(inp[o])     / 255 * inv)
            let g = min(1, CGFloat(inp[o + 1]) / 255 * inv)
            let b = min(1, CGFloat(inp[o + 2]) / 255 * inv)
            let lum = 0.2126 * r + 0.7152 * g + 0.0722 * b
            let t = pow(min(1, max(0, lum)), 0.85)
            let c = t < 0.5 ? mix(dark, mid, t / 0.5)
                            : mix(mid, light, (t - 0.5) / 0.5)
            var alpha = a
            if hasDarkTile {
                let k = min(1, max(0, (lum - lo) / (hi - lo)))
                alpha *= k * k * (3 - 2 * k)          // smoothstep
            }
            outp[o]     = UInt8(min(255, max(0, c.r * alpha * 255)))
            outp[o + 1] = UInt8(min(255, max(0, c.g * alpha * 255)))
            outp[o + 2] = UInt8(min(255, max(0, c.b * alpha * 255)))
            outp[o + 3] = UInt8(min(255, max(0, alpha * 255)))
        }
        guard let out = dstCtx.makeImage() else { return nil }
        return NSBitmapImageRep(cgImage: out).representation(using: .png, properties: [:])
    }

    /// Style backdrop drawn UNDER the (still recognisable) system logo.
    private static func iconBackdrop(_ kind: String, _ d: AIThemeDesign,
                                     ctx: CGContext, s: CGFloat) {
        let rect = CGRect(x: 0, y: 0, width: s, height: s)
        let center = CGPoint(x: s / 2, y: s / 2)
        let cs = CGColorSpaceCreateDeviceRGB()
        let clear = NSColor(calibratedWhite: 1, alpha: 0).cgColor

        switch kind {
        case "badge":
            // Solid, saturated gradient tile — deliberately the heaviest look.
            let r = rect.insetBy(dx: s * 0.025, dy: s * 0.025)
            let path = CGPath(roundedRect: r, cornerWidth: s * 0.22,
                              cornerHeight: s * 0.22, transform: nil)
            ctx.saveGState(); ctx.addPath(path); ctx.clip()
            let top = cg(mix(rgb(d.palette[1]), rgb(d.accent), 0.42))
            let g = CGGradient(colorsSpace: cs,
                               colors: [top, aiCGColor(d.palette[0])] as CFArray,
                               locations: [0, 1])!
            ctx.drawLinearGradient(g, start: CGPoint(x: 0, y: s),
                                   end: CGPoint(x: s, y: 0), options: [])
            let gloss = CGGradient(colorsSpace: cs,
                                   colors: [NSColor(calibratedWhite: 1, alpha: 0.22).cgColor,
                                            clear] as CFArray, locations: [0, 1])!
            ctx.drawLinearGradient(gloss, start: CGPoint(x: 0, y: s),
                                   end: CGPoint(x: 0, y: s * 0.45), options: [])
            // Accent bar along the bottom edge of the tile.
            ctx.setFillColor(aiCGColor(d.accent, alpha: 0.75))
            ctx.fill(CGRect(x: s * 0.16, y: s * 0.065,
                            width: s * 0.68, height: s * 0.022))
            ctx.restoreGState()
            ctx.setStrokeColor(aiCGColor(d.accent, alpha: 0.85))
            ctx.setLineWidth(max(1, s * 0.018))
            ctx.addPath(path); ctx.strokePath()

        case "glass":
            // Almost transparent: a hairline outline and one diagonal sheen.
            let r = rect.insetBy(dx: s * 0.05, dy: s * 0.05)
            let path = CGPath(roundedRect: r, cornerWidth: s * 0.22,
                              cornerHeight: s * 0.22, transform: nil)
            ctx.saveGState(); ctx.addPath(path); ctx.clip()
            ctx.setFillColor(NSColor(calibratedWhite: 1, alpha: 0.055).cgColor)
            ctx.fill(r)
            let gloss = CGGradient(colorsSpace: cs,
                                   colors: [NSColor(calibratedWhite: 1, alpha: 0.30).cgColor,
                                            clear] as CFArray, locations: [0, 1])!
            ctx.drawLinearGradient(gloss, start: CGPoint(x: s * 0.05, y: s),
                                   end: CGPoint(x: s * 0.85, y: s * 0.05), options: [])
            ctx.restoreGState()
            ctx.setStrokeColor(NSColor(calibratedWhite: 1, alpha: 0.48).cgColor)
            ctx.setLineWidth(max(1, s * 0.009))
            ctx.addPath(path); ctx.strokePath()
            ctx.setStrokeColor(aiCGColor(d.accent, alpha: 0.30))
            ctx.setLineWidth(max(1, s * 0.006))
            ctx.addPath(CGPath(roundedRect: r.insetBy(dx: s * 0.035, dy: s * 0.035),
                               cornerWidth: s * 0.19, cornerHeight: s * 0.19,
                               transform: nil)); ctx.strokePath()

        case "ring":
            let inner = CGPath(ellipseIn: rect.insetBy(dx: s * 0.075, dy: s * 0.075),
                               transform: nil)
            ctx.setFillColor(aiCGColor(d.palette[0], alpha: 0.78))
            ctx.addPath(inner); ctx.fillPath()
            ctx.setStrokeColor(aiCGColor(d.accent, alpha: 0.88))
            ctx.setLineWidth(max(1, s * 0.020))
            ctx.addPath(inner); ctx.strokePath()
            ctx.setStrokeColor(aiCGColor(d.accent, alpha: 0.24))
            ctx.setLineWidth(max(1, s * 0.007))
            ctx.strokeEllipse(in: rect.insetBy(dx: s * 0.025, dy: s * 0.025))
            for ang in [CGFloat.pi / 4, 3 * CGFloat.pi / 4,
                        5 * CGFloat.pi / 4, 7 * CGFloat.pi / 4] {
                let rr = s * 0.46
                let p = CGPoint(x: center.x + cos(ang) * rr, y: center.y + sin(ang) * rr)
                ctx.setFillColor(aiCGColor(d.accent, alpha: 0.85))
                ctx.fillEllipse(in: CGRect(x: p.x - s * 0.012, y: p.y - s * 0.012,
                                           width: s * 0.024, height: s * 0.024))
            }

        case "neon":
            // No box at all: a coloured bloom plus four HUD corner brackets.
            let g = CGGradient(colorsSpace: cs,
                               colors: [aiCGColor(d.glow, alpha: 0.72),
                                        aiCGColor(d.glow, alpha: 0)] as CFArray,
                               locations: [0, 1])!
            ctx.drawRadialGradient(g, startCenter: center, startRadius: 0,
                                   endCenter: center, endRadius: s * 0.58, options: [])
            ctx.setStrokeColor(aiCGColor(d.accent, alpha: 0.92))
            ctx.setLineWidth(max(1, s * 0.020))
            ctx.setLineCap(.round)
            let m = s * 0.055, len = s * 0.17
            for (cx, cy, sx, sy) in [(m, s - m, 1, -1), (s - m, s - m, -1, -1),
                                     (m, m, 1, 1), (s - m, m, -1, 1)] {
                ctx.move(to: CGPoint(x: cx + CGFloat(sx) * len, y: cy))
                ctx.addLine(to: CGPoint(x: cx, y: cy))
                ctx.addLine(to: CGPoint(x: cx, y: cy + CGFloat(sy) * len))
                ctx.strokePath()
            }
            ctx.setStrokeColor(aiCGColor(d.accent, alpha: 0.35))
            ctx.setLineWidth(max(1, s * 0.006))
            ctx.strokeEllipse(in: rect.insetBy(dx: s * 0.10, dy: s * 0.10))

        default:
            break
        }
    }

    /// Final icon artwork: themed original logo + an optional style treatment.
    static func iconArtworkPNG(_ src: URL, _ d: AIThemeDesign,
                               side: Int = 256) -> Data? {
        let kind = d.resolvedIconStyle
        let plain = kind == "plain"
        guard let base = styledIconPNG(src, d, side: side,
                                       extractGlyph: !plain) else { return nil }
        if plain { return base }
        guard let img = NSImage(data: base),
              let cg = img.cgImage(forProposedRect: nil, context: nil, hints: nil)
        else { return base }
        let s = CGFloat(side)
        let inset: CGFloat
        switch kind {
        case "ring":  inset = 0.17
        case "neon":  inset = 0.14
        case "badge": inset = 0.13
        default:      inset = 0.11
        }
        return png(CGSize(width: s, height: s)) { ctx, sz in
            iconBackdrop(kind, d, ctx: ctx, s: sz.width)
            ctx.draw(cg, in: CGRect(x: s * inset, y: s * inset,
                                    width: s * (1 - 2 * inset),
                                    height: s * (1 - 2 * inset)))
        }
    }

    /// Wrap PNG reps into a real ICNS container (ic07 128px + ic08 256px).
    /// OpenCanopy reads ICNS natively; embedding PNG chunks needs no subprocess.
    static func icns(png256: Data, png128: Data? = nil) -> Data {
        func be(_ v: UInt32) -> Data {
            var x = v.bigEndian
            return Data(bytes: &x, count: 4)
        }
        var body = Data()
        if let p = png128 {
            body.append(Data("ic07".utf8))
            body.append(be(UInt32(8 + p.count)))
            body.append(p)
        }
        body.append(Data("ic08".utf8))
        body.append(be(UInt32(8 + png256.count)))
        body.append(png256)
        var out = Data("icns".utf8)
        out.append(be(UInt32(8 + body.count)))
        out.append(body)
        return out
    }

    static func styledIcon(_ src: URL, _ d: AIThemeDesign) -> Data? {
        guard let big = iconArtworkPNG(src, d) else { return nil }
        return icns(png256: big, png128: iconArtworkPNG(src, d, side: 128))
    }

    /// The image shown in the generator preview for one icon slot.
    static func iconImage(_ file: String, _ d: AIThemeDesign) -> NSImage? {
        guard let src = iconSource(file) else { return nil }
        if !d.restyleIcons { return NSImage(contentsOf: src) }
        guard let png = iconArtworkPNG(src, d) else { return NSImage(contentsOf: src) }
        return NSImage(data: png)
    }

    /// Small preview of the boot menu: wallpaper + selection box + REAL system icons.
    static func preview(_ d: AIThemeDesign) -> NSImage? {
        guard let data = wallpaper(d), let base = NSImage(data: data) else { return nil }
        let out = NSImage(size: wallpaperSize)
        out.lockFocus()
        base.draw(in: NSRect(origin: .zero, size: wallpaperSize))

        let items = AIThemeRenderer.iconFiles(d)
        let count = items.count
        let rawBox: CGFloat = 178
        let rawGap: CGFloat = count > 10 ? 8 : 20
        let rawTotal = CGFloat(count) * rawBox + CGFloat(max(0, count - 1)) * rawGap
        let scale = min(1, (wallpaperSize.width - 90) / max(1, rawTotal))
        let boxW = rawBox * scale, boxH = rawBox * scale, gap = rawGap * scale
        let total = CGFloat(count) * boxW + CGFloat(max(0, count - 1)) * gap
        var x = (wallpaperSize.width - total) / 2
        let y: CGFloat = (wallpaperSize.height - boxH) / 2

        if let sel = selectionBox(d), let img = NSImage(data: sel) {
            img.draw(in: NSRect(x: x, y: y, width: boxW, height: boxH))
        }
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: max(12, 22 * scale), weight: .medium),
            .foregroundColor: NSColor.white.withAlphaComponent(0.92),
            .paragraphStyle: paragraph
        ]
        for (i, item) in items.enumerated() {
            // A faint tile keeps transparent glyph icons legible on any wallpaper.
            let tile = NSRect(x: x + 16 * scale, y: y + 38 * scale,
                              width: boxW - 32 * scale, height: boxH - 76 * scale)
            let path = NSBezierPath(roundedRect: tile,
                                    xRadius: 18 * scale, yRadius: 18 * scale)
            NSColor.black.withAlphaComponent(i == 0 ? 0.10 : 0.24).setFill()
            path.fill()
            aiNSColor(d.accent, alpha: i == 0 ? 0.30 : 0.14).setStroke()
            path.lineWidth = 1.5; path.stroke()

            if let icon = iconImage(item.file, d) {
                let s = 104 * scale
                icon.draw(in: NSRect(x: x + (boxW - s) / 2, y: y + 52 * scale,
                                    width: s, height: s),
                          from: .zero, operation: .sourceOver, fraction: 1)
            }
            (item.label as NSString).draw(
                in: NSRect(x: x - 8 * scale, y: y + 10 * scale,
                           width: boxW + 16 * scale, height: 30 * scale),
                withAttributes: attrs)
            x += boxW + gap
        }
        out.unlockFocus()
        return out
    }

    static func iconFiles(_ d: AIThemeDesign) -> [(file: String, label: String)] {
        switch d.iconSet {
        case "minimal":
            return [("Apple.icns", "macOS"), ("Windows.icns", "Windows"),
                    ("Linux.icns", "Linux"), ("Tool.icns", "Tools")]
        case "linux":
            return [("Apple.icns", "macOS"), ("Windows.icns", "Windows"),
                    ("Ubuntu.icns", "Ubuntu"), ("Fedora.icns", "Fedora"),
                    ("Debian.icns", "Debian"), ("Arch.icns", "Arch"),
                    ("Manjaro.icns", "Manjaro"), ("Mint.icns", "Linux Mint"),
                    ("openSUSE.icns", "openSUSE"), ("Tool.icns", "Tools")]
        case "full":
            return [("Apple.icns", "macOS"), ("AppleRecv.icns", "Recovery"),
                    ("AppleTM.icns", "Time Machine"), ("Windows.icns", "Windows"),
                    ("Linux.icns", "Linux"), ("Ubuntu.icns", "Ubuntu"),
                    ("Debian.icns", "Debian"), ("Arch.icns", "Arch"),
                    ("Fedora.icns", "Fedora"), ("HardDrive.icns", "Hard Drive"),
                    ("Tool.icns", "Tools"), ("Shell.icns", "UEFI Shell"),
                    ("Restart.icns", "Restart"), ("ShutDown.icns", "Shut Down"),
                    ("ResetNVRAM.icns", "Reset NVRAM")]
        default:
            return [("Apple.icns", "macOS"), ("Windows.icns", "Windows"),
                    ("Linux.icns", "Linux"), ("AppleRecv.icns", "Recovery"),
                    ("HardDrive.icns", "Hard Drive"), ("Tool.icns", "Tools"),
                    ("Restart.icns", "Restart"), ("ShutDown.icns", "Shut Down")]
        }
    }

}

// MARK: - Building a real theme from a design

enum AIThemeBuilder {
    /// Creates a complete, immediately applicable theme. Returns its id.
    @discardableResult
    static func build(_ d: AIThemeDesign) throws -> String {
        // makeTheme() gives us the full skeleton: default UI chrome, a real
        // Font.ttf from the system font, manifest and pickerVariant.
        let theme = try makeTheme(name: d.name, preset: nil, efiMount: nil)
        let dir = theme.dir
        let fm = FileManager.default

        let outputs: [(String, Data?)] = [
            ("Background.png", AIThemeRenderer.wallpaper(d)),
            ("Selected.png", AIThemeRenderer.selectionBox(d)),
            ("Cursor.png", AIThemeRenderer.cursor(d)),
            ("Dot.png", AIThemeRenderer.dot(d)),
            ("BtnFocus.png", AIThemeRenderer.focusBox(d)),
        ]
        for (name, data) in outputs {
            guard let data = data else { throw AppError.message("渲染 \(name) 失败") }
            try data.write(to: dir.appendingPathComponent(name), options: .atomic)
        }

        var labels: [String: String] = [:]
        for item in AIThemeRenderer.iconFiles(d) {
            guard let src = AIThemeRenderer.iconSource(item.file) else { continue }
            let stem = (item.file as NSString).deletingPathExtension
            // OpenCanopy expects ICNS entries; always write one, either the
            // original artwork or a palette-restyled version of that artwork.
            let dst = dir.appendingPathComponent(stem + ".icns")
            if fm.fileExists(atPath: dst.path) { try? fm.removeItem(at: dst) }
            if d.restyleIcons, let data = AIThemeRenderer.styledIcon(src, d) {
                try data.write(to: dst, options: .atomic)
            } else {
                try fm.copyItem(at: src, to: dst)
            }
            // An older build may have left a flat PNG with the same stem.
            let stalePNG = dir.appendingPathComponent(stem + ".png")
            if fm.fileExists(atPath: stalePNG.path) { try? fm.removeItem(at: stalePNG) }
            labels[stem] = item.label
        }

        // Record the design before rebuilding so the label overrides survive.
        var mf = jsonRead(dir.appendingPathComponent("manifest.json")) ?? [:]
        mf["labelOverrides"] = labels
        mf["source"] = d.fromLLM ? "AI 生成 · 大模型设计" : "AI 生成 · 本地智能引擎"
        try jsonWrite(mf, to: dir.appendingPathComponent("manifest.json"))
        try rebuildThemeManifest(dir)

        mf = jsonRead(dir.appendingPathComponent("manifest.json")) ?? [:]
        mf["aiPrompt"] = d.prompt
        mf["aiStyle"] = d.style
        mf["aiEngine"] = d.engine
        mf["source"] = d.fromLLM ? "AI 生成 · 大模型设计" : "AI 生成 · 本地智能引擎"
        try jsonWrite(mf, to: dir.appendingPathComponent("manifest.json"))

        ThemeLibrary.shared.reload()
        return theme.id
    }
}
