# OC Theme Studio

原生 macOS 的 OpenCore 主题编辑器，使用 Swift / AppKit 编写，无第三方依赖、无 Xcode 工程文件，直接用 `swiftc` 编译。

## 功能

- **主题编辑**：可视化编辑 OpenCore 启动主题的图标、布局、背景与配色
- **EFI 识别**：读取本机或已挂载分区的 EFI，识别现有引导项与主题
- **图标工具**：ICNS ↔ PNG 转换与批量生成启动图标
- **素材库**：内置壁纸 / 界面元素 / 启动项图标可浏览预览，也能导入自己的图片；编辑主题时直接从中挑选背景和图标
- **启动模拟**：主板/固件 Logo → OpenCore Picker（显示当前所选主题）→ 选择 macOS 回车后模拟 `-v` 跑码
- **主题商店**：按「完整主题 / 图标区 / 背景区 / 字体区」分类浏览、筛选、下载与上传；服务器不可达时自动回退到内置离线示例

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

商店支持 5 个分类：**完整主题（默认）、图标区、背景区、字体区、EFI 配置包**。窗口顶部「分类」下拉会读取服务端 `/api/categories` 显示各分类数量，上传面板可选择资源类型；列表通过 `GET /api/themes?category=...` 过滤。分类只影响商店展示与筛选，不改变 `.zip` 校验规则，纯字体包等资源可下载后手动取用。

### EFI 配置包（按分区上传 / 安装）

上传什么文件由**主窗口当前所选的 EFI 分区**决定：在商店上传面板把类型选为「EFI 配置包」后，按钮变为「从当前 EFI 分区生成…」，不再弹出文件选择框。App 直接读取该分区 `EFI/OC/Resources` 与 `config.plist`，生成可公开分享的脱敏包：

- 包内含 `oc-efi-manifest.json`、`EFI/OC/Resources`、`EFI/OC/config.plist` 的**最小版本**（只保留 `Misc → Boot → PickerMode / PickerVariant`）。
- 明确排除 `PlatformInfo`（序列号 / MLB / ROM / UUID）、`NVRAM`、`ACPI`、`Kernel`/Kexts、`Drivers`、`Tools`、`UEFI`、`DeviceProperties`、`Booter`。
- 网页手动上传的 EFI 包也必须带 `oc-efi-manifest.json`，否则 App 会拒绝安装。

安装同样按**主窗口当前所选的 EFI 分区**：EFI 分类的详情按钮是「下载并安装…」，下载后不进主题库，而是弹出确认框写入所选分区。安装只覆盖 `Resources/Image/<PickerVariant>` 与 `Font / Label / Sound`，并把 `PickerMode / PickerVariant` 合并进目标机自己的 `config.plist`，**不会覆盖目标机器的序列号、NVRAM、Kexts、Drivers**。写入前自动备份 `Resources` 与 `config.plist`，可在「备份」中一键还原。

> 使用前请先在右侧「EFI 分区」列表选择并挂载目标分区；未挂载时 App 会提示先挂载。写入需要管理员授权。

`Info.plist` 中 ATS 只允许本地网络 HTTP，公网连接强制 HTTPS；旧版本存的明文 IP 会在启动时自动升级为 HTTPS 域名。

