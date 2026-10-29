<p align="center">
  <img src="docs/icon.png" width="118" alt="KeyAwake">
</p>

<h1 align="center">KeyAwake</h1>

<p align="center">
  <a href="README.md">English</a> · <b>简体中文</b>
</p>

<p align="center">
  <b>修复 macOS 27 引入的蓝牙 LE 键盘延迟。</b><br>
  把链路最坏情况从 345 毫秒降到约 30 毫秒。
</p>

<p align="center">
  <img src="https://img.shields.io/badge/macOS-27%2B-000?logo=apple&logoColor=white" alt="macOS 27+">
  <img src="https://img.shields.io/badge/Swift-5-F05138?logo=swift&logoColor=white" alt="Swift 5">
  <img src="https://img.shields.io/badge/license-MIT-blue" alt="MIT">
</p>

---

## 问题

如果你的蓝牙键盘在升级到 macOS 27 后变得异常迟钝，原因多半就在这里。

macOS 27 围绕 **LE Connection Subrating**（蓝牙 5.3 的一项特性）重做了 LE 键盘的电源管理。它给键盘下发一个 `peripheralLatency: 22` 的配置——意思是键盘可以静默最长 **345 毫秒**——然后立刻尝试用 subrating 抵消它，让键盘在任何活动之后保持监听。

这个方案本身合理，只是在不支持蓝牙 5.3 的硬件上会失败：

```
setConnectionLatency LEHID-15ms to device "…"
update: minInterval:15.000 maxInterval:15.000 peripheralLatency:22 …

Proceeding with sending connection subrating parameters:
  subrateMin:1 subrateMax:6 maxLatency:1 continuationNumber=1
Remote Features: FF 79 2D 04 9E 03 00 00 … SupportsSubrating: 0
Remote device does not support connection subrating. (status=65535)
Failed to enter Connection Subrating Mode … Status=1330
```

subrating 请求失败了——**而且没有任何东西会回滚那 345 毫秒。** 键盘就此被困住。

键盘甚至会向 macOS 请求更好的参数（7.5–12.5 毫秒），却被拒绝：

```
Rejecting following parameters: min=6, max=10, lat=5, mul=50, cel=4, preferredLowLatencyInterval=0
```

macOS 里没有任何设置可以修复这个问题。

## 修复方式

一个持有连接并请求低延迟的 CoreBluetooth 客户端会强制 `peripheral latency: 0`。KeyAwake 就是那个客户端。它在后台安静运行，你不打字时就退场。

**KeyAwake 只处理键盘。** 如果同时为指针设备请求低延迟——比如同一套键鼠——macOS 27.0.1 的 HID 层会在下一次参数更新时重新套用键盘的空闲配置（latency 44）。键盘手感会立刻回到修复前，而应用仍然报告它处于加速状态。指针设备交给 macOS 管理，不会出现在设备列表里。

<p align="center">
  <img src="docs/screenshot.png" width="620" alt="KeyAwake 窗口">
</p>

<p align="center">
  <sub>支持英语、西班牙语和简体中文，跟随系统语言 —
  <a href="docs/screenshot-es.png">西班牙语</a>。</sub>
</p>

## 安装

**下载最新 release**，打开 `.dmg`，把 `KeyAwake.app` 拖进 Applications。后台引擎已内置于应用中——无需安装任何其他东西。也提供 `.zip` 版本。

由于应用未公证，macOS 会拒绝首次启动。右键点击应用并选择 **打开**，然后确认。只需操作一次。如果 macOS 仍然拦截：

```sh
xattr -dr com.apple.quarantine /Applications/KeyAwake.app
```

然后打开 KeyAwake，勾选你的键盘，并开启 **登录时启动**。就这些。

