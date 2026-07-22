<div align="center">

<img src="Sources/loadcli/Resources/Assets.xcassets/AppIcon.appiconset/icon_256x256.png" width="128" alt="loadcli">

# loadcli

### Your entire dev environment — in **one click**.

Pick a project and `loadcli` sets the stage: a **new desktop** on the right monitor, the **Terminal** already running your **CLI** in the project folder and, beside it, **whatever that project needs** — the browser at the deploy URL, a Finder folder, or nothing. All positioned, without you touching a thing.

**English** · [Português](README.pt-BR.md) · [中文](README.zh-CN.md)

![macOS 14+](https://img.shields.io/badge/macOS-14%2B-000000?style=flat-square&logo=apple&logoColor=white)
![Tested on macOS 26.3](https://img.shields.io/badge/tested%20on-macOS%2026.3%20Tahoe-1D9BF0?style=flat-square&logo=apple&logoColor=white)
![Swift 5](https://img.shields.io/badge/Swift-5-F05138?style=flat-square&logo=swift&logoColor=white)
![SwiftUI](https://img.shields.io/badge/UI-SwiftUI-0A84FF?style=flat-square)
![SIP intact](https://img.shields.io/badge/SIP-intact-3FB950?style=flat-square)
![MIT license](https://img.shields.io/badge/license-MIT-3FB950?style=flat-square)

</div>

---

## 😮‍💨 The chore it kills

Every time you sit down with a project it's the same ritual: open the Terminal, `cd` into the right folder, fire up the CLI, open the browser at the deploy, spin up a fresh desktop so you don't clutter the others, drag and resize windows… times **dozens of projects**, ten times a day.

`loadcli` turns that ritual into **one click on a card**.

```
┌───────────────────── new desktop · chosen monitor ──────────────────────┐
│                                    │                                     │
│     🌐  Browser (deploy URL)        │        ⌨️   Terminal + CLI           │
│     🗂️  or a Finder folder          │        cd ~/DEV/my-project          │
│     ▫️  or nothing (full screen)    │        $ claude                     │
│                                    │                                     │
└────────────────────────────────────┴─────────────────────────────────────┘
        pane on the left                    terminal on the right, focused
```

---

## 🎬 What one click does

<div align="center">

<img src="docs/flow-en.png" width="760" alt="What one click does: click a card → new desktop → Terminal + CLI and a side pane (browser, Finder or none) → tiled side by side, focus on the terminal">

</div>

Every window is **verified** — `loadcli` checks it actually landed on the new desktop and fixes it if it didn't — and the **focus ends on the terminal**, ready for you to type.

---

## ✨ Highlights

- 🖥️ **One desktop per project** on the monitor you pick (monitor picker when you have 2+ screens).
- ⌨️ **Terminal + CLI** already in the right folder — Terminal.app or iTerm.
- 🔤 **Auto font bump** — after focusing the terminal it presses ⌘+ a set number of times (**1–20, default 7**) so the text isn't tiny (set it in Settings).
- 🧩 **Per-project side pane:**
  - 🌐 **Browser** at the deploy URL (Chrome, Brave, Edge, Arc, Safari)
  - 🗂️ **A Finder folder** — tiled just like the browser
  - ▫️ **Nothing** — terminal only, **maximized or native full screen** (its own Space)
- 📁 **Folders** — group cards into folders that **start collapsed on every launch** for quick scanning; move cards with a menu.
- 🤖 **Per-project CLI** — Claude Code, Codex or a custom command, each with its own **model and _effort_** (e.g. `opus` + `ultracode`).
- ↔️ **Automatic split** with adjustable ratio.
- 🧭 **Menu bar launcher** — start any project (grouped by folder) without opening the main window.
- 🩺 `loadcli --doctor` — self-test of the desktop mechanism on every monitor.
- 🍎 **100% native** — SwiftUI, custom icon, About panel, Settings.

---

## 🧠 The hard part: creating Spaces **without disabling SIP**

Creating a desktop (Space) through a private API (SkyLight) **doesn't work** in a normal modern-macOS app — which is why tools like *yabai* ask you to **turn off SIP**. `loadcli` sidesteps that.

It creates the desktop **the way a human would**: it drives the **Mission Control “+” button** through the **Accessibility API**, using the Dock's stable identifiers (`mc.spaces.add`) and targeting the monitor by its `AXDisplayID` — the same path Hammerspoon's `hs.spaces` uses. Creation is confirmed by a **space-ID diff** (SkyLight, read-only).

To **enter** the new desktop (the Accessibility click on the thumbnail is ignored on macOS 26, and switching via the private API leaves the screens overlapping), it again does what a person would: a **real click** on the desktop's thumbnail in Mission Control — a clean transition, focus on the right monitor — **always verifying** the result.

> **SIP stays intact. No daemon. No kernel hack.** Just Accessibility and Apple Events — the same permissions you grant any automation app.

Details in [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md).

---

## 🚀 Getting started

**Prerequisites:** macOS 14+, **Xcode** and **Homebrew**.

> 🧪 **Tested on macOS 26.3 (Tahoe).** The deployment target is macOS 14, but the desktop-creation flow has only been validated on macOS 26 — on 14/15 the Mission Control internals differ, so behavior there is unverified.

```bash
git clone https://github.com/<your-user>/loadcli.git
cd loadcli
make bootstrap     # installs xcodegen, xcbeautify, create-dmg
make run           # generates the project, builds and opens the app
```

On first run macOS asks for **two permissions** (see below). Then just click **Add Project** and point it at a folder.

<details>
<summary>Other <code>make</code> targets</summary>

```bash
make gen           # generates loadcli.xcodeproj from project.yml
make build         # Debug build
make release       # Release build
make icon          # regenerates the app icon
make sign-notarize # sign (Developer ID) + notarize + build the DMG
```
</details>

---

## 🗂️ Configuring a project

Each card holds everything that project needs:

| Field | What it does |
|------|-----------|
| **Project folder** | where the Terminal `cd`s |
| **CLI** | Claude Code / Codex / custom command — with **model** and **_effort_** |
| **Side pane** | Browser (URL) · Finder (folder) · None |
| **Desktop** | create a new desktop or use the current one |
| **Layout** | terminal on the right/left + split ratio |
| **Monitor** | fixed or “ask every time” |
| **Folder (group)** | organizes the card into a collapsible folder |
| **Icon & color** | the card's visual identity |

Config lives in `~/Library/Application Support/loadcli/` (`projects.json`, `folders.json`, `settings.json`) — version it, back it up, hand-edit if you like.

---

## 🔐 Permissions

| Permission | For | Where |
|-----------|---------|------|
| **Accessibility** | create desktops and position windows | Settings › Privacy & Security › **Accessibility** |
| **Automation** | control Terminal and the browser | macOS asks on first use — click *Allow* |

> Changed the bundle ID or rebuilt with a different signature? macOS treats it as a new app — just **re-add** the app under Accessibility.

---

## 📦 Distribution

Shipped as **Developer ID, outside the Mac App Store** — creating desktops and controlling windows need Accessibility/Apple Events **outside** the store sandbox.

```bash
# Once: store the notarization profile (never commit secrets)
xcrun notarytool store-credentials loadcli-notary \
  --apple-id "you@example.com" --team-id "TEAMID" --password "app-specific-password"

export LOADCLI_SIGN_ID="Developer ID Application: Your Name (TEAMID)"
export LOADCLI_NOTARY_PROFILE="loadcli-notary"
make sign-notarize     # -> dist/loadcli-<version>.dmg (signed, notarized, stapled)
```

---

## 🛣️ Roadmap

- 🪟 **Windows** — native .NET/WinUI 3 app (Virtual Desktops + Win32), sharing the `projects.json` schema: [`docs/WINDOWS_ROADMAP.md`](docs/WINDOWS_ROADMAP.md).
- 🔁 Layout profiles, per-project global shortcuts, optional auto-login.

---

## 🏗️ Layout

```
project.yml                 # project definition (XcodeGen)
Makefile                    # gen / build / run / release / sign-notarize
scripts/                    # bootstrap, icon generator, signing/notarization
Sources/loadcli/
  Models/                   # Project, ProjectFolder, AppSettings, Store, AppModel
  Services/                 # SpaceManager, AppLauncher, WindowPositioner, DisplayManager, SkyLight, AX
  Views/                    # SwiftUI — grid + folders, editors, monitor picker, settings
  Resources/                # Info.plist, entitlements, Assets (icon)
docs/                       # architecture + Windows roadmap
```

---

## 🤝 Contributing

Issues and PRs welcome. Run `make build` before opening a PR and describe *how to test*. The codebase speaks its house language: **Portuguese** in UI strings and comments.

## 📄 License

[MIT](LICENSE) — use, modify and distribute freely, keeping the copyright notice.

<div align="center">
<br>

Made with ☕ and Mission Control by **HISAYOSHI, N. KAMEDA** · [kameda.app](https://kameda.app)

</div>
