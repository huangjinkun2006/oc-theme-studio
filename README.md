# OC Theme Studio

原生 macOS 的 OpenCore 主题编辑器，使用 Swift / AppKit 编写，无第三方依赖、无 Xcode 工程文件，直接用 `swiftc` 编译。

## 功能

- **主题编辑**：可视化编辑 OpenCore 启动主题的图标、布局、背景与配色
- **EFI 识别**：读取本机或已挂载分区的 EFI，识别现有引导项与主题
- **图标工具**：ICNS ↔ PNG 转换与批量生成启动图标
- **启动模拟**：主板/固件 Logo → OpenCore Picker（显示当前所选主题）→ 选择 macOS 回车后模拟 `-v` 跑码
- **主题商店**：在线浏览 / 下载 / 上传主题；服务器不可达时自动回退到内置离线示例

## 构建

需要 macOS 11.0+ 和 Xcode Command Line Tools（提供 `swiftc`、`codesign`、`hdiutil`）。

```bash
bash build.sh            # 生成 ../OC Theme Studio (Swift).app
bash dmg/make_dmg.sh     # 生成 ../OC Theme Studio.dmg
```

`make_dmg.sh` 会把 dmgbuild 等 Python 依赖装进 `.cache/dmg`（不污染系统），自动生成带箭头的安装背景和 Applications 快捷方式。应用以 ad-hoc 签名（`codesign --sign -`）打包。

## 安装

从 [Releases](https://github.com/huangjinkun2006/oc-theme-studio/releases) 下载 DMG，把 `OC Theme Studio.app` 拖进 Applications。若首次打开被 Gatekeeper 拦截，可右键 → 打开，或执行：

```bash
xattr -cr "/Applications/OC Theme Studio.app"
```

如需彻底免提示，需要 Apple Developer ID 签名并公证。

## 主题商店

默认服务器地址 `https://mctop.top`（见 `Sources/StoreClient.swift`）。可在商店窗口顶部的「服务器地址」栏覆盖，配置保存在 `~/Library/Application Support/OCThemeStudio/state.json`。

`Info.plist` 中 ATS 只允许本地网络 HTTP，公网连接强制 HTTPS；旧版本存的明文 IP 会在启动时自动升级为 HTTPS 域名。

后端是独立仓库：[huangjinkun2006/oc-theme-store](https://github.com/huangjinkun2006/oc-theme-store)（FastAPI + 网页商店 + 一键部署脚本）。

## 目录结构

| 路径 | 说明 |
|---|---|
| `Sources/` | 全部 Swift 源码 |
| `Info.plist` | App 配置与 ATS 策略 |
| `Presets/` | 内置图标池与预设定义 |
| `Store/` | 离线主题目录 |
| `dmg/` | DMG 打包脚本、布局与背景生成 |
| `build.sh` | 编译并组装 `.app` |

## 版本

- **2.1.1**：修复主题商店窗口因 `windowDidLoad()` 未触发导致列表为空、上传/刷新按钮无响应；改为初始化时显式配置，并持有上传面板控制器。
- **2.1**：默认商店地址切换为 HTTPS 域名，收紧 ATS。
