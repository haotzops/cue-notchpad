# DeepSeek FIM 行间补全开发方案

> 状态：首版已实现，尚未发布。
>
> 实现范围：DeepSeek FIM SSE、Keychain API Key、默认关闭的设置、TextKit ghost text、Tab 接受/Esc 关闭、IME/异步取消保护及 Core 纯逻辑测试已完成。Provider HTTP mock、可配置接受键、多候选和用量展示保留为后续迭代。

## 1. 目标与边界

为 Cue Notchpad 的 prompt 编辑器加入类似 VS Code 的 **行间补全（inline completion / ghost text）**：用户在光标处输入时，应用将“光标前文本”和“光标后文本”发送给用户显式配置的 DeepSeek FIM 服务，将返回内容以半透明预览显示在光标后。预览不是文档的一部分；用户按接受快捷键后才写入真实文本。

首版目标：

- 可在设置中显式启用/关闭，默认关闭；
- 通过 DeepSeek FIM 生成单个候选；
- 支持流式显示、多行候选、`Tab` 接受和 `Esc` 仅关闭候选；
- 中文输入法组合期间不请求、不显示、不改写；
- 绝不将 API Key 写入 `UserDefaults`、日志、Release 资产或 prompt 文本；
- 网络失败不打断编辑或 `cue --wait` 会话。

首版不做：

- LSP、项目索引、代码语义诊断；
- 多候选列表、候选排序或模型自动路由；
- 接受单词/接受下一行；
- 在用户未配置 Key 或未同意网络传输时发起请求；
- 将补全内容自动提交给调用方。

Cue 是通用 prompt 编辑器而不是代码 IDE；因此先把 FIM 的响应、隐私、IME 和编辑器一致性做好，后续才评估历史模板、本地模型或 LSP Provider。

## 2. 调研结论与外部 API 契约

DeepSeek 官方文档将 FIM 标记为 Beta。当前文档要求调用：

```text
POST https://api.deepseek.com/beta/completions
Authorization: Bearer <API key>
Content-Type: application/json
```

FIM 的核心字段如下：

```json
{
  "model": "deepseek-v4-pro",
  "prompt": "光标之前的文本",
  "suffix": "光标之后的文本",
  "max_tokens": 64,
  "temperature": 0.2,
  "stream": true,
  "stream_options": { "include_usage": true }
}
```

- `prompt` 是前缀，`suffix` 是可选后缀；返回的 `choices[0].text` 是应插入两者之间的文本。
- 流式响应是 SSE；每个 `data:` 事件承载 JSON，最后以 `data: [DONE]` 结束。
- 文档列出的参数还包括 `stop`（最多 16 个序列）、`top_p`、`echo` 与 `logprobs`。首版使用 `echo: false`（或不传，视最终接口默认值确认），不使用已废弃的 `frequency_penalty`、`presence_penalty`。
- 当前官方 `/completions` 页面列出的模型为 `deepseek-v4-pro`；FIM 是 Beta，模型可用性可能变化。因此模型名称应作为可验证配置，不能把“永久可用”假设编码进协议层。
- 常见错误：400/422 请求错误、401 Key 无效、402 余额不足、429 限流、500/503 服务端暂不可用。补全是可选增强，不得因这些错误弹出阻塞式对话框或影响提交。

官方参考：

