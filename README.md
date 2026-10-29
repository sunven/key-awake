<p align="center">
  <img src="docs/icon.png" width="118" alt="KeyAwake">
</p>

<h1 align="center">KeyAwake</h1>

<p align="center">
  <b>English</b> · <a href="README.zh-CN.md">简体中文</a>
</p>

<p align="center">
  <b>Fixes the Bluetooth LE keyboard lag introduced in macOS 27.</b><br>
  Brings the link from a 345 ms worst case down to ~30 ms.
</p>

<p align="center">
  <img src="https://img.shields.io/badge/macOS-27%2B-000?logo=apple&logoColor=white" alt="macOS 27+">
  <img src="https://img.shields.io/badge/Swift-5-F05138?logo=swift&logoColor=white" alt="Swift 5">
  <img src="https://img.shields.io/badge/license-MIT-blue" alt="MIT">
</p>

---

<p align="center">
  <img src="docs/screenshot.png" width="620" alt="KeyAwake window">
</p>

## What it does

macOS 27 manages LE keyboards around **LE Connection Subrating**. It assigns a profile with
`peripheralLatency: 22` — up to **345 ms** between key presses — and relies on subrating to cancel
that out. On hardware older than Bluetooth 5.3 the request fails, nothing rolls the latency back,
and the keyboard feels sluggish. No macOS setting fixes it.

KeyAwake is a small CoreBluetooth client that holds the connection at latency 0. It releases the
link after a period without typing (3 minutes by default) to save battery, and takes it back on
your next keystroke — that first key after idle arrives a little late.

**Keyboards only.** Requesting low latency for a pointing device as well makes the keyboard fall
back to its idle profile on macOS 27.0.1, so pointing devices are left to macOS.

## Install

Download the latest release, open the `.dmg`, and drag `KeyAwake.app` into Applications. Then tick
your keyboard and enable **Start at login**.

The app is not notarised, so the first launch needs **right-click → Open**. If macOS still blocks it:

```sh
xattr -dr com.apple.quarantine /Applications/KeyAwake.app
```

Or build it yourself (see [Building](#building)) — a copy signed with your own certificate stops
macOS re-asking for Bluetooth permission.

## Permissions

Bluetooth only, requested once by the background engine. No Accessibility or Input Monitoring: idle
detection uses `CGEventSourceSecondsSinceLastEventType`, a system-wide idle counter, not an event
tap. There is no network code.

## Latency levels

Measured on macOS 27.2 — the parameters `bluetoothd` actually negotiates:

| Setting | Interval | Peripheral latency | Worst case |
|---|---|---|---|
| **Fastest** (default) | 10–30 ms | 0 | **~30 ms** |
| Balanced | 100–120 ms | 1 | ~240 ms |
| Lowest power | 290–320 ms | 1 | ~640 ms |

> **Lowest power is slower than the bug itself** (345 ms). The app warns you when you pick it.

## Troubleshooting

The app records signal strength, packet loss and radio drops every minute to
`~/Library/Application Support/KeyAwake/link-history.csv`, and shows the current reading in the window.

| Symptom | Likely cause |
|---|---|
| Many radio drops in an hour | The Mac keeps sleeping and cycling Bluetooth — check `pmset -g custom`. |
| High packet loss, decent signal | 2.4 GHz interference nearby. |
| Weak signal (below −70 dBm) | Distance or an obstruction. |
| All fine, still slow | Not the link — compare with the built-in keyboard. |

## How it works

`KeyAwake.app` is the interface; `KeyAwakeAgent.app`, nested inside it as a login item, is the
engine that keeps running. Devices are remembered by hardware address rather than CoreBluetooth
UUID, so re-pairing does not break your settings.

Design notes, private API use and caveats: **[docs/DESIGN.md](docs/DESIGN.md)**.

## Building

Requires Xcode Command Line Tools.

```sh
git clone https://github.com/sunven/key-awake.git
cd key-awake
./build.sh
```

`build.sh` uses a code signing identity when one is available and falls back to ad-hoc.

## Uninstall

```sh
launchctl bootout gui/$(id -u)/com.keyawake.agent
rm -f ~/Library/LaunchAgents/com.keyawake.agent.plist
rm -rf /Applications/KeyAwake.app ~/Library/Application\ Support/KeyAwake
```

## Caveats

- **Private CoreBluetooth API.** There is no public way to do this; every call is guarded with
  `responds(to:)`, so a future macOS makes KeyAwake stop working rather than crash.
- **Built for macOS 27.** The bug does not exist on earlier versions.
- **Not notarised.** See [Install](#install).

## Contributing

Translations are the easiest way to help: copy `Resources/en.lproj/Localizable.strings` to a new
`<language>.lproj`, translate the right-hand side, and add the language code to
`CFBundleLocalizations` in `build.sh`. The app ships English, Spanish and Simplified Chinese.

## Credits

A rewrite of [KeyBoost](https://github.com/leonardofundora/KeyBoost) by
[Leonardo Fundora](https://github.com/leonardofundora), which established the diagnosis and the
CoreBluetooth workaround. The original copyright notice is retained.

## License

MIT — see [LICENSE](LICENSE). Includes code from KeyBoost; its original copyright notice
(© Leonardo Fundora) is retained.
