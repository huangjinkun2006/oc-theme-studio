# OC Theme Studio

原生 macOS 的 OpenCore 主题编辑器，使用 Swift / AppKit 编写，无第三方依赖、无 Xcode 工程文件，直接用 `swiftc` 编译。

## 功能

- **主题编辑**：可视化编辑 OpenCore 启动主题的图标、布局、背景与配色
- **EFI 识别**：读取本机或已挂载分区的 EFI，识别现有引导项与主题
- **图标工具**：ICNS ↔ PNG 转换与批量生成启动图标
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

- **2.3.0**：新增「EFI 配置包」分类。上传时从主窗口所选 EFI 分区生成脱敏配置包（只含 Resources 与 PickerMode / PickerVariant，移除序列号 / MLB / ROM / NVRAM / Kexts / Drivers）；下载后按所选目标分区安装，自动备份并合并 Picker 设置，不覆盖目标机器标识。同时修复 EFI 资源树复制时的目录扁平化问题，上传前加入 200 MB 本地预检。
- **2.2.0**：主题商店新增「完整主题 / 图标区 / 背景区 / 字体区」分类，支持按分类筛选、卡片与详情显示类型、上传时选择资源类型，并同步后端 `/api/categories` 与 `?category=` 过滤。
- **2.1.1**：修复主题商店窗口因 `windowDidLoad()` 未触发导致列表为空、上传/刷新按钮无响应；改为初始化时显式配置，并持有上传面板控制器。
- **2.1**：默认商店地址切换为 HTTPS 域名，收紧 ATS。
