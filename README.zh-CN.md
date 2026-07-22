<div align="center">

<img src="Sources/loadcli/Resources/Assets.xcassets/AppIcon.appiconset/icon_256x256.png" width="128" alt="loadcli">

# loadcli

### 你的整个开发环境 —— **一键**就位。

选中一个项目，`loadcli` 就会为你搭好舞台：在指定显示器上新建一个**桌面（Space）**，让**终端**在项目目录里直接运行你的 **CLI**，并在旁边打开**这个项目需要的东西** —— 部署地址的浏览器、一个 Finder 文件夹，或者什么都不开。全部自动摆好位置，你什么都不用动。

[English](README.md) · [Português](README.pt-BR.md) · **中文**

![macOS 14+](https://img.shields.io/badge/macOS-14%2B-000000?style=flat-square&logo=apple&logoColor=white)
![已在 macOS 26.3 测试](https://img.shields.io/badge/%E5%B7%B2%E6%B5%8B%E8%AF%95-macOS%2026.3%20Tahoe-1D9BF0?style=flat-square&logo=apple&logoColor=white)
![Swift 5](https://img.shields.io/badge/Swift-5-F05138?style=flat-square&logo=swift&logoColor=white)
![SwiftUI](https://img.shields.io/badge/UI-SwiftUI-0A84FF?style=flat-square)
![SIP 保持开启](https://img.shields.io/badge/SIP-%E4%BF%9D%E6%8C%81%E5%BC%80%E5%90%AF-3FB950?style=flat-square)
![MIT 许可证](https://img.shields.io/badge/%E8%AE%B8%E5%8F%AF%E8%AF%81-MIT-3FB950?style=flat-square)

</div>

---

## 😮‍💨 它替你省掉的琐事

每次开始动一个项目都是同一套流程：打开终端、`cd` 到正确的目录、启动 CLI、打开部署地址的浏览器、新建一个桌面免得弄乱其他的、拖动并调整窗口大小…… 再乘以**几十个项目**、一天十几次。

`loadcli` 把这套流程变成**点一下卡片**。

```
┌───────────────────── 新桌面 · 所选显示器 ───────────────────────┐
│                                    │                                     │
│     🌐  浏览器（部署地址）           │        ⌨️   终端 + CLI               │
│     🗂️  或 Finder 文件夹            │        cd ~/DEV/my-project          │
│     ▫️  或什么都不开（全屏）         │        $ claude                     │
│                                    │                                     │
└────────────────────────────────────┴─────────────────────────────────────┘
        面板在左侧                          终端在右侧，并获得焦点
```

---

## 🎬 点击后发生了什么

```mermaid
flowchart LR
    A([🖱️ 点击卡片]) --> B[🖥️ 在所选显示器上<br/>新建桌面]
    B --> C[⌨️ 终端 + CLI<br/>进入项目目录]
    B --> D{侧边面板？}
    D -->|浏览器| E[🌐 部署地址]
    D -->|Finder| F[🗂️ 指定文件夹]
    D -->|无| G[▫️ 终端全屏]
    C --> H([↔️ 左右并排<br/>焦点落在终端])
    E --> H
    F --> H
    G --> H
```

每个窗口都会被**验证** —— `loadcli` 会确认它确实落在了新桌面上，如果没有就纠正 —— 并且**焦点最终停在终端上**，你可以立刻开始输入。

---

## ✨ 亮点

- 🖥️ **每个项目一个桌面**，开在你选择的显示器上（有 2 块以上屏幕时提供显示器选择器）。
- ⌨️ **终端 + CLI** 直接进入正确目录 —— 支持 Terminal.app 或 iTerm。
- 🔤 **自动放大字体** —— 聚焦终端后，自动按 ⌘+ 若干次（**1–20，默认 7**），字体不再太小（在“设置”里调整）。
- 🧩 **每个项目可选的侧边面板：**
  - 🌐 **浏览器**打开部署地址（Chrome、Brave、Edge、Arc、Safari）
  - 🗂️ **一个 Finder 文件夹** —— 像浏览器一样并排摆放
  - ▫️ **无** —— 只开终端，**最大化或原生全屏**（独立 Space）
- 📁 **文件夹归类** —— 把卡片分组到文件夹；**每次启动都默认折叠**，方便快速查找；用菜单移动卡片。
- 🤖 **每个项目独立的 CLI** —— Claude Code、Codex 或自定义命令，各自带有独立的**模型和 _effort_**（例如 `opus` + `ultracode`）。
- ↔️ **自动分屏**，比例可调。
- 🧭 **菜单栏启动器** —— 无需打开主窗口即可启动任意项目（按文件夹分组）。
- 🩺 `loadcli --doctor` —— 在每块显示器上对桌面机制做自检。
- 🍎 **100% 原生** —— SwiftUI、专属图标、关于面板、设置。

---

## 🧠 难点：**不关闭 SIP** 也能创建 Space

在现代 macOS 的普通 App 里，通过私有 API（SkyLight）创建桌面（Space）**是行不通的** —— 这正是 *yabai* 之类的工具要你**关闭 SIP** 的原因。`loadcli` 绕开了它。

它**像人一样**创建桌面：通过**辅助功能（Accessibility）API** 驱动 **Mission Control 的“+”按钮**，使用 Dock 的稳定标识符（`mc.spaces.add`），并按 `AXDisplayID` 定位显示器 —— 与 Hammerspoon 的 `hs.spaces` 走的是同一条路。创建结果通过 **space ID 差异比对**（SkyLight，只读）来确认。

要**进入**新桌面（在 macOS 26 上，对缩略图的辅助功能点击会被忽略，而用私有 API 切换又会让画面重叠），它同样做人会做的事：在 Mission Control 里对该桌面缩略图执行一次**真实点击** —— 干净的切换、焦点落在正确的显示器上 —— 并且**始终验证**结果。

> **SIP 保持开启。没有守护进程。没有内核 hack。** 只用辅助功能和 Apple Events —— 就是你给任何自动化 App 的那几项权限。

细节见 [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md)。

---

## 🚀 快速开始

**前置要求：** macOS 14+、**Xcode** 和 **Homebrew**。

> 🧪 **已在 macOS 26.3（Tahoe）上测试。** 部署目标是 macOS 14，但桌面创建流程只在 macOS 26 上验证过 —— 在 14/15 上 Mission Control 的内部实现不同，因此那里的行为未经验证。

```bash
git clone https://github.com/<your-user>/loadcli.git
cd loadcli
make bootstrap     # 安装 xcodegen、xcbeautify、create-dmg
make run           # 生成工程、编译并打开 App
```

首次运行时 macOS 会请求**两项权限**（见下文）。之后点击**添加项目**并指向一个文件夹即可。

<details>
<summary>其他 <code>make</code> 目标</summary>

```bash
make gen           # 从 project.yml 生成 loadcli.xcodeproj
make build         # Debug 构建
make release       # Release 构建
make icon          # 重新生成 App 图标
make sign-notarize # 签名（Developer ID）+ 公证 + 生成 DMG
```
</details>

---

## 🗂️ 配置一个项目

每张卡片都保存着这个项目需要的一切：

| 字段 | 作用 |
|------|-----------|
| **项目文件夹** | 终端 `cd` 进入的目录 |
| **CLI** | Claude Code / Codex / 自定义命令 —— 带**模型**和 **_effort_** |
| **侧边面板** | 浏览器（URL）· Finder（文件夹）· 无 |
| **桌面** | 新建一个桌面，或使用当前桌面 |
| **布局** | 终端在右/左 + 分屏比例 |
| **显示器** | 固定，或“每次询问” |
| **文件夹（分组）** | 把卡片归入一个可折叠的文件夹 |
| **图标与颜色** | 卡片的视觉标识 |

配置保存在 `~/Library/Application Support/loadcli/`（`projects.json`、`folders.json`、`settings.json`）—— 可以纳入版本管理、备份，也可以手动编辑。

---

## 🔐 权限

| 权限 | 用途 | 位置 |
|-----------|---------|------|
| **辅助功能** | 创建桌面并摆放窗口 | 设置 › 隐私与安全性 › **辅助功能** |
| **自动化** | 控制终端和浏览器 | macOS 首次使用时询问 —— 点击*允许* |

> 改了 bundle ID 或用不同的签名重新编译了？macOS 会把它当成一个新 App —— 只需在“辅助功能”里**重新添加**该 App。

---

## 📦 分发

以 **Developer ID 形式分发，不上 Mac App Store** —— 创建桌面和控制窗口需要在商店沙盒**之外**使用辅助功能 / Apple Events。

```bash
# 一次性：保存公证配置（切勿提交任何密钥）
xcrun notarytool store-credentials loadcli-notary \
  --apple-id "you@example.com" --team-id "TEAMID" --password "app-specific-password"

export LOADCLI_SIGN_ID="Developer ID Application: Your Name (TEAMID)"
export LOADCLI_NOTARY_PROFILE="loadcli-notary"
make sign-notarize     # -> dist/loadcli-<版本>.dmg（已签名、已公证、已装订）
```

---

## 🛣️ 路线图

- 🪟 **Windows** —— 原生 .NET/WinUI 3 应用（虚拟桌面 + Win32），共享 `projects.json` 结构：[`docs/WINDOWS_ROADMAP.md`](docs/WINDOWS_ROADMAP.md)。
- 🔁 布局预设、每个项目的全局快捷键、可选的自动登录。

---

## 🏗️ 结构

```
project.yml                 # 工程定义（XcodeGen）
Makefile                    # gen / build / run / release / sign-notarize
scripts/                    # 引导脚本、图标生成、签名/公证
Sources/loadcli/
  Models/                   # Project、ProjectFolder、AppSettings、Store、AppModel
  Services/                 # SpaceManager、AppLauncher、WindowPositioner、DisplayManager、SkyLight、AX
  Views/                    # SwiftUI —— 网格 + 文件夹、编辑器、显示器选择器、设置
  Resources/                # Info.plist、entitlements、Assets（图标）
docs/                       # 架构 + Windows 路线图
```

---

## 🤝 参与贡献

欢迎提交 Issue 和 PR。开 PR 前请先运行 `make build`，并说明*如何测试*。代码沿用项目的“母语”：UI 文案和注释使用**葡萄牙语**。

## 📄 许可证

[MIT](LICENSE) —— 可自由使用、修改和分发，保留版权声明即可。

<div align="center">
<br>

由 **HISAYOSHI, N. KAMEDA** 用 ☕ 与 Mission Control 打造 · [kameda.app](https://kameda.app)

</div>
