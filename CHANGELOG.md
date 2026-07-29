# 更新日志

Cue Notchpad 的重要变更都会记录在此文件中。

格式参考 [Keep a Changelog](https://keepachangelog.com/zh-CN/1.1.0/)，
版本号遵循[语义化版本](https://semver.org/lang/zh-CN/)。

## [0.1.0] - 2026-07-29

### 新增

- 提供依附于屏幕顶部 notch 的 prompt 编辑器，并兼容标准 `$EDITOR` / `$VISUAL` 文件接口。
- 提供阻塞式 `cue --wait` 命令，支持 stdout 输出和原子文件写回。
- 支持多个并发编辑会话、调用方识别和键盘切换。
- 支持英文和简体中文界面。
- 支持配置窗口尺寸、内容增长方式和全局快捷键。
- 使用本地 `cl100k_base` 词表计算 token，不发送网络请求。
- 添加 Cue Notchpad 应用图标。

[0.1.0]: https://github.com/haotzops/cue-notchpad/releases/tag/v0.1.0
