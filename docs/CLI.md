# CLI

MultiWechat App 内置 `wxmulti` 命令行程序。源码开发时可通过 `swift run wxmulti` 调用。

## 托管隔离分身

```bash
swift run wxmulti doctor
swift run wxmulti create work --name 微信-工作
swift run wxmulti start work
swift run wxmulti list
swift run wxmulti rename work --name 微信-工作号
swift run wxmulti stop work
swift run wxmulti sync-runtime work
swift run wxmulti remove work --delete-app
```

托管分身是菜单栏 App 使用的默认路线。它不会修改 `/Applications/WeChat.app`，每个分身有独立 Bundle ID 和容器。`start` 会检查官方微信指纹，微信更新后自动重建分身。

默认签名模式为 `--entitlements none`。`isolated` 和 `preserve` 模式保留给持有适用开发者签名、并愿意自行验证权限兼容性的开发者。

## 实验性硬多开

```bash
swift run wxmulti patch-status
swift run wxmulti install-patched --name 微信-生活 --force
swift run wxmulti start-patched
swift run wxmulti stop-patched
swift run wxmulti destroy-patched
```

命名槽位：

```bash
swift run wxmulti hard-create life --name 微信-生活
swift run wxmulti hard-start life
swift run wxmulti hard-stop life
swift run wxmulti hard-remove life --delete-app
```

硬多开路线会修改微信副本中的单实例检查，仅支持代码内明确列出的构建号。未知版本会拒绝写入。这条路线不属于菜单栏 App 的稳定能力，使用前应完全退出相关微信进程并保留备份。

## 本机路径

```text
~/Applications/WxMulti/
~/Library/Application Support/WxMulti/instances.json
~/Library/Application Support/WxMulti/hard-instances.json
~/Library/Application Support/WxMulti/account-aliases.json
```

账号备注只保存在本机。运行资源同步不会复制登录目录、账号目录或聊天文件。
