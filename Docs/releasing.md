# 版本发布流程

本文档记录每个版本都需要重复执行的发布步骤。项目使用 GitHub Release 分发 arm64 app，并通过 `haotzops/tap/cue-notchpad` 提供 Homebrew 安装。

## 1. 确定版本内容

以下示例以 `0.1.0` 为例，后续版本替换 `VERSION` 即可：

```bash
VERSION=0.1.0
TAG="v$VERSION"
```

发布前完成：

- 确认 `main` 工作区干净，计划发布的代码已全部合入。
- 将 `Supporting/Info.plist` 中的 `CFBundleShortVersionString` 更新为 `$VERSION`。
- 更新 `CHANGELOG.md`，写入版本号、实际发布日期和最终变更。
- 创建或更新 `Docs/releases/$TAG.md`，作为面向用户的 GitHub Release 正文。
- 确认 README 中的安装命令、系统要求和未公证提示仍然准确。
- 在仓库设置中启用 immutable releases。
- 配置 Actions secret `HOMEBREW_TAP_TOKEN`；该 fine-grained token 必须能够读取和写入 `haotzops/homebrew-tap` 的 Contents 与 Pull requests。

`Packaging/homebrew/cue-notchpad.rb.template` 只保存 `@VERSION@` 和 `@SHA256@` 占位符。发布前不得填入本地构建的校验值；Homebrew Cask 必须由工作流使用 GitHub 最终接收的 Release asset digest 生成。

## 2. 本地预检

运行测试并生成 arm64 预检包。本地产物用于验证构建与安装链路，不得将其 checksum 写入 Cask；tag workflow 会在受控 job 中构建一次正式 ZIP，GitHub Release、Actions artifact 和 Homebrew 都引用该正式产物。`make release` 是本地 Release 预检，不是正式发布：

```bash
make test
RELEASE_VERSION="$VERSION" BUILD_NUMBER=1 make release
```

检查 ZIP、校验值与 provenance：

```bash
(cd dist && shasum -a 256 -c SHA256SUMS)
unzip -t "dist/Cue-Notchpad-$VERSION-macOS-arm64.zip"
python3 -m json.tool dist/PROVENANCE.json >/dev/null
```

发布脚本已经验证两个 Mach-O 均为 arm64 和 app 签名。需要人工复核时，解压 ZIP 后运行：

```bash
lipo -archs "Cue Notchpad.app/Contents/MacOS/cue"
lipo -archs "Cue Notchpad.app/Contents/MacOS/cue-host"
codesign --verify --deep --strict --verbose=2 "Cue Notchpad.app"
```

安装并验证这个已生成的预检产物：

```bash
RELEASE_ARCHIVE="dist/Cue-Notchpad-$VERSION-macOS-arm64.zip" \
  APP_DIR="$HOME/Applications" BIN_DIR="$HOME/.local/bin" \
  make install-release
cue --wait
```

并确认提交、取消、文件写回、语言切换和设置窗口行为正常。

## 3. 创建发布提交和 tag

将版本相关改动提交到 `main`。提交信息示例：

```text
chore(release): 发布 v0.1.0
```

创建附注 tag：

```bash
git tag -a "$TAG"
```

建议使用多行注释，而不是只写一个标题：

```text
Cue Notchpad v0.1.0

首个公开版本，提供阻塞式 prompt 编辑、并发会话、
英文与简体中文界面，以及离线 token 计数。

完整发布说明：Docs/releases/v0.1.0.md
```

推送前检查 tag 指向和内容：

```bash
git show "$TAG" --no-patch
```

确认无误后推送提交和 tag：

```bash
git push origin main
git push origin "$TAG"
```

## 4. 验证 GitHub Release

推送 `v*.*.*` tag 会触发 `.github/workflows/release.yml`。工作流将：

1. 校验 tag、Info.plist、发布说明和 Homebrew Tap 写权限。
2. 运行测试，只构建一次 arm64 ZIP，并同时保存 ZIP、`SHA256SUMS` 和 `PROVENANCE.json` 为 Actions artifact。
3. 创建 Draft Release，上传这三份资产。
4. 比较本地 SHA-256 与 GitHub 在上传时生成的 asset digest；不一致时保留 Draft 并停止发布。
5. digest 一致后发布 Release，并确认仓库的 immutable releases 已生效。
6. 使用最终 digest 渲染 Cask，在真实 Tap checkout 中执行 Ruby 语法检查、`brew audit`、安装和 CLI smoke test。
7. 向 `haotzops/homebrew-tap` 推送独立分支并创建更新 PR。

工作流成功后，从 GitHub Release 重新下载公开资产进行最终校验，不要只验证本地 `dist/`：

```bash
gh release download "$TAG" --dir "/tmp/cue-notchpad-$VERSION"
(cd "/tmp/cue-notchpad-$VERSION" && shasum -a 256 -c SHA256SUMS)
gh release view "$TAG" --json isImmutable,assets
```

确认 `isImmutable` 为 `true`，并检查 Release 标题、正文、ZIP、`SHA256SUMS`、`PROVENANCE.json` 与下载链接。用户 issue 应附带版本、build number 和 `BuildInfo.json` / `PROVENANCE.json`；开发者可运行 `make install-published-release VERSION="$VERSION"` 安装同一 ZIP 精确复现。

## 5. 合并 Homebrew Tap PR

Release workflow 会创建标题为 `chore(cask): 更新 Cue Notchpad v$VERSION` 的 Tap PR。该 PR 中的 `sha256` 来自已发布 ZIP 的 GitHub asset digest，不得用另一次本地构建的值替换。

合并前确认 workflow 已执行：

```bash
brew audit --cask --strict haotzops/tap/cue-notchpad
brew install --cask haotzops/tap/cue-notchpad
cue --invalid-option  # 预期退出码 64
brew uninstall --cask cue-notchpad
```

合并后运行 `brew update`，再按 README 验证一次公开安装。测试时先退出已经运行的 Cue Host，确保 Homebrew 创建的 `cue` 命令能够自行启动 app。

需要在本地检查模板渲染时，使用唯一的生成入口：

```bash
./Scripts/render-homebrew-cask.sh "$VERSION" "<64 位小写 SHA-256>" /tmp/cue-notchpad.rb
ruby -c /tmp/cue-notchpad.rb
```

## 6. 发布后规则

- Release asset 是分发真源；Actions artifact、GitHub Release、`SHA256SUMS`、`PROVENANCE.json` 和 Cask 必须引用同一次构建产生的字节。
- 不要使用 `gh release upload --clobber`，也不要替换已有版本的 ZIP；已公开版本的修复使用新的补丁版本。
- 不要为版本化 Release asset 使用 `sha256 :no_check`。
- Tap PR 未通过时修复 Cask 生成或 Tap 测试，不得重建或替换已经发布的 ZIP。
- Developer ID 签名或 Apple 公证策略发生变化时，同步更新 README、Release 说明和 Cask caveats。
- 发布完成后检查 GitHub Release 和 Homebrew 两种安装方式，确保 README 中的命令仍然可用。
