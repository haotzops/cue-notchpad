# Cue Notepad

`cue --wait` 是一个只做一件事的 macOS prompt 编辑器：从命令行打开依附在屏幕顶部 notch 上的编辑面板，等待编辑完成，再把文本原样写回标准输出。

## 使用

```bash
cue --wait
```

- `⌘ Return`：完成，关闭面板并把文本写到 stdout（不会额外添加换行）
- `Esc`：取消整次 wait，退出码为 `130`，stdout 为空（不会返回初始文本或当前编辑文本）
- `⌘ H`：暂时隐藏窗口但继续等待；通过菜单栏临时出现的 `CUE` 菜单恢复或取消
- `⌘ ,`：打开原生 macOS 设置窗口
- 普通 `Return`：在 prompt 中换行
- 若 stdin 是管道，其内容会作为初始 prompt

底部的 token 数使用本地内置的 OpenAI `cl100k_base` tokenizer 计算；prompt 内容不会因此发送到网络。

示例：

```bash
prompt="$(cue --wait)"
printf '重写这段 prompt' | cue --wait > edited.txt
```

面板关闭后会像 CotEditor 的 `cot --wait` 一样，把焦点还给调用命令时位于前台的终端应用。

多个并发的 `cue --wait` 会按单会话队列串行显示：当前会话完成或取消后，下一个调用才打开窗口。每个进程分别保留自己的 stdin、stdout 和退出状态。

界面会跟随 macOS 的首选语言，当前内置：

- English
- 简体中文

设置窗口可以覆盖系统语言，并配置展开内容区的宽度、高度以及是否默认置于其他窗口上方。默认内容区尺寸为 `680 × 292 pt`。

## 构建

要求 macOS 13+ 和 Swift 6/Xcode Command Line Tools。

```bash
make test
make app
```

app bundle 会生成到：

```text
build/Cue Notepad.app
```

## 安装

默认安装到当前用户目录，不需要 sudo：

```bash
make install
export PATH="$HOME/.local/bin:$PATH"
```

这会创建：

- `~/Applications/Cue Notepad.app`
- `~/.local/bin/cue`

也可以安装到系统目录：

```bash
APP_DIR=/Applications BIN_DIR=/usr/local/bin make install
```

如果对应目录不可写，请在命令前使用 `sudo`，并显式设置 `HOME` 或直接指定 `APP_DIR` / `BIN_DIR`。

## 实现说明

- UI 参考本地 `boring.notch` 的顶部居中透明 panel、黑色 notch 容器、上下不同圆角和 spring 展开方式；编辑 panel 可以成为 key window，因此无需辅助功能权限即可输入。
- 等待及焦点恢复语义参考本地 CotEditor 的 `cot --wait`；`cue` 进程本身运行 AppKit event loop，所以 shell 会自然阻塞到编辑结束，不需要轮询或常驻后台服务。
- 应用采用 accessory activation policy，不显示 Dock 图标；仅在用户通过 `⌘ H` 暂时隐藏等待窗口时显示临时 `CUE` 菜单栏项目。
- 设置存储在标准 macOS `UserDefaults` 中，通过 `⌘ ,` 打开原生风格设置窗口。
