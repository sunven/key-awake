# KeyAwake — design notes

## The bug

macOS 27 assigns Bluetooth LE keyboards a connection profile named `LEHID-15ms`, which carries
`peripheralLatency: 22`. With a 15 ms connection interval, that lets the peripheral stay silent for
up to `15 × 23 = 345 ms`.

That would be harmless, because macOS immediately tries to override it with **LE Connection
Subrating** (a Bluetooth 5.3 feature). Straight from `bluetoothd`:

```
setConnectionLatency LEHID-15ms to device "<redacted>"
update: minInterval:15.000 maxInterval:15.000 peripheralLatency:22 minCE=4 maxCE=4 timeout:2000

Proceeding with sending connection subrating parameters:
  subrateMin:1 subrateMax:6 maxLatency:1 continuationNumber=1
Remote Features: FF 79 2D 04 9E 03 00 00 ... SupportsSubrating: 0
Remote device does not support connection subrating. (status=65535)
Failed to enter Connection Subrating Mode ... Status=1330
```

With `continuationNumber=1`, subrating would keep the peripheral listening on consecutive events
right after any activity — instant typing, power saving only while idle. That is a sound design.

**But the keyboard is older than Bluetooth 5.3, the subrating request fails, and nothing rolls back
the `peripheralLatency: 22`.** The device is left stranded with the raw 345 ms window.

On subrating-capable peripherals nobody notices. On everything older, typing becomes unusable.

The keyboard even asks for better parameters and is refused:

```
Rejecting following parameters: min=6, max=10, lat=5, mul=50, cel=4, preferredLowLatencyInterval=0
```

That request is 7.5–12.5 ms with a latency of 5 — roughly 75 ms worst case.

No user-facing setting fixes this. The full key table of `com.apple.Bluetooth` and the
`LeConnectionLatency{Low,Medium,High,VeryHigh}` overrides were checked; none covers LE HID
peripheral latency.

## The fix

A CoreBluetooth client that holds the connection and asks for low latency forces
`peripheral latency: 0`:

```objc
[central setDesiredConnectionLatency:0 forPeripheral:peripheral];
```

This only holds **while that client stays connected**. Release the connection and `bluetoothd`
reverts to its own profile. Hence a resident process.

## Private API

Three selectors, each guarded with `responds(to:)` so the app degrades instead of crashing if Apple
removes them. See `Sources/Agent/CBPrivate.swift`.

| Selector | Why |
|---|---|
| `setDesiredConnectionLatency:forPeripheral:` | Forces `peripheral latency: 0`. This is the fix. |
| `retrieveConnectedPeripheralsWithServices:allowAll:` | Discovery. The public filter by service `0x1812` (HID over GATT) returns **0** results — macOS does not cache GATT for the HID link on behalf of third-party clients. Empty service list plus `allowAll: YES` works. |
| `retrieveAddressForPeripheral:` | Returns the 6-byte hardware address. Devices are stored **by address, not by CoreBluetooth UUID**, so re-pairing or switching Bluetooth slots does not break your configuration. |

## Architecture

Two bundles, because the UI must be closable without stopping the fix.

| | `KeyAwakeAgent.app` | `KeyAwake.app` |
|---|---|---|
| Role | engine | interface |
| Dock | no (`LSUIElement`) | yes |
| Lifetime | always, via LaunchAgent | only while you use it |
| Menu bar icon | owns it, when enabled | — |

They communicate through `~/Library/Application Support/KeyAwake/{settings,status}.json` plus
Darwin notifications. The agent also re-reads settings when the file's modification date changes,
so hand-editing the JSON works too.

### BoostPolicy

The engine's rules live in `Sources/Policy/BoostPolicy.swift`, not in `AgentController`.
`BoostPolicy.decide(_:_:)` is a pure function: settings, live devices, their kinds, which
addresses are connected, idle time and the current instant go in; one `Decision` comes out —
boost/release actions, learned identities, the status rows, which samples are due, and the
state for the next tick. Live devices are mapped to `ObservedDevice`, so CoreBluetooth stays
out of the module. The controller supplies the snapshot, applies the actions, persists learned
identities once, and publishes.

Change a boost rule here, and test it through the same interface: `swift test` runs
`Tests/PolicyTests` without Bluetooth hardware or a running app.

### Settings commands

The engine is the only writer of `settings.json`. The interface sends a `SettingsCommand`
(enable, menu bar icon, latency, idle release, start device, forget device) over a Darwin
notification; the engine applies it once, saves, and broadcasts `settingsChanged`. The
interface updates its own copy optimistically with the same `Settings.apply(_:)`, so the
window reacts at once; the engine's broadcast is authoritative.

If the engine is not running, the interface writes the file directly: with no second writer
there is nothing to race. A hand-edited file is still picked up by the engine's
modification-date check, which then broadcasts the change back to the interface.

## State machine

```
IDLE ──(input activity)──► BOOSTED
  ▲                            │
  └──(N seconds idle │ Mac sleeps │ disabled)──┘

BOOSTED = connectPeripheral + setDesiredConnectionLatency(level)
IDLE    = cancelPeripheralConnection
```

Activity comes from `CGEventSourceSecondsSinceLastEventType`, a system idle counter. **This is not
an event tap**: it reads no keystroke content and needs no Accessibility permission. The signal is
keyboard-only: `keyDown` and modifier changes. Pointing devices are not boosted; see below.

## Why pointing devices are left alone

On macOS 27.0.1, holding a low-latency connection to a keyboard and a pointing device at the same
time triggers bluetoothd's multi-HID power management. Right after the keyboard's low-latency
request, its HID layer logs:

```
LE Connection Interval(30.00 ms) Latency(0) ... is not preferred. Adjust HID Sniff Interval.
setConnectionLatency LEHID-7.5msCE4 to device "…"
  minInterval:7.500 maxInterval:7.500 peripheralLatency:44
```

The keyboard is back at a 345 ms worst case in about 0.4 seconds. Repeating the request repeats
the override, so a shorter refresh interval does not help. Releasing the pointing device makes the
keyboard stay at latency 0 indefinitely.

KeyAwake therefore handles keyboards only. Pointing devices are left entirely to macOS and do not
appear in the device list. `CBConnectOptionLatencyCritical` was
tried as a way to keep both; bluetoothd still applied the HID profile, so it is not used.

## Latency levels

Measured on macOS 27.2, not estimated. These are the parameters `bluetoothd` negotiates:

| Level | Interval | `peripheralLatency` | Worst case |
|---|---|---|---|
| `low` | 10–30 ms | 0 | ~30 ms |
| `medium` | 100–120 ms | 1 | ~240 ms |
| `high` | 290–320 ms | 1 | ~640 ms |

Note that `high` is worse than the 345 ms bug this app exists to fix. The UI warns about that.

## Code signing matters

With **ad-hoc** signing, macOS re-prompts for Bluetooth permission intermittently after rebuilds:
TCC stores verifier data it cannot match without a certificate. `build.sh` therefore picks up any
code signing identity from `security find-identity -v -p codesigning` and falls back to ad-hoc.

A way to tell whether a dialog appeared, without watching the screen: the delay between
`engine started` and `bluetooth: on` in the log. 8–9 s means it waited for a click; 0–1 s means it
did not. Also note that `#ManagedTCCDefaults showing the prompt` lines in `tccd` appear either way —
the one that matters is `AUTHREQ_PROMPTING`.
