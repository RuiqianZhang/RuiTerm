<div align="center">
  <h3>RuiTerm</h3>
  <p>
    <a href="#english">English</a> | <a href="#简体中文">简体中文</a>
  </p>
</div>

---

<h2 id="english">English</h2>

**RuiTerm** is a modern, native SSH client and terminal emulator designed exclusively for macOS. It was built from the ground up to provide developers with an aesthetically stunning and highly intuitive terminal experience.

### ✨ Key Features

- **🚀 Native Experience**: Built entirely with Swift and SwiftUI, deeply integrating with macOS native features to deliver buttery smooth UI and extremely low resource footprint.
- **🪟 Advanced Split Panes**: Supports infinitely nested horizontal and vertical splits. Say goodbye to tiny, hard-to-click divider lines—**simply drag the title bar of any pane to seamlessly resize the split layout**.
- **⌨️ iTerm2-Style Shortcuts**: Features a highly customizable shortcut system with out-of-the-box support for classic iTerm2 workflows, such as `Cmd+D` (Split Right), `Cmd+Shift+D` (Split Down), and `Cmd+W` (Close Pane/Tab).
- **📁 Built-in SFTP Browser**: Manage remote server files directly from the sidebar without third-party tools. Supports upload, download, drag-and-drop, and real-time remote editing.
- **☁️ Cloud Sync**: Natively supports syncing your hosts and groups configurations across multiple Macs via local directories (iCloud Drive / Dropbox) or Amazon S3 compatible APIs.
- **🎨 Deep Customization**: Includes rich theme toggles, Glassmorphism effects, and highly refined visual aesthetics that make working in the terminal a joy.
- **🌍 Multi-Language Support**: Fully localized in both English and Simplified Chinese with instant toggling.

### 📦 Building and Packaging

The repository includes a one-click script to easily build the `.dmg` installer on macOS.

1. Clone the repository:
   ```bash
   git clone https://github.com/RuiqianZhang/RuiTerm.git
   cd RuiTerm
   ```
2. Build and package the DMG file:
   ```bash
   chmod +x scripts/build-app.sh scripts/build-dmg.sh
   ./scripts/build-dmg.sh
   ```
3. A `RuiTerm.dmg` file will be generated in the root directory. Double click it to install!

### 🛠 Tech Stack

- Language: **Swift 5**
- Interface: **SwiftUI** & AppKit
- Core Terminal Engine: **SwiftTerm**

### 📝 License

RuiTerm. All rights reserved.

---

<h2 id="简体中文">简体中文</h2>

**RuiTerm** 是一款专为 macOS 设计的现代化原生 SSH 客户端与终端模拟器。它的设计初衷是为开发者提供一个拥有极致美感、并且操作符合直觉的终端体验。

### ✨ 核心特性

- **🚀 原生体验**：使用 Swift 和 SwiftUI 构建，深度集成 macOS 原生特性，享受丝滑的 UI 与极低的资源占用。
- **🪟 强大的分屏系统**：支持无限层级的垂直与水平分屏。无需寻找极细的分割线，**直接拖拽面板的标题栏即可丝滑调整分屏大小**。
- **⌨️ iTerm2 风格的快捷键**：内置灵活的快捷键系统，支持完全自定义，并原生兼容 `Cmd+D`（向右分屏）、`Cmd+Shift+D`（向下分屏）、`Cmd+W`（关闭面板/标签页）等经典的 iTerm2 键盘流。
- **📁 内置 SFTP 浏览器**：无需借助第三方工具，在终端侧边即可直接管理服务器文件，支持上传、下载、拖拽与实时编辑。
- **☁️ 云端同步**：完美支持本地目录（配合 iCloud Drive / Dropbox）及 S3 协议的云端存储，将您的服务器列表和分组配置在多台 Mac 之间实时无缝同步。
- **🎨 高级终端自定义**：支持丰富的主题切换、毛玻璃（Glassmorphism）特效定制，带来令人惊艳的视觉享受。
- **🌍 多语言支持**：原生支持中文与英文，并在设置中提供了一键切换功能。

### 📦 安装与打包

本项目自带一键打包脚本，可以在 macOS 上快速构建安装包。

1. 克隆代码仓库：
   ```bash
   git clone https://github.com/RuiqianZhang/RuiTerm.git
   cd RuiTerm
   ```
2. 构建并打包生成 DMG 安装文件：
   ```bash
   chmod +x scripts/build-app.sh scripts/build-dmg.sh
   ./scripts/build-dmg.sh
   ```
3. 在项目根目录下，您将看到生成好的 `RuiTerm.dmg`，双击即可安装使用。

### 🛠 技术栈

- 语言: **Swift 5**
- 界面: **SwiftUI** & AppKit
- 核心终端引擎: **SwiftTerm**

### 📝 许可证

RuiTerm 保留所有权利。
