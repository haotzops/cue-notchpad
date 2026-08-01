# Cue 持久化兼容性约定

本文件是 Cue 的持久化数据兼容性契约。任何修改用户数据位置、key、格式、schema 或删除行为的变更都必须同时更新本文件、迁移代码和测试 fixture。

## 稳定身份

- Bundle identifier 永远为 `io.github.haotzops.cue-notchpad`。
- 设置由该 bundle identifier 对应的 `UserDefaults` 域保存。
- API Key 文件位置为 `~/Library/Application Support/Cue Notchpad/config.json`。
- Usage archive key 为 `cueUsageArchive.v1`，保存于同一 `UserDefaults` 域。

## 数据所有权与删除

用户的设置、API Key 和 Usage 都属于用户。Cue 不得在没有用户明确操作的情况下删除、清空、缩短或覆盖这些数据。

- `UserDefaults.register(defaults:)` 只能提供缺失 key 的默认值，不能重置用户值。
- Usage 为追加式历史；归档只能迁移或复制数据，不能删除历史。
- 删除 API Key 必须由用户在 UI 中明确发起，且只删除 API Key。
- 不得以迁移、容量控制或保留期为由自动删除用户数据。

## Schema 演进

- 每个结构化持久化格式必须含整数 `schemaVersion`。
- 当前 schema 只能添加可选字段或带默认值的字段；不得重命名、移除或改变既有字段含义。
- 迁移必须按版本顺序、幂等且原子化。迁移之前必须保留可恢复的源数据。
- 对会整体重写的文档，发现高于当前支持版本的 schema 时，必须进入只读模式：可以读取已知字段，但绝不能写回覆盖未知字段。
- `UserDefaults` 的设置使用独立、稳定的 key；高版本 schema 也不得重置、删除或重写整个 domain。
- JSON 重写必须保留未知字段。

## 验证要求

每次持久化格式变更必须：

1. 新增或更新 `Tests/Fixtures/Persistence/` 中的对应 fixture；
2. 增加“当前版本读取 fixture”的自动化测试；
3. 增加“未知字段仍被保留”与“未来 schema 不被写回”的测试；
4. 运行 `make test`、`swift build` 与 `git diff --check`。

代码审查中，涉及 `UserDefaults`、`Application Support`、`JSONEncoder`、`JSONDecoder`、`removeObject`、`removeItem`、bundle identifier 或持久化 key 的改动，必须按本约定审查。
