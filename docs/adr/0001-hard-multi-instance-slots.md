# ADR 0001: 命名硬多开槽位

状态：实验路线，已由 `0002-managed-isolated-instances.md` 取代为菜单默认路线。

## 背景

新版 macOS 微信在复制 App 并修改 `CFBundleIdentifier` 后，可能在扫码登录后提示“当前客户端版本过低”。硬多开路线保留官方 Bundle ID，只在副本主二进制中解除单实例限制，再用 `open -n -a` 启动额外进程。

## 决策

wxmulti 保留“命名硬多开槽位”作为实验 CLI 路线：

- 原版 `/Applications/WeChat.app` 不修改。
- 每个命名槽位复制一个 App 副本。
- 副本保留 `com.tencent.xinWeChat`。
- 副本写入已知构建号对应的单实例补丁。
- 副本可设置 `CFBundleName` / `CFBundleDisplayName`，用于 Finder、菜单和本机辨识。
- 槽位配置写入 `~/Library/Application Support/WxMulti/hard-instances.json`。
- 默认命名槽位 App 放在 `~/Applications/WxMulti/Hard/`。

## 备选方案

1. 复制 App 并修改 Bundle ID。
   - 优点：macOS 层面更容易区分 App。
   - 缺点：新版微信可能登录后提示版本过低，且客户端身份差异更大。

2. 只维护单个 `/Applications/WeChatPatched.app`。
   - 优点：实现简单。
   - 缺点：无法管理多个命名分身，不利于长期使用和开源。

3. 虚拟机或容器化桌面。
   - 优点：隔离强。
   - 缺点：资源开销大，不适合作为轻量菜单工具。

## 取舍

保留官方 Bundle ID 能提高与微信客户端身份的一致性，但 macOS 和微信自己的状态栏菜单可能会把多个实例视为同类应用。该路线依赖具体构建号，微信更新后需要重新验证补丁地址，因此不再作为菜单默认路径。

## 回滚

- 销毁命名槽位记录：`swift run wxmulti hard-remove <id>`。
- 同时销毁 App 副本：`swift run wxmulti hard-remove <id> --delete-app`。
- 默认第二微信副本可用 `swift run wxmulti destroy-patched` 销毁。
- 原版微信不被修改，无需还原原版 App。

## 验证

- `swift build`
- `swift test`
- `swift run wxmulti patch-status`
- `swift run wxmulti hard-list`
- `swift run wxmulti patched-runtime-status`
