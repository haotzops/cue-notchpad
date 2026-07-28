# 中文全角标点与尾随光标间距修改方案

> 状态：仅方案，等待 review；本次未改动标点排版行为。

## 当前实现

编辑器位于 `Sources/cue/PromptTextEditor.swift`：

- SwiftUI 通过 `NSViewRepresentable` 包装 `NSScrollView` 和 `NSTextView`。
- `NSTextView` 使用 `NSFont.systemFont(ofSize: 16, weight: .regular)`。
- 编辑器设为纯文本模式（`isRichText = false`）。
- 文本布局、输入法 marked text 和 insertion point 全部由系统 TextKit/NSTextView 处理。
- 当前没有对中文字体、全角标点、字距或光标位置做自定义处理。

在当前字体配置下实测 16 pt 字号的 glyph advance：

| 内容 | advance |
| --- | ---: |
| `中`（系统字体回退） | 约 15.88 pt |
| `，`（系统字体回退） | 约 8.09 pt |
| `，`（PingFang SC） | 16 pt |

因此当前的 `，` 实际只获得约半个中文字符的 advance，系统光标紧跟该 advance，视觉上就会紧贴逗号。这不是我们手动绘制光标造成的。

## 拟议修改

1. 编辑器主体继续使用系统字体，避免改变拉丁字符、数字和 emoji 的现有观感。
2. 为 `，。！？；：（）【】《》“”‘’` 等 CJK 全角标点建立明确字符集合。
3. 对已提交、且不处于输入法 marked-text 状态的上述字符，单独应用 16 pt `PingFang SC` 字体；若字体不可用则保持系统字体。
4. 内部使用 attributed text 承载字体信息，但对外仍只读取 `NSTextView.string`，因此 stdout 保持纯文本且不会包含格式。
5. 粘贴时去掉来源格式，再按字符重新应用系统字体/CJK 标点字体，避免网页富文本污染编辑器。
6. 重新应用属性时保存并恢复 selection，禁止递归触发 delegate，同时保留 Undo/Redo 行为。
7. 输入法正在组词时不修改 text storage；仅在 marked text 提交后执行规范化，避免干扰拼音候选框。

## 验收标准

- 16 pt 下 `，` 和常用全角标点的 advance 接近 16 pt，尾随光标保留正常的右侧留白。
- 英文逗号 `,` 仍使用系统字体和原有比例宽度。
- 拼音输入、候选选择、跨行输入不闪动、不跳光标。
- `⌘ Return` 返回的 Unicode 文本与用户输入完全一致。
- 复制、粘贴、Undo、Redo 和多行选择行为不回退。
- 覆盖简体中文、繁体中文、英文与 emoji 混排测试。

## 备选方案

直接对标点添加 `.kern` 可以产生间距，但会人为改变所有字体的排版，且容易在换行处留下多余 advance。因此优先采用“仅为 CJK 标点指定原生中文字体”的方案，不建议全局 kerning。
