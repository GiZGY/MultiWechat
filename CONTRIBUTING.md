# Contributing

感谢你帮助改进 MultiWechat。

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

## 兼容性问题

报告微信版本兼容问题时，请提供 macOS 版本、Mac 芯片类型、微信版本、MultiWechat 版本、复现步骤和不含账号信息的错误现象。不要上传微信数据目录或聊天数据库。
