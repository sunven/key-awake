# KeyAwake

A macOS utility that keeps a Bluetooth LE keyboard on a low-latency link. It runs as two processes: the interface for settings and status, and the engine that holds the link.

## Language

### Processes

**Engine**:
The resident background process that holds the keyboard's link and requests low latency. It outlives the window.
_Avoid_: agent, daemon, background service

**Interface**:
The process with the window for settings and status. Closing it stops nothing.
_Avoid_: app, UI

### Link

**Link**:
The Bluetooth LE connection between the Mac and a keyboard.

**Boost**:
Keep the link held with low latency requested, so the keyboard reacts immediately.
_Avoid_: wake, turbo

**Release**:
Drop the link so macOS returns the keyboard to its power-saving profile.

**Idle**:
Keyboard inactivity, measured system-wide. After the configured period the engine releases.

**Latency level**:
One of three measured connection profiles: fastest, balanced, lowest power. The lowest-power level is worse than the macOS 27 fault.

### Devices

**Device identity**:
A keyboard the user boosts, represented as one name plus every hardware address seen for it. An address match is definitive; a name match applies only when none of the identity's aliases is live.
_Avoid_: device record, entry

**Alias**:
One of the hardware addresses belonging to a device identity.

**Live device**:
A device visible through CoreBluetooth right now.

**Absent device**:
A device identity with no live address. It is still listed because it remains configured.

**Wanted**:
The engine's verdict that a live device is one the user asked for.

**Boosted**:
The link is held and running at the requested latency. Only a live, wanted keyboard can be boosted.

**Learned identity**:
An address or real name the engine adds to an existing device identity after seeing the two together.

### Link health

**Signal (RSSI)**:
Signal strength in dBm, read only while the link is held.

**Packet loss**:
Share of the keyboard's packets the Mac failed to receive, measured from bluetoothd link statistics over a window.

**Radio drop**:
One transition of the Bluetooth radio out of the on state, counted per hour.

**Link health**:
The verdict — good, fair, poor, unknown — derived from signal, packet loss, and radio drops.

**History**:
The per-minute record of link health that lets an intermittent fault leave a trace.

### Policy

**Tick**:
One periodic evaluation by the engine: observe devices, decide, apply, publish.

**BoostPolicy**:
The module that turns a settings snapshot and the live devices into one decision: wanted devices, boost or release actions, learned identities, status rows, and which samples are due.
_Avoid_: rules engine, controller

**Decision**:
The value BoostPolicy returns for one tick.

**Policy state**:
The facts BoostPolicy carries from one tick to the next: when boosting began, when signal and history were last sampled, and the names known for absent devices.
