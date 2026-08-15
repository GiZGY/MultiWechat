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

`Release` workflow 会验证标签与 Changelog，运行测试，构建 Apple Silicon 与 Intel 通用架构的 DMG/ZIP，生成 SHA-256 校验文件，并发布 GitHub Release。

默认公开构建使用 ad-hoc 签名。具备 Developer ID 与公证凭据时，可在可信本机环境通过 `CODESIGN_IDENTITY` 和 `NOTARY_PROFILE` 调用 `scripts/build-release.sh`；签名证书和公证凭据不得写入仓库或 GitHub Actions 日志。
