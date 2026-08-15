# Contributing

感谢你帮助改进 MultiWechat。

提交贡献即表示你同意贡献内容按项目的 MIT License 发布，并遵守 [Code of Conduct](CODE_OF_CONDUCT.md)。

## 开发环境

- macOS 13 或更高版本
- Xcode Command Line Tools
- Swift 6.0 或更高版本
- 官方微信安装在 `/Applications/WeChat.app`

## 提交前检查

```bash
swift test
swift build -c release
```

涉及菜单界面或实例操作时，还应安装本地构建并实际验证对应交互：

```bash
scripts/install-menu-app.sh
```

请勿提交微信账号、容器数据、聊天文件、二维码、日志、签名证书或本机配置。改动应保持单一目的，并为可独立测试的逻辑补充测试。

## Pull Request

1. Fork 仓库，从最新 `main` 创建单一目的的主题分支。
2. 保持提交可审查，不混入构建产物、格式噪声或无关重构。
3. 推送到自己的 Fork 并创建 Pull Request，完整填写模板。
4. 等待必需 CI 通过和 CODEOWNER 审核；新的提交会使旧审核失效。
5. 维护者通过 squash 或 rebase 合并，合并后删除主题分支。

外部贡献者不需要、也不会获得 Release 权限。版本标签和 Release 只由维护者从受保护的 `main` 创建。

## 兼容性问题

报告微信版本兼容问题时，请提供 macOS 版本、Mac 芯片类型、微信版本、MultiWechat 版本、复现步骤和不含账号信息的错误现象。不要上传微信数据目录或聊天数据库。
