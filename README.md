# MultiWechat

一款原生 macOS 微信多开助手。它为每个微信分身创建独立 App、Bundle ID 和数据容器，并在微信更新后自动重建分身。

<p align="center">
  <img src="assets/WxMultiIcon-1024.png" width="220" alt="MultiWechat 图标">
</p>

## 功能

- 原生 Swift + AppKit 菜单栏界面
- 创建、启动、显示、关闭、更新和销毁多个微信分身
- 每个分身使用独立数据目录，登录状态和聊天缓存互不混用
- 微信更新后，启动分身时自动检测并重建
- 查看每个实例的数据占用和登录过的账号标识
- 空闲时不轮询进程、不扫描磁盘

## 安装

1. 从 [Releases](https://github.com/GiZGY/MultiWechat/releases/latest) 下载 `MultiWechat-<版本>.dmg`。
2. 打开 DMG，将 `MultiWechat.app` 拖入 `Applications`。
3. 首次启动后，点击菜单栏中的 MultiWechat 图标创建分身。

当前公开构建为 ad-hoc 签名版本。首次打开时如 macOS 提示无法验证开发者，请在访达中右键 `MultiWechat.app`，选择“打开”。项目尚未完成 Apple 公证。

要求：macOS 13 或更高版本，并已在 `/Applications` 安装官方微信。

## 使用

- `新建`：预填一个可修改的分身名称，创建后自动启动。
- `启动 / 显示`：启动分身，或将正在运行的对应微信窗口切到前台。
- 展开实例：查看账号、数据占用以及关闭、更新、访达、数据、清除和销毁操作。
- `更新`：从当前官方微信重新构建分身，保留原有独立数据目录。
- `销毁`：移除分身 App 和 MultiWechat 的实例记录，不删除聊天数据。
- `清除`：清除该分身的数据目录，需要在实例关闭后二次确认。

分身 App 位于 `~/Applications/WxMulti/`，本机配置位于 `~/Library/Application Support/WxMulti/`。这些内容不会写入仓库。

## 已知限制

- 视频号视频和部分小程序视频卡片在分身中可能无法打开；普通网页、PDF 和 Office 文件链路已可用。
- 微信升级可能改变内部结构。MultiWechat 会自动重建托管分身，但无法保证兼容未来所有微信版本。
- 当前 Release 未使用 Apple Developer ID 签名和公证。

## 开发

```bash
swift test
scripts/install-menu-app.sh
```

构建通用架构 Release：

```bash
scripts/build-release.sh 0.1.0
```

产物会写入 `dist/`。CLI 与实验性硬多开入口见 [CLI 文档](docs/CLI.md)，架构决策见 [ADR](docs/adr/)。

## 隐私与边界

MultiWechat 只在本机管理微信 App 副本和隔离容器，不读取聊天正文，不上传账号、聊天、二维码或本机配置，也不提供防撤回、抢红包或自动化聊天功能。

MultiWechat 是独立开源项目，与腾讯或微信无隶属、合作或认可关系。“微信”和“WeChat”是其各自权利人的商标。

## 贡献

提交代码前请阅读 [CONTRIBUTING.md](CONTRIBUTING.md)。安全问题请按 [SECURITY.md](SECURITY.md) 中的方式报告。

## 许可证

[MIT](LICENSE)
