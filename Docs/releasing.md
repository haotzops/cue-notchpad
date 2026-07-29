# 版本发布流程

本文档记录每个版本都需要重复执行的发布步骤。项目使用 GitHub Release 分发 Universal app，并通过 `haotzops/tap/cue-notchpad` 提供 Homebrew 安装。

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

## 2. 本地预检

运行测试并生成同时包含 Apple Silicon 和 Intel 架构的发布包：

```bash
make test
RELEASE_VERSION="$VERSION" BUILD_NUMBER=1 make release
```

检查 ZIP 和校验值：

```bash
(cd dist && shasum -a 256 -c SHA256SUMS)
unzip -t "dist/Cue-Notchpad-$VERSION-macOS-universal.zip"
```

发布脚本已经验证两个 Mach-O 架构和 app 签名。需要人工复核时，解压 ZIP 后运行：

```bash
lipo -archs "Cue Notchpad.app/Contents/MacOS/cue"
lipo -archs "Cue Notchpad.app/Contents/MacOS/cue-host"
codesign --verify --deep --strict --verbose=2 "Cue Notchpad.app"
```

至少手动验证一次：

```bash
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

1. 校验 tag、Info.plist 和发布说明中的版本。
2. 运行测试。
3. 构建 `arm64 + x86_64` Universal app。
4. 执行 ad-hoc 签名并验证。
5. 上传 ZIP 和 `SHA256SUMS`。
6. 使用 `Docs/releases/$TAG.md` 创建 GitHub Release。

工作流成功后，从 GitHub Release 重新下载公开资产进行最终校验，不要只验证本地 `dist/`：

```bash
gh release download "$TAG" --dir "/tmp/cue-notchpad-$VERSION"
(cd "/tmp/cue-notchpad-$VERSION" && shasum -a 256 -c SHA256SUMS)
```

同时检查 Release 标题、正文、资产名称和下载链接是否正确。

## 5. 更新 Homebrew Tap

从 GitHub Release 的 `SHA256SUMS` 取得 ZIP 校验值。将 `Packaging/homebrew/cue-notchpad.rb.template` 复制到 `haotzops/homebrew-tap` 仓库的：

```text
Casks/cue-notchpad.rb
```

更新 Cask 中的：

- `version`
- `sha256`
- ZIP 文件名和 URL（格式变化时）
- 未公证提示（签名策略变化时）

提交 Tap 前执行：

```bash
brew tap haotzops/tap
brew audit --cask --strict haotzops/tap/cue-notchpad
brew install --cask haotzops/tap/cue-notchpad
command -v cue
cue --wait
brew uninstall --cask cue-notchpad
```

测试时先退出已经运行的 Cue Host，确保 Homebrew 创建的 `cue` 命令能够自行启动 app。

## 6. 发布后规则

- 不要替换已有版本的 ZIP；Homebrew 已记录其 SHA-256。
- 已公开版本的修复使用新的补丁版本，例如 `0.1.1`。
- Developer ID 签名或 Apple 公证策略发生变化时，同步更新 README、Release 说明和 Cask caveats。
- 发布完成后检查 GitHub Release 和 Homebrew 两种安装方式，确保 README 中的命令仍然可用。