- [FIM 指南](https://api-docs.deepseek.com/zh-cn/guides/fim_completion)
- [Create Completion API](https://api-docs.deepseek.com/zh-cn/api/create-completion)
- [错误码](https://api-docs.deepseek.com/zh-cn/quick_start/error_codes)
- [限流说明](https://api-docs.deepseek.com/zh-cn/quick_start/rate_limit)

## 3. 与现有代码的接入点

当前实现已经具备合适的基础：

| 现有位置 | 现状 | 接入方式 |
| --- | --- | --- |
| `Sources/CueApp/PromptTextEditor.swift` | `CueTextView` 是 `NSTextView` 子类，`Coordinator` 已避开 marked text | 在这里接收文本/选区/按键事件，并由子类绘制 ghost text |
| `PromptTextEditor.Coordinator` | 文本变化仅在非 IME 组合状态提交给 `PromptModel` | 文本变化后通知补全控制器；绝不把 ghost text 传给 `acceptCommittedText` |
| `CueTextView.keyDown` | 已处理 Cmd-Return、Esc、Cmd-,、Cmd-H | 补全激活时优先处理 `Tab` 与 `Esc`；未激活时保留当前 Esc 取消会话行为 |
| `Sources/CueApp/CueSettings.swift` | 持久化非敏感编辑器偏好 | 增加非敏感开关和参数；Key 不放这里 |
| `Sources/CueApp/SettingsWindowController.swift` | SwiftUI 设置表单 | 增加“AI 行间补全”分区与 Key 管理入口 |
| `Sources/CueCore` | 已承载可测试的纯逻辑 | 请求上下文裁剪、SSE 解析和状态转换放入可单测的类型 |

`Package.swift` 当前不需要引入第三方 SDK。macOS 13 的 `URLSession`、Swift Concurrency、`Security`/Keychain 与 AppKit 足以实现首版，避免增加 OpenAI SDK 依赖和供应链负担。

## 4. 架构设计

### 4.1 类型与职责

建议新增如下类型；具体文件名可在实现时微调：

```text
CueCore/
  InlineCompletion.swift              // 候选、上下文、状态、纯规则
  DeepSeekFIMRequest.swift            // Codable 请求/响应/SSE 事件解析
  InlineCompletionContextBuilder.swift // UTF-16 安全的前后文裁剪

CueApp/
  InlineCompletionProvider.swift      // 协议
  DeepSeekFIMCompletionProvider.swift // URLSession + SSE 实现（actor）
  InlineCompletionController.swift    // @MainActor，编辑器、任务和状态协调
  CueInlineCompletionRenderer.swift   // TextKit 1 ghost text 布局/绘制
  CueKeychain.swift                   // API Key 存取
```

建议协议：

```swift
protocol InlineCompletionProvider: Sendable {
    func streamCompletion(_ request: InlineCompletionRequest)
        -> AsyncThrowingStream<InlineCompletionDelta, Error>
}
```

`InlineCompletionController` 必须是 `@MainActor`，持有：

- 当前文档 `revision`；
- 当前 selection 的 UTF-16 `NSRange`；
- 当前候选文本和候选起点；
- debounce `Task` 与网络 `Task`；
- 单调递增的 `requestID`。

每个回调都校验 `requestID`、`revision`、光标位置、会话 ID、设置开关和 `hasMarkedText()`。任意一个不匹配就丢弃结果。这是防止“旧网络响应显示在新文字后”的核心约束。

### 4.2 状态机

```text
idle
  └─（可请求编辑）→ debouncing
      └─（150–250 ms 无新修改）→ requesting
          ├─（首个 delta）→ showing
          ├─（完成且空候选）→ idle
          ├─（网络/API 错误）→ idle + 非阻塞状态记录
          └─（任何失效事件）→ cancelled → idle
showing
  ├─（Tab）→ accepting → idle
  └─（Esc / 输入 / 移动光标 / 选区变化 / 切换会话 / 隐藏 / 关闭）→ idle
```

失效事件必须先 `cancel()` debounce 和网络 Task，再清空渲染器。取消是正常控制流，不向用户显示“请求失败”。

### 4.3 上下文与请求构造

1. 仅在以下条件满足时请求：功能启用、Key 存在、窗口展开、编辑器是第一响应者、无选区（`length == 0`）、无 marked text、非空或达到最小触发字符数。
2. 用当前 selection 的 UTF-16 位置将 `textView.string` 分为 `prefix` 与 `suffix`。必须通过 `String.Index(encodedOffset:)` 或经验证的 `Range(NSRange, in: String)` 转换，不能按 Swift `Character` 下标混用 `NSRange`。
3. 首版限制上下文，例如：前缀最近 6,000 个 UTF-16 code units、后缀最初 2,000 个；裁剪边界向外移动到完整扩展字形簇，避免截断 emoji、组合音标或中文字符。
4. 请求参数建议：`max_tokens: 64`、`temperature: 0.2`、`stream: true`。先不设置 `top_p`；官方建议不要同时调节它和 `temperature`。
5. 不要擅自对 prompt 添加“你是补全器”等聊天式 system prompt：该端点是 Completion/FIM 协议。若模型质量需要引导，另做可审计的请求模板设计，并在测试中锁定输入输出。
6. 对返回文本执行安全过滤：空文本、与已输入前缀重复的文本、只含控制字符的文本不展示；设定最大 UTF-16 长度和最大行数，超出时截断到完整字符边界并显示省略提示，或直接丢弃。不得修改真实文档。

### 4.4 流式 SSE

`DeepSeekFIMCompletionProvider` 使用 `URLSession` 发起 POST，不引入 SDK：

- 设置 `Authorization: Bearer …` 和 JSON body；
- 累积按任意字节边界到达的数据，按 SSE 空行分帧，不能假定一个网络 chunk 等于一个 JSON；
- 读取 `data:` 行；`[DONE]` 正常结束；其他行 JSON 解码为 completion chunk；
- 每个 chunk 的增量追加到候选，传给主线程；
- 正常取消映射为 `CancellationError`，不显示错误；
- 401/402 显示一次可操作的设置提示；429 采用冷却时间并静默停止；5xx/网络错误短暂状态提示后退避，不自动无限重试。

首版不采集远程遥测。只允许在开发构建中记录经过脱敏的状态、HTTP 状态和耗时；绝不记录 Key、`prompt`、`suffix`、候选完整文本或 Authorization header。

## 5. Ghost Text 的 TextKit 1 渲染方案

不能把候选写入 `NSTextStorage`：那会污染 `PromptModel`、字符/token 计数、自动中英文间距、文件写回、撤销栈和 stdout。

采用 `CueTextView` 内的独立渲染：

1. `CueInlineCompletionRenderer` 接收真实文本、插入位置、候选、字体、段落样式、`textContainer` 宽度和 `textContainerInset`。
2. 它建立**独立**的 scratch `NSTextStorage` / `NSLayoutManager` / `NSTextContainer`，内容为：
   `真实前缀 + ghost candidate + 真实后缀`。
3. 只对 candidate range 设置半透明前景色（例如白色 35%）、可选斜体或不同背景；真实文本保持与编辑器完全相同的字体、段落样式和容器宽度。
4. `CueTextView.draw(_:)` 先调用 `super.draw(_:)`，然后只绘制 scratch layout 中 candidate range 的 glyphs。因为它在同一个 document view 坐标系绘制，自动获得当前的滚动偏移与裁剪，不需将 ghost text 加到 SwiftUI 状态。
5. 在字体、编辑器宽度、text container inset、换行策略或真实文本变化时使 scratch layout 失效并重新布局。
6. ghost text 不参与 hit-testing、选择、高度测量、可访问性文本值或复制；可通过 accessibility announcement 提示“已提供建议，按 Tab 接受”。

该方案支持多行和自动换行。MVP 若出现性能问题，可先只渲染前 3 行/256 个字符，但接受逻辑必须与可见候选一致，不能接受用户看不到的尾部。

## 6. 键盘、IME、撤销与提交语义

`CueTextView.keyDown(with:)` 的优先级：

1. 有候选且无 marked text：`Tab` 接受；
2. 有候选且无 marked text：`Esc` 只清空候选，不取消 `cue --wait` 会话；
3. `⌘ Return` 保持现有提交行为；
4. 无候选时 `Esc` 保持现有取消行为；
5. 其余按键交给 `super`，由 `textDidChange` 失效当前候选并计划下一个请求。

接受时必须通过 AppKit 正规编辑路径插入，例如调用 `shouldChangeText(in:replacementString:)`、替换 selection、调用 `didChangeText()`，或使用等价的 `NSTextView` 编辑 API。验收要求：一次接受是一次可撤销操作，`⌘Z` 只撤销已接受候选，不能撤销或恢复 ghost text。

IME 规则：

- `hasMarkedText()` 为真时不调度请求、不接受候选、不因 Esc 关闭会话；
- `textDidChange` 仅在组合文本提交后才增加 revision；
- `textViewDidChangeSelection` 在非 marked 状态下使候选失效；
- 切换会话、隐藏、提交、取消和关闭窗口都必须同步取消任务。

## 7. 设置、Keychain 与隐私 UX

### 7.1 非敏感设置（`CueSettings` / `UserDefaults`）

```text
inlineCompletionEnabled: Bool = false
inlineCompletionProvider: "deepseekFIM"
inlineCompletionModel: String = "deepseek-v4-pro"
inlineCompletionDebounceMilliseconds: Int = 200
inlineCompletionMaxTokens: Int = 64
```

首版可只把模型显示为只读默认值，把高级参数隐藏，降低支持成本。所有值应校验范围；开关默认关闭。

### 7.2 API Key（Keychain）

- 使用 `Security.framework` 的 generic password item；
- `service`: `io.github.haotzops.cue-notchpad.inline-completion`；
- `account`: `deepseek-api-key`；
- accessibility 使用适合本机登录会话的 `kSecAttrAccessibleWhenUnlocked`；
- 设置页只显示“未配置”或已掩码的尾部，不读取回显完整 Key；提供“保存/替换”“移除”“测试连接”；
- Keychain 访问失败时显示可操作错误，功能保持关闭；
- 不支持在环境变量、命令行参数或普通偏好文件保存 Key，避免 shell history、进程列表和备份泄露。

### 7.3 设置文案与同意

新增“AI 行间补全”分区：

- 开关：`启用 DeepSeek 行间补全`；
- 说明：`启用后，光标附近的 prompt 文本会发送至 DeepSeek FIM API 以生成建议。候选仅在按 Tab 后写入。`；
- API Key 状态与管理按钮；
- `测试连接` 只发送一个固定、无用户内容的 FIM 测试请求；
- 连接状态、最近一次失败的简短原因和官方隐私/定价链接。

首次打开开关且 Key 已存在时，仍显示一次明确确认。DeepSeek 的数据保留、训练和地区合规政策不应靠猜测写入 Cue；实现前需要产品负责人根据当时官方隐私政策确认并链接到对应页面。

## 8. 错误、限流与性能策略

| 情形 | 行为 |
| --- | --- |
| 无 Key | 不调度请求；设置页提示配置 Key |
| 401 | 清除“可用”状态，不删除 Key；提示检查或替换 Key |
| 402 | 停止本会话请求；提示余额不足 |
| 400/422 | 记录脱敏诊断；不重试；实现缺陷需修复 |
| 429 | 取消队列，指数退避（例如 5、15、60 秒上限）；显示短暂限流状态 |
| 500/503/网络断开 | 静默清除候选，有限次数退避；不阻止编辑 |
| 超时 | 例如首个字节 8 秒、总请求 15 秒；取消并回到 idle |

性能目标：

- 本地输入到开始请求：约 200 ms debounce；
- 不因 ghost text 导致真实输入掉帧；
- 首 token 的网络耗时单独记录为开发诊断，不承诺固定 SLA；
- 每个编辑器/会话最多一个 in-flight 请求；
- 候选在下一次真实编辑、选区变化或会话切换后不晚于一个主线程 runloop 被移除。

## 9. 测试计划

### 9.1 单元测试（优先放入 `CueCoreTests`）

- UTF-16 caret range 对 CJK、emoji、ZWJ family emoji、组合音标和多行文本的 prefix/suffix 切分；
- 上下文裁剪不截断扩展字形簇；
- 请求 JSON：endpoint、必填字段、`max_tokens`、`temperature`、`stream`、suffix；
- SSE parser：单 chunk、多 chunk、任意分块边界、`[DONE]`、空 choices、错误 JSON；
- 状态机：debounce、输入后取消、过期 request ID、空候选、接受/忽略；
- 候选过滤和最大长度/行数规则。

### 9.2 Provider 与集成测试

- 用自定义 `URLProtocol` 或注入 HTTP transport 模拟 200 SSE、401、402、429、500、503、超时和取消；
- 断言取消后不再向 UI 发布 delta；
- 断言请求 header 含 Bearer Key，但任何测试输出和 error description 不含 Key 或文本上下文；
- Keychain 用协议封装，测试使用内存 fake，不能读写开发者真实 Keychain。

### 9.3 AppKit/手工回归

- 英文、简体中文、混合中英文、Nerd Font 私有区字符、多行和自动换行；
- 拼音、日文、韩文输入法：候选期间无 ghost text/请求，确认后才请求；
- Tab 接受、Esc 先关候选再取消、Cmd-Return、Cmd-Z/Cmd-Shift-Z、鼠标选区、箭头移动、粘贴；
- 会话切换、`⌘H` 隐藏、关闭、并发 `cue --wait`、文件写回和 stdout；
- 窗口尺寸、编辑器字体和 grow-with-content；
- VoiceOver 下真实文本不能包含未接受候选。

### 9.4 CI

现有 macOS CI 继续运行 `swift build`、`make test`、`make app` 与 Universal archive 校验。新增纯逻辑测试应并入 `make test`。不在 CI 调用真实 DeepSeek API，也不配置任何生产 Key；网络测试全部 mock。

## 10. 分阶段实施与验收门槛

### 阶段 A：基础与隐私

- 增加 Provider、Keychain、非敏感设置、请求/响应模型及 mock 测试；
- 设置页可以保存、掩码、移除 Key，并展示传输说明；
- 完成固定测试连接。

**门槛**：Key 不进入 `UserDefaults`、git diff、日志或 crash message；所有 Core/CI 测试通过。

### 阶段 B：非流式单候选闭环

- 以注入 fake provider 驱动候选；
- 实现 revision/cancellation、单行 ghost text、Tab/Esc/撤销；
- 接入真实 FIM 的非流式请求作为开发开关。

**门槛**：真实文档、字符数、token 数、提交 stdout 在展示候选前后均不变；接受后一次撤销可恢复原文本。

### 阶段 C：SSE 与多行 TextKit 渲染

- 增量 SSE parser；
- scratch TextKit renderer、多行/换行、滚动与重布局；
- 错误、限流和超时 UX。

**门槛**：所有手工 IME/会话/尺寸回归通过；取消后旧 delta 永不显示；无可见光标跳动。

### 阶段 D：Beta 发布与反馈

- 默认保持关闭；发布说明明确网络传输、Beta API 依赖、费用由用户 DeepSeek 账户承担；
- 收集用户主动提交的、无 prompt 内容的故障反馈；
- 根据延迟和误接受反馈决定是否做“接受单词”、本地历史 provider 或多模型支持。

**门槛**：至少一轮真实安装（Homebrew 与源码版）验证，且 `cue --wait` 的取消、提交、文件写回未回归。

## 11. 需要在开始编码前确认的产品决策

1. 是否仅支持 DeepSeek，还是一开始就暴露通用 OpenAI-compatible FIM endpoint？建议首版仅 DeepSeek，Provider 协议保留扩展点。
2. 是否允许网络补全用于任何来源（Pi、Codex、终端 stdin），还是要求每个会话确认？建议全局一次明确同意 + 设置中随时关闭。
3. 是否展示请求用量/费用？建议首版仅在设置页显示最近一次 usage（不持久化 prompt），待真实需求再加预算上限。
4. Tab 与现有 macOS 焦点导航冲突时，是否支持可配置接受键？建议首版 Tab，设置中预留快捷键演进空间。
5. DeepSeek Beta API 或模型名变化时的降级策略：建议禁用 Provider 并在设置页提示更新，而不是静默切换模型。
