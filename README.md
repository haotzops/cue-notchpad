# Cue Notchpad

<p align="center">
  <img src="Supporting/logo.svg" alt="Cue Notchpad Logo" width="220">
</p>

Cue Notchpad 只做一件事，替代你的 `code --wait`/`cot --wait` 作为外挂 prompt 编辑器。安装后，你只需要在各类 agent 工具的配置文件中，将 editor 配置为 `cue --wait`。在会话中，使用 `Control-G` 即可弹出 Cue 编辑器。

## 安装

### Homebrew

由于这是第三方 Tap，Homebrew 需要显式信任 Cask。下面的命令只信任 Cue Notchpad，不会信任整个 Tap：

```bash
brew tap haotzops/tap
brew trust --cask haotzops/tap/cue-notchpad
brew install --cask cue-notchpad
```

该命令会同时安装 `Cue Notchpad.app` 和 `cue` 命令。

升级或卸载：

```bash
brew upgrade --cask cue-notchpad
brew uninstall --cask cue-notchpad
```

如果 Cue 正在等待编辑会话，升级会主动中止，以避免替换正在运行的 `cue-host`；请先提交或取消编辑，再重新执行升级。

### GitHub Release

1. 从 [GitHub Releases](https://github.com/haotzops/cue-notchpad/releases) 下载 `Cue-Notchpad-<版本>-macOS-arm64.zip`、`SHA256SUMS` 和 `PROVENANCE.json`。
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

## 报告正式版问题

请使用 [正式版问题报告](https://github.com/haotzops/cue-notchpad/issues/new?template=bug-report.yml)，附上版本、build number 和 `BuildInfo.json` 或 `PROVENANCE.json`。这些 metadata 不包含用户设置、API Key、prompt 或 Pi message。开发者会先用相同正式资产复现：

```bash
make install-release VERSION=x.y.z
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
- 在“设置 → 供应商凭据”中可搜索并按折叠分类管理全部 Provider 的凭据（环境变量 / 本地保存 / 无需 Key），点选行即切换执行 AI 重写的 Provider。各 Provider 的凭据独立保存在 `~/Library/Application Support/Cue Notchpad/config.json`（权限 `0600`），也可由对应环境变量提供。Cue 只在用户按重写快捷键时发送当前 prompt，不提供 FIM 或行间补全。
- 重写提示词支持 `${message}`：当当前 Cue 窗口由 Pi 打开时，可在提示词任意位置插入 active branch 上最近一个 assistant turn 的文本。
- `⌘ ,`：打开设置窗口
- 在“设置 → AI”中可显式安装 Cue 管理的全局 Pi integration。安装位置为 `~/.pi/agent/extensions/pi-cue-context/`（或 `PI_CODING_AGENT_DIR` 指定的 agent 目录）；Cue 不修改 Pi 的 `settings.json`。
- 若要让 Pi 的 `Control-G` 使用 Cue，请自行在 Pi 的全局 `settings.json` 中设置 `"externalEditor": "cue --wait"`。卸载 integration 不会修改该设置。
- 普通 `Return`：在 prompt 中换行

提交后会像 CotEditor 的 `cot --wait` 一样，把焦点还给调用命令时位于前台的终端应用。

## AI 重写与 Pi `${message}`

Cue 的 AI 能力只保留用户显式触发的文本重写。当前编辑器文本作为 user input 发送，用户配置的重写提示词作为 system instruction 发送；请求可能产生所选 Provider 的账户费用。

Cue 只保留三个内置配置：DeepSeek、OpenAI 和 Anthropic。其他云服务、网关和本地推理服务统一通过“自定义 API”配置接入；自定义配置支持 OpenAI Chat Completions、OpenAI Responses 和 Anthropic Messages 三种协议，可以创建多个配置。

自定义配置包含名称、协议、Base URL、API Key 和 Model ID。Cue 会按协议与规范化 Base URL 匹配内置 endpoint catalog；匹配成功时自动提供模型查询和可用的余额检测接口。未匹配的服务需要手动填写模型接口地址、余额接口地址以及余额 JSON Pointer。Ollama、LM Studio、vLLM 等本地服务通常选择 OpenAI Chat Completions。

内置和自定义配置的 API Key 按 profile 独立保存在 `~/Library/Application Support/Cue Notchpad/config.json`。Cue 不从环境变量读取供应商 API Key；未保存本地凭据的内置配置需要在设置中手动填写。

Pi integration 安装后，请自行配置：

```json
{
  "externalEditor": "cue --wait"
}
```

Pi 用 `Control-G` 启动 Cue 时，integration 通过 session-scoped 私有 Unix socket 与随机 capability，向该次 Cue 编辑事务提供 active branch 上最近一个 assistant turn 的文本。可在重写提示词任意位置使用：

```text
${message}
```

例如：

```text
参考上一轮 agent 回复：
${message}

重写用户当前 prompt，使其能明确回应上述回复。只输出重写结果。
```

- 只选择最近 assistant turn 的 text block，不包含 thinking、tool call、tool result、图片或整段 session。
- Pi message 不显示在编辑器、不写入 prompt 文件、UserDefaults、Usage archive 或日志。
- 只有提示词包含 `${message}` 且用户明确触发重写时，Pi message 才会发送给当前所选 Provider。
- 普通 `cue --wait`、未安装 integration、bridge 超时或验证失败时，`${message}` 展开为空；普通编辑和不依赖该变量的重写继续可用。
- 多个并发 Cue 会话分别持有启动时取得的 message snapshot，不会互相覆盖。


## 从源码构建

要求 macOS 26+、Swift 6.2、Node.js 22+ 和完整的 Xcode 工具链。仅安装 Xcode Command Line Tools 不足以构建当前版本：SwiftUI 的 `@State` 在较新的 macOS SDK 中依赖 Xcode 提供的 `SwiftUIMacros` 编译器插件。

安装 Xcode 后，选择其 Developer 目录并完成首次初始化（如果 Xcode 安装在其他位置，请相应调整路径）：

```bash
sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer
sudo xcodebuild -license accept
sudo xcodebuild -runFirstLaunch
```

验证当前 shell 使用的是完整 Xcode 工具链：

```bash
xcode-select -p
xcodebuild -version
xcrun --find swift
```

输出中的开发者目录应与实际安装的 Xcode Developer 目录一致（上例为 `/Applications/Xcode.app/Contents/Developer`），并且 `xcodebuild` 应能正常显示 Xcode 版本。如果不希望全局切换开发者目录，也可以在构建时设置 `DEVELOPER_DIR`，例如：

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer make check
```

获取源码并构建：

```bash
git clone https://github.com/haotzops/cue-notchpad.git
cd cue-notchpad
make check
make app
open "build/Cue Notchpad.app"
```

`make check` 是本地开发的统一质量门禁：校验脚本与源码 metadata、构建 debug products，并运行全部测试。需要更细粒度操作时，可单独使用 `make build`、`make test`、`make app` 或 `make install`；这些入口始终生成 debug 开发构建。如果出现 `external macro implementation type 'SwiftUIMacros.StateMacro' could not be found` 或 `plugin for module 'SwiftUIMacros' not found`，请先检查 `xcode-select -p` 是否指向完整 Xcode，并清理旧工具链产生的缓存后重试：

```bash
rm -rf .build build
make check
```

`make release-preflight` 是本地、CI 与 tag workflow 共用的发布前门禁：先执行 `make check`，然后只构建一次本地 Release 候选 ZIP，并验证 checksum、provenance、app metadata、签名、架构、资源和 CLI smoke test。该命令不会上传或发布任何内容；正式 Release 只能由 `v*.*.*` tag workflow 发布。运行 `make help` 可查看完整命令分组。

发布预检支持以下变量：

- `RELEASE_VERSION`：写入 `CFBundleShortVersionString`，默认读取 `Supporting/Info.plist`。
- `BUILD_NUMBER`：写入 `CFBundleVersion`，必须是正整数，默认值为 `1`。
- `DIST_DIR`：候选资产输出目录，默认 `dist`。

执行完整发布预检，准备本地 Release 候选 ZIP、SHA-256 与 provenance，但不进行上传或发布：

```bash
RELEASE_VERSION=0.1.0 BUILD_NUMBER=1 make release-preflight
```

产物位于 `dist/`。正式发布工作流使用同一个 `release-preflight` 入口，只构建一次 ZIP，校验 GitHub asset digest 后发布 immutable release。发布成功后，可单独运行 Homebrew Cask workflow，以该正式 asset 的 digest 创建 Tap 更新 PR。完整流程见 [`Docs/releasing.md`](Docs/releasing.md)。

## 从源码安装

默认安装到当前用户目录，不需要 sudo：

```bash
make install
export PATH="$HOME/.local/bin:$PATH"
```

这会创建：

- `~/Applications/Cue Notchpad.app`
- `~/.local/bin/cue`

如果 Cue 正在等待编辑会话，安装会主动中止，以避免覆盖正在运行的 `cue-host`；请先提交或取消编辑，再重新执行安装。

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

发版前需要安装并人工验收本地候选资产时，运行：

```bash
RELEASE_VERSION=0.3.2 BUILD_NUMBER=1 make install-rc
```

该命令会执行完整 `release-preflight`，生成并验证候选 ZIP，然后安装这份 ZIP；它不会上传或发布任何内容。

为精确复现用户正在运行的公开版本，下载指定正式资产、校验其官方 `SHA256SUMS` 后安装：

```bash
make install-release VERSION=0.3.1
```

该命令不会从源码重建；它安装的 ZIP 与用户下载的正式 Release 相同。因此公开安装入口仅对应三种情境：`make install` 用于 debug 开发，`make install-rc` 用于候选验收，`make install-release` 用于正式版复现。每个 app bundle 的 `Contents/Resources/BuildInfo.json` 和 Release 附带的 `PROVENANCE.json` 记录版本、构建号、源码 revision、配置、架构及工具链信息。

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
