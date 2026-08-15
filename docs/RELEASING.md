# Release Process

Release 由仓库维护者执行。版本号遵循 `MAJOR.MINOR.PATCH`，标签格式为 `vMAJOR.MINOR.PATCH`。

## 发布前

1. 更新 `CHANGELOG.md`，添加与版本号完全一致的标题。
2. 在 PR 中通过必需的 `test` 检查并合并到受保护的 `main`。
3. 确认工作区干净，版本提交已经位于 `origin/main`。

## 发布

```bash
git tag -a v0.2.0 -m "MultiWechat 0.2.0"
git push origin v0.2.0
```

`Release` workflow 会验证标签来自 `main` 且 Changelog 已更新，随后在只读 job 中运行测试、构建 Apple Silicon 与 Intel 通用架构的 DMG/ZIP，并生成 SHA-256 校验文件。构建完成后，需要维护者在 GitHub `release` 环境中批准，独立的发布 job 才会获得临时写权限并创建 Release。

默认公开构建使用 ad-hoc 签名。具备 Developer ID 与公证凭据时，可在可信本机环境通过 `CODESIGN_IDENTITY` 和 `NOTARY_PROFILE` 调用 `scripts/build-release.sh`；签名证书和公证凭据不得写入仓库或 GitHub Actions 日志。

需要验证打包链路而不发布版本时，在 GitHub Actions 中手动运行 `Release` workflow 并填写一个已存在于 Changelog 的版本号。该模式只执行只读构建并保留 7 天 Artifact，不进入发布环境，也不会创建或覆盖 Release。
