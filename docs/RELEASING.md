# 发布指南

项目使用 `Resources/Info.plist` 管理版本号，`CHANGELOG.md` 记录变更。
GitHub Actions 负责构建、测试和生成安装包，成功后创建 Release 草稿。

## 发布已有草稿

如果目标版本的草稿和安装包已经存在，不需要重新运行工作流。

1. 打开仓库的 [Releases](https://github.com/Rachel-hw/bongocat/releases)，编辑目标版本的草稿。
2. 确认版本、标题和说明正确，附件包含 `.dmg` 和 `.dmg.sha256`。
3. 正式版本不要勾选 **Set as a pre-release**；需要作为默认下载版本时，勾选 **Set as latest release**。
4. 点击 **Publish release**。

也可以通过 GitHub CLI 发布已有草稿（将版本替换为目标版本）：

```sh
gh release edit v0.2.1 --repo Rachel-hw/bongocat --draft=false --prerelease=false --latest
```

发布 Release 不会改变仓库可见性。要让所有用户都能下载，仓库需要设为 Public。
正式版发布并设为 Latest 后，可以分享固定入口：
<https://github.com/Rachel-hw/bongocat/releases/latest>。

## 生成下一个版本

1. 将改动推送到 `main`，在 `CHANGELOG.md` 的 `Unreleased` 段记录用户可见的变更。
2. 打开 [Actions → Release](https://github.com/Rachel-hw/bongocat/actions/workflows/release.yml)，点击 **Run workflow**。
3. 选择 `main`，版本增量默认用 `patch`；`notes` 可以留空或补充说明。
4. 等待工作流成功。它会递增版本和构建号、提交变更、创建 `vX.Y.Z` tag，
   构建 Apple silicon / Intel 通用 DMG，并把安装包与校验文件上传到 Release 草稿。
5. 按上面的步骤检查并发布草稿。
6. 本地执行 `git pull --ff-only`，同步工作流生成的版本提交。

例如当前版本为 `0.2.1`，选择 `patch` 会生成 `0.2.2`。
每次重新运行 **Run workflow** 都会尝试创建新版本；若已有版本构建失败，
请在该次运行中使用 **Re-run failed jobs**，不要重新发起版本递增。

## 手动推送 tag

先更新 `Info.plist` 的版本和变更记录，提交并推送，再创建、推送对应的 `vX.Y.Z` tag。
工作流会自动打包并生成 Release 草稿；tag 必须匹配 `Info.plist` 中的版本。

## 签名与权限

安装包使用 ad-hoc 签名，不需要 Apple 证书或公证 Secrets。
GitHub 上的正式 Release 不等同于 Apple 公证；更新后也可能需要重新添加辅助功能授权。

工作流使用仓库自带的 `GITHUB_TOKEN`，发布作业需要 `contents: write`。
若 main 的分支保护禁止机器人直接提交版本，应改用版本 PR 流程。

参考：[GitHub 发布管理](https://docs.github.com/en/repositories/releasing-projects-on-github/managing-releases-in-a-repository)。
