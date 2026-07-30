# 更新日志

Cue Notchpad 的重要变更都会记录在此文件中。

格式参考 [Keep a Changelog](https://keepachangelog.com/zh-CN/1.1.0/)，
版本号遵循[语义化版本](https://semver.org/lang/zh-CN/)。

## [未发布]

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

[未发布]: https://github.com/haotzops/cue-notchpad/compare/v0.2.0...HEAD
[0.2.0]: https://github.com/haotzops/cue-notchpad/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/haotzops/cue-notchpad/releases/tag/v0.1.0