后端是独立仓库：[huangjinkun2006/oc-theme-store](https://github.com/huangjinkun2006/oc-theme-store)（FastAPI + 网页商店 + 一键部署脚本）。

## 素材库（图标 / 壁纸）

入口：状态栏「🎨 素材库」、菜单「工具 → 图标 / 壁纸素材库…」（⌘K）。主题编辑器左栏另有「🎨 从素材库添加…」和「🎨 从素材库替换…」，可视化设计器顶栏有「🎨 素材库选图」。

- **内置素材**：`Presets/wallpapers`（6 张 1600×900 深色渐变壁纸）、`Presets/icons`（3 张壁纸 + 启动项图标与界面元素）、`Presets/defaults`（默认 UI 图），共 57 项素材、其中 10 张壁纸。随 App 打包，只读。分类判定与 `buildManifest()` 共用同一套关键词，素材库里显示为「界面元素」的文件写入主题后确实落在 `uiAssets` 桶。
- **自定义素材**：窗口里「＋ 导入素材…」可多选图片或整个文件夹，副本存到 `~/Library/Application Support/OCThemeStudio/Assets`，按子文件夹名（含「壁纸 / 背景 / wallpaper / ui / 界面」等）辅助分类；「打开素材文件夹」直达该目录，「移出素材库」只删除副本，不影响原文件。
- **分类与搜索**：全部 / 壁纸 / 界面元素 / 图标 / 自定义，加名称搜索；网格缩略图、大图预览、尺寸与文件大小。
- **写入主题**：选好素材后按用途自动命名——背景写 `Background.png`、选中框写 `Selected.png`、光标写 `Cursor.png`，启动项图标保留原文件名（.icns / .png）。若主题里已有同用途或同名资源会**直接替换**而不是生成 `Background 2.png` 这类重复文件；格式不一致时自动转成真实 PNG，避免出现扩展名与内容不符的文件。写入后调用 `rebuildThemeManifest()` 更新安装清单，应用主题时照常写入 EFI。

## 目录结构

| 路径 | 说明 |
|---|---|
| `Sources/` | 全部 Swift 源码 |
| `Info.plist` | App 配置与 ATS 策略 |
| `Presets/` | 内置图标池、壁纸与预设定义 |
| `Store/` | 离线主题目录 |
| `dmg/` | DMG 打包脚本、布局与背景生成 |
| `build.sh` | 编译并组装 `.app` |

## 版本

- **2.3.3**：新增「图标 / 壁纸素材库」。内置 10 张壁纸（含 6 张新增 1600×900 深色渐变）+ 全部启动项图标 / 界面元素，支持导入自定义图片、分类筛选、搜索、缩略图预览；主题编辑器与可视化设计器都能直接从素材库挑背景和图标，按用途自动命名写入主题并重建安装清单，同用途资源自动替换而非生成重复文件。

- **2.3.2**：让「＋ 新建」在**不挂载 EFI** 时也能建出完整主题。新增兜底：无 EFI 字体时自动从本机系统字体（Geneva / NewYork / SF Compact / Arial / Verdana，按序回退）复制一份 `Font.ttf` 到新主题，保证 OpenCanopy 能加载出图形选取器（含选取框）而非退回文本菜单；挂载 EFI 时仍以 EFI 自带字体为准。内置默认 UI 图（背景/选取框/光标/圆点/焦点框）始终直接生成，不依赖 EFI。字体仅从用户本机复制，不打包进 App / DMG，避免再分发受版权保护的字体。
- **2.3.1**：修复「新建主题」文件夹不完整导致开机退回文本选取器的问题。现在「＋ 新建」会从**右侧当前挂载的 EFI 分区**复制其现有的选取框（Selected）、字体（Resources/Font）与标签（Resources/Label）以及当前变体的图标/背景，使新主题一建好就是完整可加载的 OpenCore 主题；未挂载 EFI 时回退到内置默认图。同时 `apply` 在主题没有任何图片资源时不再强行把 `PickerMode` 设为 External（否则 OpenCanopy 加载失败退回文本），并提示缺少字体的情况。
- **2.3.0**：新增「EFI 配置包」分类。上传时从主窗口所选 EFI 分区生成脱敏配置包（只含 Resources 与 PickerMode / PickerVariant，移除序列号 / MLB / ROM / NVRAM / Kexts / Drivers）；下载后按所选目标分区安装，自动备份并合并 Picker 设置，不覆盖目标机器标识。同时修复 EFI 资源树复制时的目录扁平化问题，上传前加入 200 MB 本地预检。
- **2.2.0**：主题商店新增「完整主题 / 图标区 / 背景区 / 字体区」分类，支持按分类筛选、卡片与详情显示类型、上传时选择资源类型，并同步后端 `/api/categories` 与 `?category=` 过滤。
- **2.1.1**：修复主题商店窗口因 `windowDidLoad()` 未触发导致列表为空、上传/刷新按钮无响应；改为初始化时显式配置，并持有上传面板控制器。
- **2.1**：默认商店地址切换为 HTTPS 域名，收紧 ATS。
