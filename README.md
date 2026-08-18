# Cue Notchpad

<p align="center">
  <img src="Supporting/logo.svg" alt="Cue Notchpad Logo" width="220">
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

Provider 与 API adapter 参考 Pi Coding Agent 的分层设计，但只内置官方条款未限定工具白名单、指定交互场景或专属客户端 OAuth 的接入方式：

| 类别 | 内置 Provider |
|---|---|
| 官方 API | DeepSeek、OpenAI、Anthropic、Google Gemini、OpenRouter、Moonshot AI CN（Kimi）、Z.AI（智谱 GLM 国际版）、MiniMax、Xiaomi MiMo、Ant Ling、阿里云百炼（DashScope）、火山方舟 Ark、腾讯混元、百度千帆、SiliconFlow（硅基流动） |
| Token Plan | MiniMax Token Plan CN、Xiaomi MiMo Token Plan CN |
| 平台与网关 | OpenCode Zen、OpenCode Go、Azure OpenAI、Google Vertex AI、Amazon Bedrock、Together AI、Fireworks AI、Groq、Hugging Face、NVIDIA NIM、Vercel AI Gateway、Cloudflare AI Gateway、xAI API |
| 本地 | Ollama、LM Studio、vLLM、llama.cpp、LocalAI、MLX、Jan、GPT4All、KoboldCpp、Msty |
| 自定义 | OpenAI Chat Completions、OpenAI Responses、Anthropic Messages 或 Google Generative AI；可配置 Base URL 与 Model ID |

OpenCode、Fireworks、Cloudflare 与 xAI 可按 Provider 实际 endpoint 选择 API。Azure OpenAI 需填写以 `/openai/v1` 结尾的资源 Base URL；Vertex 需填写包含 project、location 与 `publishers/google` 的完整 Base URL；Cloudflare 需填写包含 account、gateway 与所选 API route 的 Base URL；Bedrock 当前支持官方 long-term API key/bearer token，不读取 AWS profile 或 ADC。模型目录是可编辑的初始列表，仍可直接输入任意有效 Model ID。

本地 Provider 默认指向本机端口（Ollama 11434、LM Studio 1234、vLLM 8000、llama.cpp/LocalAI/MLX 8080、Jan 1337、GPT4All 4891、KoboldCpp 5001、Msty 3000），无需 API Key；地址可在设置中改为局域网内推理服务。模型列表在服务启动后可刷新。

支持的环境变量：`CUE_DEEPSEEK_API_KEY` / `DEEPSEEK_API_KEY`、`OPENAI_API_KEY`、`ANTHROPIC_API_KEY`、`GEMINI_API_KEY`、`OPENROUTER_API_KEY`、`MOONSHOT_API_KEY`、`ZAI_API_KEY`、`MINIMAX_API_KEY`、`XIAOMI_API_KEY`、`ANT_LING_API_KEY`、`DASHSCOPE_API_KEY`、`ARK_API_KEY`、`HUNYUAN_API_KEY`、`QIANFAN_API_KEY`、`SILICONFLOW_API_KEY`、`MINIMAX_CN_API_KEY`、`XIAOMI_TOKEN_PLAN_CN_API_KEY`、`OPENCODE_API_KEY`、`AZURE_OPENAI_API_KEY`、`GOOGLE_CLOUD_API_KEY`、`AWS_BEARER_TOKEN_BEDROCK`、`TOGETHER_API_KEY`、`FIREWORKS_API_KEY`、`GROQ_API_KEY`、`HF_TOKEN`、`NVIDIA_API_KEY`、`AI_GATEWAY_API_KEY`、`CLOUDFLARE_API_KEY`、`XAI_API_KEY`、`CUE_CUSTOM_API_KEY`。环境变量优先于本地配置文件。自定义本地服务（例如 Ollama、LM Studio、vLLM）可以不配置 API Key。

Cue 刻意不内置 GLM Coding Plan、阿里云百炼 Coding Plan、腾讯 TokenHub、讯飞 Astron、Kimi Code subscription、百度/火山 Coding Plan，以及 GitHub Copilot、ChatGPT Codex、SuperGrok 等订阅登录：这些服务存在指定工具/场景范围、专属客户端 OAuth，或缺少足够明确的自定义客户端授权。普通开放 API 与受限订阅权益不能混用。

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

要求 macOS 13+、Swift 6、Node.js 22+ 和 Xcode Command Line Tools。首次使用可先安装命令行工具：

```bash
xcode-select --install
```

获取源码并构建：

```bash
git clone https://github.com/haotzops/cue-notchpad.git
cd cue-notchpad
make check
make app
open "build/Cue Notchpad.app"
```

`make check` 是本地开发的统一质量门禁：校验脚本与源码 metadata、构建 debug products，并运行全部测试。需要更细粒度操作时，可单独使用 `make build`、`make test`、`make app` 或 `make install`；这些入口始终生成 debug 开发构建。

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
