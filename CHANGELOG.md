# 更新日志

Cue Notchpad 的重要变更都会记录在此文件中。

格式参考 [Keep a Changelog](https://keepachangelog.com/zh-CN/1.1.0/)，
版本号遵循[语义化版本](https://semver.org/lang/zh-CN/)。

## [未发布]

### 新增

- 新增 Pi integration 安装/修复/卸载：可将 Cue 管理的全局 Pi 扩展安装到 `~/.pi/agent/extensions/pi-cue-context`（或 `PI_CODING_AGENT_DIR` 指定目录），并提供 Pi `externalEditor = "cue --wait"` 的可复制配置指引；Cue 不会自动修改 Pi 设置。
- 未安装 Pi integration 时，内联补全开关保留原用户设置但不可启用，并显示原因。

## [0.3.1] - 2026-08-04

### 变更

- 发布构建统一为 arm64；开发构建、Release 预检与正式发布拆分为明确的 Make 入口。
- Release 归档改为 `macOS-arm64.zip`，并附带可追溯构建 metadata；CI 与发布文档同步更新。
- Release 改为单次构建后先上传 Draft、校验 GitHub asset digest 再发布，并使用最终 digest 自动创建 Homebrew Tap 更新 PR。
- 新增下载、校验并安装指定公开 Release 的入口，用于资产级 issue 复现。
- Actions 固定到完整 commit SHA，并由 Dependabot 提供受审查的更新；新增正式版问题报告表单。

## [0.3.0] - 2026-08-03

### 新增

- 新增可选的 DeepSeek FIM 行间补全：以半透明建议显示在光标后，按 Tab 才会插入文本；支持流式响应、IME 保护与异步请求取消。
- 在设置中提供 DeepSeek API Key 的 本地配置文件保存与移除操作（也支持 CUE_DEEPSEEK_API_KEY 环境变量），以及通过官方 `GET /models` 获取并选择模型的能力；该功能默认关闭，并明确提示会向 DeepSeek 发送附近的 prompt 文本。
- 可选择自动或仅 ⇧Tab 触发补全、设置自动触发延迟与最大补全行数；底部显示累计 FIM token 用量。
- 新增 AI 润色：可为润色与 FIM 分别选择模型，配置润色提示词并通过快捷键替换当前 prompt。
- 设置改为通用、AI、使用统计和快捷键分页；新增按日期范围统计的 FIM 用量、API 调用次数与 Cue 打开次数。
- 通用设置新增编辑器字号输入和步进控制；编辑器聚焦时可用 ⌘+ / ⌘- 调整字号。
- AI 设置新增 DeepSeek 服务健康检测和 FIM 请求测试；通用设置新增还原全部应用设置与清除使用统计的确认操作，并明确说明各操作保留或删除的数据。

### 变更

- 调整 Prompt 顶部品牌标识、编辑器内部 placeholder 与底部快捷键的可读性。

### 修复

- 修复随内容增长模式混用旧 viewport 与 TextKit 布局数据导致的窗口跳动或延迟扩展；窗口高度现依据同一布局快照的实际文本所需高度计算。

## [0.2.0] - 2026-07-30

### 新增

- 可在设置中通过 macOS 原生字体面板选择编辑器字体和字号；所选字体会立即应用并记住。未安装的已选字体会安全回退至系统字体。
- 可选在提交 prompt 时自动为相邻的中文和英文/数字补充空格；标点、已有空白和换行保持不变。

### 变更

- Homebrew Cask 安装完成后自动移除 Cue Notchpad 的 quarantine 属性，避免首次启动时被 Gatekeeper 阻止。

### 修复

- 修正 Homebrew 安装文档，不再使用当前 Homebrew 已移除的 `--no-quarantine` 参数。

## [0.1.0] - 2026-07-29

### 新增

- 提供依附于屏幕顶部 notch 的 prompt 编辑器，并兼容标准 `$EDITOR` / `$VISUAL` 文件接口。
- 提供阻塞式 `cue --wait` 命令，支持 stdout 输出和原子文件写回。
- 支持多个并发编辑会话、调用方识别和键盘切换。
- 支持英文和简体中文界面。
- 支持配置窗口尺寸、内容增长方式和全局快捷键。
- 使用本地 `cl100k_base` 词表计算 token，不发送网络请求。
- 添加 Cue Notchpad 应用图标。

[0.3.1]: https://github.com/haotzops/cue-notchpad/compare/v0.3.0...v0.3.1
[0.3.0]: https://github.com/haotzops/cue-notchpad/compare/v0.2.0...v0.3.0
[0.2.0]: https://github.com/haotzops/cue-notchpad/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/haotzops/cue-notchpad/releases/tag/v0.1.0
