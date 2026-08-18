# 版本发布流程

项目通过 GitHub Release 分发 arm64 app，并在 Release 发布后由独立 workflow 更新 `haotzops/tap/cue-notchpad` Homebrew Cask。Release asset 是分发真源；Cask 更新失败不影响已验证的正式 Release。

## 1. 准备发布提交

以下示例以 `0.1.0` 为例，后续版本替换 `VERSION` 即可：

```bash
VERSION=0.1.0
TAG="v$VERSION"
```

发布前只需完成：

1. 确认计划发布的代码已合入 `main`，工作区干净。
2. 将 `Supporting/Info.plist` 中的 `CFBundleShortVersionString` 更新为 `$VERSION`。
3. 创建或更新 `Docs/releases/$TAG.md`。这是面向用户的唯一变更说明。

`Packaging/homebrew/cue-notchpad.rb.template` 只保存 `@VERSION@` 和 `@SHA256@` 占位符。不得向其中填写本地构建的校验值；Cask workflow 只使用 GitHub 已发布 asset 的 digest。

## 2. 可选本地候选验收

`main` 的 CI 与 tag workflow 都会运行相同的 `make release-preflight` 门禁。一般的常规版本无需在本地重复执行候选验收；涉及安装、更新、界面或端到端交互变更时，建议人工验收候选包：

```bash
RELEASE_VERSION="$VERSION" BUILD_NUMBER=1 make install-rc
```

该命令会生成、验证并安装候选 ZIP，但不会上传或发布内容。只需生成候选包时使用 `make release-preflight`。

## 3. 创建 tag 并发布 Release

提交版本改动后创建附注 tag 并推送：

```bash
git add Supporting/Info.plist "Docs/releases/$TAG.md"
git commit -m "chore(release): 发布 v$VERSION"
git tag -a "$TAG" -m "Cue Notchpad $TAG"
git push origin main
git push origin "$TAG"
```

推送 `v*.*.*` tag 会触发 `.github/workflows/release.yml`。该工作流将：

1. 校验 tag、Info.plist 与 Release notes。
2. 使用与本地、CI 相同的 `make release-preflight`，只构建一次 arm64 ZIP，并上传 ZIP、`SHA256SUMS`、`PROVENANCE.json` 为 workflow artifact。
3. 创建 Draft Release，比较本地 SHA-256 与 GitHub asset digest；不一致时保留 Draft 并停止发布。
4. digest 一致后发布 Release，并确认仓库的 immutable releases 已生效。

工作流成功后，从 GitHub Release 重新下载公开资产进行最终校验：

```bash
gh release download "$TAG" --dir "/tmp/cue-notchpad-$VERSION"
(cd "/tmp/cue-notchpad-$VERSION" && shasum -a 256 -c SHA256SUMS)
gh release view "$TAG" --json isImmutable,assets
```

确认 `isImmutable` 为 `true`，并检查 Release 标题、正文、ZIP、`SHA256SUMS`、`PROVENANCE.json` 与下载链接。需要精确复现公开版本时：

```bash
make install-release VERSION="$VERSION"
cue --invalid-option  # 预期退出码 64
```

## 4. 发布后更新 Homebrew Cask

GitHub Release 成功后，在 Actions 页面手动运行 `Update Homebrew Cask` workflow，输入不带 `v` 的版本号；或使用：

```bash
gh workflow run homebrew-cask.yml -f version="$VERSION"
```

该 workflow 仅接受已公开且 immutable 的 Release。它读取该 Release ZIP 的 GitHub asset digest，渲染 Cask，并在真实 Tap checkout 中执行 Ruby 语法检查、`brew audit`、安装与 CLI smoke test；全部通过后才创建 Tap PR。

首次运行前，配置具备 `haotzops/homebrew-tap` 的 Contents 与 Pull requests 读写权限的 fine-grained secret `HOMEBREW_TAP_TOKEN`。该 token 仅影响 Cask workflow，绝不会阻断 GitHub Release。

合并 Tap PR 后运行：

```bash
brew update
brew install --cask haotzops/tap/cue-notchpad
cue --invalid-option  # 预期退出码 64
brew uninstall --cask cue-notchpad
```

需要本地检查模板渲染时，使用唯一的生成入口：

```bash
./Scripts/render-homebrew-cask.sh "$VERSION" "<64 位小写 SHA-256>" /tmp/cue-notchpad.rb
ruby -c /tmp/cue-notchpad.rb
```

## 5. 发布后规则

- GitHub Release、`SHA256SUMS`、`PROVENANCE.json` 与 Cask 必须引用同一次正式构建产生的 ZIP。
- 不要使用 `gh release upload --clobber`，也不要替换已有版本的 ZIP；已公开版本的修复使用新的补丁版本。
- 不要为版本化 Release asset 使用 `sha256 :no_check`。
- Cask workflow 或 Tap PR 失败时，只修复 Cask 流程并重新运行它；不得重建或替换已发布 ZIP。
- 当前发行使用 ad-hoc 签名；Developer ID 签名或 Apple 公证策略发生变化时，同步更新 README、Release 说明和 Cask caveats。
