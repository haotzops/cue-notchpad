# Cue Notchpad

<p align="center">
  <img src="Supporting/logo.svg" alt="Cue Notchpad Logo" width="220">
</p>

Cue Notchpad 只做一件事，替代你的 `code --wait`/`cot --wait` 作为外挂 prompt 编辑器。安装后，你只需要在各类 agent 工具的配置文件中，将 editor 配置为 `cue --wait`。在会话中，使用 `Control-G` 即可弹出 Cue 编辑器。

它的实用性在于，启动 Cue 后，你可以随意滚动终端，浏览历史消息，你不需要反复上下翻阅，你可以随时随地编辑你的 prompt，甚至在另一个桌面。Cue 还支持 AI 重写功能，允许你在编辑器中直接调用云端或本地的 LLM 服务，使用预制提示词重写/扩写当前 prompt。

遗憾的是，Pi v0.84.0 新增了 fullscreen 模式，它将编辑窗口固定在终端下方，解决了“无法同窗口便捷地 review 并编写 prompt”的核心问题。不过 Cue 是跨桌面的，你仍可以脱离终端窗口，在任意你喜欢的地方编辑 prompt。并且，Cue 的 AI 重写功能可以帮助你优化prompt。

对于 Pi 之外的其他 agent工具，Cue 不保证兼容性。

## 安装

### Homebrew

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

打开 Cue 时提示「已损坏，无法打开」或者 未知开发者警告 ，是因为项目使用 ad-hoc 签名，无 Apple 开发者签名。macOS 若阻止首次启动，可前往“系统设置 → 隐私与安全性”选择“仍要打开”；也可以在命令行移除该 app 的 quarantine 属性：

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
- 在“设置 → 供应商凭据”中可搜索并按折叠分类管理全部 Provider 的凭据（环境变量 / 本地保存 / 无需 Key），点选行即切换执行 AI 重写的 Provider。各 Provider 的凭据独立保存在 `~/Library/Application Support/Cue Notchpad/config.json`（权限 `0600`），也可由对应环境变量提供。Cue 只在用户按重写快捷键时发送当前 prompt。
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


## 开发

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

卸载默认的源码安装（只会删除 `~/Applications/Cue Notchpad.app` 和由 `make install` 创建的 `~/.local/bin/cue`，不会影响 Homebrew）：

```bash
make uninstall
```

使用自定义安装目录时，用相同的变量卸载：

```bash
APP_DIR=/Applications BIN_DIR=/usr/local/bin make uninstall
```

## 许可证与致谢

Cue Notchpad 使用 [GNU GPL v3.0 only](LICENSE) 发布。
界面实现参考 [boring.notch](https://github.com/TheBoredTeam/boring.notch)；
`--wait` 及焦点恢复行为参考 [CotEditor](https://github.com/coteditor/CotEditor)。

应用内置的 OpenAI `cl100k_base` 词表使用 MIT License。详细第三方声明见 [`Supporting/ThirdPartyNotices.txt`](Supporting/ThirdPartyNotices.txt)。
