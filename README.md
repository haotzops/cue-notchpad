# Cue Notchpad

<p align="center">
  <img src="Supporting/cue-logo.png" alt="Cue Notchpad Logo" width="220">
</p>

Cue Notchpad 只做一件事，替代你的 `code --wait`/`cot --wait` 作为外挂 prompt 编辑器。安装后，你只需要在各类 agent 工具的配置文件中，将 editor 配置为 `cue --wait`。在会话中，使用 `Control-G` 即可弹出 Cue 编辑器。

## 安装

### Homebrew

```bash
brew install --cask haotzops/tap/cue-notchpad
```

该命令会同时安装 `Cue Notchpad.app` 和 `cue` 命令。项目使用 ad-hoc 签名，未经过 Apple 公证；Homebrew 安装完成后会自动移除该 app 的 quarantine 属性，从而避免首次启动时被 Gatekeeper 阻止。请仅在确认 Tap 和下载来源可信后安装。

升级或卸载：

```bash
brew upgrade --cask cue-notchpad
brew uninstall --cask cue-notchpad
```

### GitHub Release

1. 从 [GitHub Releases](https://github.com/haotzops/cue-notchpad/releases) 下载 `Cue-Notchpad-<版本>-macOS-universal.zip` 和 `SHA256SUMS`。
2. 在两个文件所在的目录校验下载内容：

   ```bash
   shasum -a 256 -c SHA256SUMS
   ```

3. 解压 ZIP，将 `Cue Notchpad.app` 移到 `~/Applications`。
4. 创建 `cue` 启动脚本，并确保 `~/.local/bin` 已加入 `PATH`：

   ```bash
   mkdir -p "$HOME/.local/bin"
   cat > "$HOME/.local/bin/cue" <<'EOF'
   #!/bin/sh
   exec "$HOME/Applications/Cue Notchpad.app/Contents/MacOS/cue" "$@"
   EOF
   chmod +x "$HOME/.local/bin/cue"
   export PATH="$HOME/.local/bin:$PATH"
   ```

打开 Cue 时提示「已损坏，无法打开」或者 未知开发者警告 ，是因为项目使用 ad-hoc 签名，未经过 Apple 开发者签名。macOS 若阻止首次启动，可前往“系统设置 → 隐私与安全性”选择“仍要打开”；也可以在命令行移除该 app 的 quarantine 属性：

```bash
xattr -dr com.apple.quarantine "$HOME/Applications/Cue Notchpad.app"
```

## 使用

```bash
cue --wait
```

- `⌘ Return`：完成，关闭面板并把文本写到 stdout（不会额外添加换行）
- `Esc`：取消当前 wait，退出码为 `130`，stdout 为空；有其他并发会话时 Cue 会隐藏，待用全局显示快捷键恢复
- `⌘ H`：暂时隐藏窗口但继续等待；不会提交、取消或修改原文件
- `⌥⌘ C`：在任意应用中显示或隐藏 Cue（可在设置中修改）
- `⌥⌘ ←` / `⌥⌘ →`：切换上一个/下一个并发会话（可在设置中修改）
- 在“设置 → 编辑器 → 编辑器字体”中可使用 macOS 原生字体面板选择字体和字号；安装 Nerd Font 后可选择相应字体显示其私有区图标。
- 在“设置 → 编辑器”中可开启“中英文之间自动加空格”；开启后仅在提交 prompt 时处理相邻的中文与英文/数字，不影响编辑过程或取消操作。
- `⌘ ,`：打开设置窗口
- 普通 `Return`：在 prompt 中换行

提交后会像 CotEditor 的 `cot --wait` 一样，把焦点还给调用命令时位于前台的终端应用。


## 从源码构建

要求 macOS 13+、Swift 6 和 Xcode Command Line Tools。首次使用可先安装命令行工具：

```bash
xcode-select --install
```

获取源码并构建：

```bash
git clone https://github.com/haotzops/cue-notchpad.git
cd cue-notchpad
make test
make app
open "build/Cue Notchpad.app"
```

`make app` 默认构建当前 Mac 的原生架构，app bundle 会生成到 `build/Cue Notchpad.app`。
构建脚本支持以下环境变量：

- `RELEASE_VERSION`：写入 `CFBundleShortVersionString`，默认读取 `Supporting/Info.plist`。
- `BUILD_NUMBER`：写入 `CFBundleVersion`，必须是正整数，默认读取 `Supporting/Info.plist`。
- `ARCHS`：用空格分隔的目标架构；不设置时只构建当前架构。
- `CONFIGURATION`：`debug` 或 `release`，默认 `release`。
- `OUTPUT_DIR`：app bundle 输出目录，默认 `build`。

例如，构建版本号为 `0.1.0`、构建号为 `7` 的 Universal app：

```bash
RELEASE_VERSION=0.1.0 BUILD_NUMBER=7 ARCHS="arm64 x86_64" make app
```

准备可上传的 ZIP 和 SHA-256 文件，但不进行上传或发布：

```bash
RELEASE_VERSION=0.1.0 BUILD_NUMBER=1 make release
```

产物位于 `dist/`。完整发布检查清单见 [`Docs/releasing.md`](Docs/releasing.md)。

## 从源码安装

默认安装到当前用户目录，不需要 sudo：

```bash
make install
export PATH="$HOME/.local/bin:$PATH"
```

这会创建：

- `~/Applications/Cue Notchpad.app`
- `~/.local/bin/cue`

也可以安装到系统目录：

```bash
APP_DIR=/Applications BIN_DIR=/usr/local/bin make install
```

如果对应目录不可写，请在命令前使用 `sudo`，并显式设置 `HOME` 或直接指定 `APP_DIR` / `BIN_DIR`。

卸载默认的源码安装（只会删除 `~/Applications/Cue Notchpad.app` 和由 `make install` 创建的 `~/.local/bin/cue`，不会影响 Homebrew）：

```bash
make uninstall
```

使用自定义安装目录时，用相同的变量卸载：

```bash
APP_DIR=/Applications BIN_DIR=/usr/local/bin make uninstall
```

## 在源码版与 Homebrew 版之间切换

默认源码安装与 Homebrew 可以共存：前者使用 `~/Applications` 和 `~/.local/bin`，后者使用 `/Applications` 和 `/opt/homebrew/bin`。先退出正在运行的 Cue Host（可关闭 app，或运行 `pkill -x cue-host`），再用 `type -a cue` 查看 shell 会调用的命令。

临时优先使用源码版：

```bash
PATH="$HOME/.local/bin:$PATH" cue --wait
```

临时优先使用 Homebrew 版：

```bash
PATH="/opt/homebrew/bin:$PATH" cue --wait
```

需要永久切换时，调整 shell 配置文件中这两个目录加入 `PATH` 的先后顺序；如果只使用 Homebrew，可执行 `make uninstall` 后保留 `brew install --cask haotzops/tap/cue-notchpad` 的安装结果。

## 许可证与致谢

Cue Notchpad 使用 [GNU GPL v3.0 only](LICENSE) 发布。
界面实现参考 [boring.notch](https://github.com/TheBoredTeam/boring.notch)；
`--wait` 及焦点恢复行为参考 [CotEditor](https://github.com/coteditor/CotEditor)。

应用内置的 OpenAI `cl100k_base` 词表使用 MIT License。详细第三方声明见 [`Supporting/ThirdPartyNotices.txt`](Supporting/ThirdPartyNotices.txt)。
