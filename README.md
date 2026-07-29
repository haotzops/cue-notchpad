# Cue Notchpad

Cue Notchpad 只做一件事，替代你的 `code --wait`/`cot --wait` 作为外挂 prompt 编辑器：从命令行打开依附在屏幕顶部 notch 上的编辑面板，等待编辑完成，再把文本原样写回标准输出。

## 使用

```bash
cue --wait
```

- `⌘ Return`：完成，关闭面板并把文本写到 stdout（不会额外添加换行）
- `Esc`：取消当前 wait，退出码为 `130`，stdout 为空；有其他并发会话时 Cue 会隐藏，待用全局显示快捷键恢复
- `⌘ H`：暂时隐藏窗口但继续等待；不会提交、取消或修改原文件
- `⌥⌘ C`：在任意应用中显示或隐藏 Cue（可在设置中修改）
- `⌥⌘ ←` / `⌥⌘ →`：切换上一个/下一个并发会话（可在设置中修改）
- `⌘ ,`：打开原生 macOS 设置窗口
- 普通 `Return`：在 prompt 中换行
- 若 stdin 是管道，其内容会作为初始 prompt

底部的 token 数使用本地内置的 OpenAI `cl100k_base` tokenizer 计算；prompt 内容不会因此发送到网络。词表在构建期转换为连续二进制哈希索引，运行时只读映射，不会为 100,256 个 token 分别创建 Swift 对象。

示例：

```bash
prompt="$(cue --wait)"
printf '重写这段 prompt' | cue --wait > edited.txt

# 标准 $EDITOR / $VISUAL 文件接口（Pi、Codex、OpenCode 等）
cue --wait /tmp/prompt.md
cue /tmp/prompt.md
```

提交后会像 CotEditor 的 `cot --wait` 一样，把焦点还给调用命令时位于前台的终端应用。

`cue` 兼容标准 `$EDITOR` / `$VISUAL` 约定：编辑器命令接收一个文本文件路径，成功提交才原子写回文件；`Esc` 返回 `130` 且不写回，因此调用方原有 prompt 会保留。Pi、Codex、OpenCode 都可将 `cue --wait` 配置为外部编辑器。

多个并发请求由单一 Cue Host 同时管理而非串行阻塞。底部只在多于一个会话时显示 `‹ 2 / 4 ›`；箭头可切换会话，每个调用方各自等待并只获得自己的结果。顶部调用方名称来自父进程树（例如 Pi、Codex、OpenCode），不依赖专用 agent 协议。

界面会跟随 macOS 的首选语言，当前内置：

- English
- 简体中文

设置窗口可以覆盖系统语言，配置展开内容区的宽度和最小高度（默认 `650 × 150 pt`，范围 `130–800 pt`），选择“可滚动窗口”或“随行数增加”，并录制全局显示/隐藏及前后会话快捷键。后者会按真实文本布局向下扩展，达到上限后自动滚动。Prompt 始终置顶。

## 构建

要求 macOS 13+ 和 Swift 6/Xcode Command Line Tools。

```bash
make test
make app
```

app bundle 会生成到：

```text
build/Cue Notchpad.app
```

## 安装

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

## 实现说明

- UI 参考本地 `boring.notch` 的顶部居中透明 panel、黑色 notch 容器、上下不同圆角和 spring 展开方式；编辑 panel 可以成为 key window，因此无需辅助功能权限即可输入。
- 等待及焦点恢复语义参考本地 CotEditor 的 `cot --wait`；轻量 `cue` 客户端经用户私有 Unix socket 将请求交给单一 GUI Host，shell 自然阻塞至自己的会话结束。
- 应用采用 accessory activation policy，不显示 Dock 图标；不依赖菜单栏状态项，并安装本地化的标准 Edit responder-chain 菜单来支持 Command-C/V、撤销、重做、剪切和全选。
- 设置存储在标准 macOS `UserDefaults` 中，通过 `⌘ ,` 打开原生风格设置窗口。
- `Supporting/Tokenizer/cl100k_base.tiktoken` 是上游词表来源；`Scripts/generate-tokenizer-index.py` 会校验其 SHA-256，并生成 app 实际使用的紧凑 `cl100k_base.cuebpe` 资源。
