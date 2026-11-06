# The Opera

The Opera 是 macOS 上的 Opera 启动器。每次观看前设定时长，启动器会显示今天累计使用了多久、已经开启了几轮。

- 每轮的截止时间在启动时确定。观看中再次打开 The Opera 会显示剩余时间。
- Opera 退出后进入 30 分钟冷却。主动退出和到点退出都适用。冷却窗口显示最早可以再次开启的时间。
- 时长按浏览器从启动到退出计算，包含后台打开的时间。跨午夜的时长按本机日期拆分，开启次数记在启动当天。

## 安装

需要 macOS、Xcode 或 Command Line Tools，以及安装在 `/Applications/Opera.app` 的 Opera。请先退出 Opera，再从仓库根目录运行以下命令。

```sh
./scripts/install.sh
```

安装完成后，从 `~/Applications` 打开 **The Opera**。安装脚本会备份已有启动器和守卫，再加载新的 LaunchAgent。macOS 可能会提示新增名为 `opera-guard` 的后台项目。这个守卫负责记录退出、执行观看时限和冷却，并把统计保存在本机的 `~/Library/Application Support/The Opera/state.json`。

## 开发

`Sources/Launcher.applescript` 负责对话框。`Sources/OperaGuard.swift` 管理会话和统计，`Sources/main.swift` 提供启动器及 LaunchAgent 使用的命令入口。

运行隔离测试需要一个已登录的 macOS 图形会话。测试使用临时的后台应用和统计文件。

```sh
./scripts/test.sh
```
