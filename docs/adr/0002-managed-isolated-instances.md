# ADR 0002: 托管隔离分身作为菜单默认路线

状态：采用

## 背景

微信 4.1.9 构建号 `268624` 更新后，硬多开副本可以启动数秒但随后退出，说明单实例相关检查不止一处，且补丁地址会随构建变化。继续把硬补丁作为菜单默认能力，会让每次微信更新都变成逆向维护工作。

同时，托管隔离实例路线在本机验证通过：分身使用独立 Bundle ID、独立容器和启动参数镜像，原版微信保持运行，托管分身可稳定启动并保留独立进程身份。

## 决策

MultiWechat 菜单默认只管理 `instances.json` 中的托管隔离分身：

- 原版 `/Applications/WeChat.app` 不修改。
- 每个分身复制一个 App 到 `~/Applications/WxMulti/`。
- 每个分身使用独立 Bundle ID，例如 `com.tencent.xinWeChat.wxmulti.wechat.2`。
- 每个分身使用独立容器，互不共享登录目录和聊天目录。
- 启动前同步原版容器中的运行补丁、插件配置和版本策略文件。
- 启动包装器镜像原版微信运行时的 `client_version`、`UnifiedPCMacWechat` 和内部 bundle 参数。
- 菜单里的新建、启动、关闭、更新、访达、销毁全部走 `create/start/stop/rebuild/remove` CLI。

硬多开补丁命令保留为实验入口，但不显示在菜单中。

## 取舍

托管隔离路线不需要 patch 微信二进制，微信更新后的维护成本更低，也更适合开源。代价是分身 Bundle ID 与原版不同，因此必须同步运行版本参数，避免子进程或网络侧拿到过期客户端信息。

## 回滚

- 关闭分身：`swift run wxmulti stop <id>`。
- 销毁分身记录和 App：`swift run wxmulti remove <id> --delete-app`。
- 原版微信不被修改，无需还原原版 App。
- 如果实验硬补丁副本存在，可用 `swift run wxmulti destroy-patched` 移除。

## 验证

- `swift build`
- `swift test`
- `swift run wxmulti create wechat-2 --name 微信-2 --app-name 微信-2 --force --entitlements none`
- `swift run wxmulti start wechat-2`
- 观察 30 秒，原版 `/Applications/WeChat.app` 与分身 `~/Applications/WxMulti/微信-2.app` 同时保持运行。
- `swift run wxmulti stop wechat-2` 只关闭托管分身，原版微信保持运行。