**或者自行构建**——推荐，见[构建](#构建)。本地构建的副本用你自己的证书签名，macOS 不会再反复询问蓝牙权限。

## 权限

**仅蓝牙，只需授权一次，且只给引擎。** 这就是全部。

KeyAwake **不**申请辅助功能或输入监控。空闲检测使用 `CGEventSourceSecondsSinceLastEventType`，这是系统级空闲计数器，而非事件监听。它看不到你输入的内容，项目中也完全没有网络代码。

## 延迟级别

在 macOS 27.2 上实测，而非估算——这些是 `bluetoothd` 实际协商出的参数：

| 设置 | 间隔 | 外设延迟 | 最坏情况 |
|---|---|---|---|
| **最快**（默认） | 10–30 毫秒 | 0 | **约 30 毫秒** |
| 均衡 | 100–120 毫秒 | 1 | 约 240 毫秒 |
| 最低功耗 | 290–320 毫秒 | 1 | 约 640 毫秒 |

> 注意 **最低功耗比这个 bug 本身还慢**（345 毫秒）。它存在的唯一意义是你更在意电量而非打字手感。选择时应用会给出警告。

## 电池

把链路保持在延迟 0 意味着键盘每 30 毫秒监听一次，这会耗电。所以 KeyAwake 在一段时间没有输入后释放链路（默认 3 分钟），并在下一次按键时重新抓住它。

代价是：**空闲后的第一次按键会迟到**，之后一切即时。如果宁愿永远不见到这次迟到，把 *空闲多久后释放* 设为 **永不释放**。

## 仍然感觉慢的时候

KeyAwake 每分钟记录一次链路健康状况——信号强度、数据包丢失，以及蓝牙无线电掉线的频率——写入 `~/Library/Application Support/KeyAwake/link-history.csv`。窗口会显示当前读数，并用一行文字说明哪里出了问题。

之所以需要它，是因为硬故障是间歇性的。一小时后靠快照诊断，只会归咎于期间恰好变动的东西——这正是你冤枉一个无辜 USB 扩展坞的常见方式。开发期间出现了三种不同的原因，只有历史记录能把它们区分开：

| 现象 | 含义 |
|---|---|
| 一小时内**无线电断开**很多次 | Mac 反复休眠并重启蓝牙。检查 `pmset -g custom`；电池供电下的 `sleep 1` 会导致这种情况。 |
| **丢包**高但信号不错 | 附近有设备在 2.4 GHz 频段发送信号。 |
| **信号**弱（低于 −70 dBm） | 距离过远或有遮挡。 |
| 三项都正常，仍然慢 | 问题不在链路。与你 Mac 内置键盘对比一下。 |

## 工作原理

两个 bundle。`KeyAwake.app` 是界面——打开、修改设置、关闭，它就从 Dock 消失。作为登录项嵌套其中的 `KeyAwakeAgent.app` 是持续运行的引擎。可选的菜单栏图标属于引擎，隐藏它不会丢失任何功能。

设备以**硬件地址而非 CoreBluetooth UUID** 记住，重新配对键盘或切换蓝牙槽位都不会破坏你的配置。

完整说明，包括涉及的三组私有 selector 以及公共发现 API 为什么什么都返回不了：**[docs/DESIGN.md](docs/DESIGN.md)**。

## 构建

需要 Xcode Command Line Tools。

```sh
git clone https://github.com/sunven/key-awake.git
cd key-awake
./build.sh
```

`build.sh` 会从 `security find-identity -v -p codesigning` 中挑选任意代码签名身份，否则回退到 ad-hoc。用真实身份签名可以避免 macOS 在每次重新构建后反复询问蓝牙权限。

## 卸载

```sh
launchctl bootout gui/$(id -u)/com.keyawake.agent
rm -f ~/Library/LaunchAgents/com.keyawake.agent.plist
rm -rf /Applications/KeyAwake.app ~/Library/Application\ Support/KeyAwake
```

## 注意事项

- **使用私有 CoreBluetooth API。** 公开途径无法做到这一点。每次调用都用 `responds(to:)` 保护，所以未来移除这些 API 的 macOS 只会让 KeyAwake 停止生效，而不是崩溃——但它确实会停止生效。
- **仅支持键盘。** 同时为指针设备请求低延迟会让键盘在 27.0.1 上被交还给 macOS 的空闲配置；见[修复方式](#修复方式)。
- **为 macOS 27 构建。** 它规避的 bug 在更早版本中不存在。
- **未公证。** 见[安装](#安装)。

## 参与贡献

翻译是最简单的贡献方式：把 `Resources/en.lproj/Localizable.strings` 复制到新的 `<language>.lproj`，翻译右侧内容，并把语言代码加入 `build.sh` 的 `CFBundleLocalizations`。应用目前提供英语、西班牙语和简体中文。

## 致谢

KeyAwake 是 [Leonardo Fundora](https://github.com/leonardofundora) 的 [KeyBoost](https://github.com/leonardofundora/KeyBoost) 的重写版本。原项目确立了 macOS 27 subrating bug 的诊断，以及本应用赖以构建的 CoreBluetooth 变通方案；KeyAwake 将其重构为更小、可测试的模块，并扩展了上述链路历史与诊断功能。原始版权声明予以保留。

## 许可证

MIT — 见 [LICENSE](LICENSE)。版权声明归 KeyBoost 原作者 Leonardo Fundora 所有。
