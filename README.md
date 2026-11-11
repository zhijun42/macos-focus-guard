# macOS Focus Guard

macOS Focus Guard 是一组本地运行的专注保护工具。它不联网，不收集数据，通过 LaunchAgent 在后台执行约束。

仓库包含两个彼此独立、共享底层能力的守卫：

- **OperaGuard**：每次打开 Opera 前设定使用时长，记录当天累计使用时间和开启轮数；Opera 退出后进入 30 分钟冷却。
- **FocusGuard**：在固定时间窗口内阻止指定应用运行，适合保护睡前和早晨的专注时间。

> 守卫会先请求应用正常退出；应用没有响应时可能会被强制终止。请先保存正在编辑的内容。

## 要求

- macOS 13 或更高版本
- Xcode 或 Command Line Tools
- OperaGuard 需要 `/Applications/Opera.app`

## 安装 OperaGuard

请先退出 Opera，然后运行：

```sh
./scripts/install-opera-guard.sh
```

为了兼容此前的用法，`./scripts/install.sh` 等价于上面的命令。安装完成后，从 `~/Applications` 打开 **The Opera**。

每轮的截止时间在启动时确定。观看中再次打开 The Opera 会显示剩余时间。Opera 主动退出或到点退出后都会进入冷却；跨午夜的使用时长按本机日期拆分，开启次数记在启动当天。

统计保存在本机的：

```text
~/Library/Application Support/The Opera/state.json
```

## 安装 FocusGuard

默认保护窗口为 `22:30–10:30`，默认阻止微信、Opera、The Opera 启动器和照片：

```sh
./scripts/install-focus-guard.sh
```

可以在安装命令中覆盖时间和应用列表：

```sh
FOCUS_START=23:00 \
FOCUS_END=09:30 \
FOCUS_APPS=com.tencent.xinWeChat,com.operasoftware.Opera \
./scripts/install-focus-guard.sh
```

时间使用本机时区和 `HH:MM` 格式。开始时间晚于结束时间时，窗口自动跨越午夜。开始与结束相同时，保护窗口关闭。

应用使用 bundle identifier 标识。可以通过下面的命令查询一个应用：

```sh
mdls -name kMDItemCFBundleIdentifier /Applications/Example.app
```

## 临时停用与恢复 FocusGuard

```sh
launchctl bootout "gui/$(id -u)/com.zhijun.focus_guard"
launchctl bootstrap "gui/$(id -u)" "$HOME/Library/LaunchAgents/com.zhijun.focus_guard.plist"
```

## 卸载

卸载脚本不会直接删除文件，而是把程序和 LaunchAgent 移到带时间戳的备份目录：

```sh
./scripts/uninstall.sh focus
./scripts/uninstall.sh opera
./scripts/uninstall.sh all
```

状态和日志会保留在 Application Support 中。

## 开发

这是一个 Swift Package，包含两个 executable product、两个业务模块和共享的 `GuardCore`：

```text
Sources/
├── GuardCore/
├── OperaGuardKit/
├── OperaGuard/
├── FocusGuardKit/
└── FocusGuard/
```

运行项目完整测试，包括 Swift 单元测试和真实图形会话中的 OperaGuard 集成测试：

```sh
./scripts/test.sh
```

单独构建两个命令行程序：

```sh
swift build -c release --product opera-guard
swift build -c release --product focus-guard
```

## 隐私

所有配置、状态和日志都保存在本机。项目没有遥测、分析服务或网络请求。

## License

[MIT](LICENSE)
