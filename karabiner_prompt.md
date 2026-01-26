# Task: Optional Karabiner DriverKit VirtualHIDDevice keyboard backend + runtime fallback to CGEvent

## Context
GlassToKey currently emits keystrokes using CoreGraphics `CGEvent` posting via a single in-process dispatcher (`KeyEventDispatcher` → `CGEventKeyDispatcher`).

We want to optionally use **Karabiner-DriverKit-VirtualHIDDevice** as the *primary* output backend when:
1) The user explicitly enables it, and
2) The driver is installed and activated, and
3) The VirtualHID daemon is reachable (root-only socket + protocol).

If any of those conditions are false (or if the VirtualHID path errors at runtime), we must immediately fall back to the existing CGEvent path.

## Goals
- Add a **Keyboard Output Backend** abstraction with two implementations:
  - `VirtualHID` (Karabiner DriverKit VirtualHIDDevice via daemon)
  - `CGEvent` (existing behavior, always available)
- Choose backend at runtime with a clear preference order:
  - User enabled VirtualHID AND VirtualHID is healthy → use VirtualHID
  - Otherwise → use CGEvent
- Keep hot-path overhead minimal and predictable:
  - No repeated “is it installed?” checks during key dispatch
  - No per-keystroke filesystem probes
  - No per-keystroke process spawning
  - Prefer persistent connections and precomputed mappings

## Non-goals
- Do not bundle or sign DriverKit drivers ourselves.
- Do not silently auto-install Karabiner components.
- Do not rework the touch pipeline. This is strictly about the **output** stage.

---

## Constraints and Facts (important)
- Karabiner VirtualHID components live in standard locations when installed (examples include):
  - `/Library/Application Support/org.pqrs/Karabiner-DriverKit-VirtualHIDDevice`
  - `/Applications/.Karabiner-VirtualHIDDevice-Manager.app`
  - `/Library/Application Support/org.pqrs/tmp`
- Karabiner client apps send input events to `Karabiner-VirtualHIDDevice-Daemon` via a **UNIX domain socket**:
  - `/Library/Application Support/org.pqrs/tmp/rootonly/vhidd_server/*.sock`
- Command injection is restricted to **processes running with root privileges**.

(Implementation must respect these constraints.)

---

## Deliverables
1) **Backend abstraction** that allows switching between VirtualHID and CGEvent.
2) **VirtualHID implementation** that can be used when available:
   - Uses a persistent connection
   - Handles keyDown/keyUp and keyStroke
   - Translates `CGKeyCode` + `CGEventFlags` into the VirtualHID expected representation
3) **Runtime health detection** and **automatic fallback** on failure.
4) **User preference + UI**:
   - Toggle/selector in settings: “Keyboard Output: CGEvent (default) / VirtualHID (Karabiner)”
   - Status indicator: Installed? Activated? Daemon reachable? Currently in-use backend.
5) **Minimal instrumentation** (debug-only) for backend switching events.

---

## Architecture

### A. Public API inside GlassToKey
Introduce a small, stable interface used by the touch pipeline:

- `KeyboardOutputDriver` (or reuse/extend existing `KeyDispatching`)
  - `postKeyStroke(code: CGKeyCode, flags: CGEventFlags, token: RepeatToken? = nil)`
  - `postKey(code: CGKeyCode, flags: CGEventFlags, keyDown: Bool, token: RepeatToken? = nil)`

The touch pipeline (e.g., `ContentViewModel.TouchProcessor`) should continue calling `KeyEventDispatcher.postKeyStroke/postKey` unchanged.

### B. KeyEventDispatcher refactor
Refactor `KeyEventDispatcher` from:
- `private let dispatcher: KeyDispatching` fixed to CGEvent

to:
- A runtime-selectable backend:
  - `private var dispatcher: KeyDispatching`
  - `private var backendState: BackendState` (healthy/unhealthy + reason)
  - `func reconfigureBackendIfNeeded()` called only on:
    - app start
    - settings change
    - explicit “Recheck” button
    - background slow timer (optional, low frequency, e.g. every 2-5 seconds only while VirtualHID is enabled but unhealthy)

**Hot-path requirement**
- The key dispatch call site must be a single virtual call into `dispatcher.*` with no additional branching.
- If switching is needed, swap the `dispatcher` reference atomically/serially on a configuration queue.

### C. Implementations

#### 1) CGEvent backend (existing)
Keep current implementation as-is.

#### 2) VirtualHID backend (new)
Because VirtualHID command injection requires root privileges and uses a daemon + socket protocol, implement VirtualHID output using one of these strategies:

**Preferred (recommended): Privileged helper + XPC**
- Add a separate helper executable:
  - Runs as root (installed via SMJobBless or equivalent).
  - Maintains the connection to `vhidd_server` socket(s).
  - Uses Karabiner’s client library or implements the daemon protocol exactly.
- Main app (user session) talks to helper via XPC:
  - Keep messages tiny and binary-friendly.
  - Maintain a persistent XPC connection.
  - Provide “sendKeyStroke” and “sendKey” calls.
  - Consider batch messages: send both down+up in a single IPC for strokes.

**Fallback (only if you accept running the whole app as root): direct socket from app**
- Not recommended for UX/security.
- Only mention in docs; do not default to it.

##### VirtualHID translation layer
VirtualHID expects HID-style semantics (usage page, usage, values, modifiers).
Implement a translation layer:
- Map `CGKeyCode` to HID usage (Keyboard/Keypad page).
- Map `CGEventFlags` to modifier usages (left/right shift/control/option/command).
- Support:
  - key down
  - key up
  - key stroke (down then up)

Precompute and store mappings in static tables:
- `[UInt16]` or fixed arrays for keycode→usage
- bitmask transforms for flags→modifier usages

No allocations per event.

---

## Availability and Health Checks

### Installation check (fast, not on hot path)
Performed at startup and when user opens settings panel or toggles VirtualHID.

Check existence of key paths:
- `/Library/Application Support/org.pqrs/Karabiner-DriverKit-VirtualHIDDevice`
- `/Applications/.Karabiner-VirtualHIDDevice-Manager.app` (optional indicator)
- `/Library/Application Support/org.pqrs/tmp/rootonly/vhidd_server/` (directory exists)

### Daemon reachability check
From the helper:
- Enumerate `/Library/Application Support/org.pqrs/tmp/rootonly/vhidd_server/*.sock`
- Attempt connect + protocol handshake once.
- Cache result in helper and expose status via XPC:
  - `.healthy`
  - `.unreachable` (no socket)
  - `.connectFailed`
  - `.handshakeFailed`
  - `.permissionDenied` (if any)

### Runtime failure handling
If VirtualHID send fails:
- Immediately mark backend unhealthy.
- Switch `KeyEventDispatcher.dispatcher` to CGEvent backend.
- Record last error (debug log, and optionally surface in UI).
- Optional: background re-try if user preference remains VirtualHID.

**Never block the touch pipeline waiting for reconnection.**

---

## User Settings and UI

### Persisted preference
Add a new defaults key:
- `GlassToKey.keyboardOutputBackend` (string enum)
  - `"cgevent"` (default)
  - `"virtualhid"` (only used if available)

### UI
In settings UI:
- Picker: “Keyboard Output”
  - “CGEvent (Compatibility)”
  - “VirtualHID (Karabiner)”
- Status section (read-only):
  - Installed: Yes/No
  - Activated: Unknown/Yes/No (best-effort)
  - Daemon reachable: Yes/No (from helper)
  - Currently using: CGEvent/VirtualHID
  - Last error: (if any)
- Buttons:
  - “Open Install Guide” (opens Karabiner docs / repo)
  - “Recheck VirtualHID Status”

---

## Performance Requirements (hard rules)
- Key dispatch hot path:
  - No filesystem checks.
  - No process launches.
  - No JSON encoding/decoding.
  - No allocations if avoidable.
- Use persistent connections:
  - Persistent XPC connection main↔helper
  - Persistent socket connection helper↔vhidd_server
- Batch where possible:
  - For `postKeyStroke`, send one IPC message that contains both down+up.

---

## Implementation Plan (step-by-step)

1) **Defaults**
   - Add `GlassToKeyDefaultsKeys.keyboardOutputBackend`.

2) **Backend state types**
   - Add `enum KeyboardOutputBackend { case cgevent, virtualhid }`
   - Add `struct KeyboardBackendStatus { backend, isInstalled, isReachable, lastError, usingBackend }`

3) **Refactor KeyEventDispatcher**
   - Make dispatcher swappable.
   - Add `configure(backendPreference:)` and `refreshBackendStatus()`.

4) **Add VirtualHID backend skeleton**
   - `VirtualHIDKeyDispatcher: KeyDispatching`
   - For now, can be a thin wrapper that calls `VirtualHIDXPCClient`.

5) **Add privileged helper**
   - Install as root.
   - Implement:
     - Connect to vhidd_server socket
     - Send events
     - Report health
   - Keep connection + mapping tables in helper process.

6) **Wire UI**
   - Toggle/picker writes defaults and triggers `KeyEventDispatcher.configure(...)`.
   - Status panel polls `KeyEventDispatcher.backendStatus` (or observes published state).

7) **Fallback logic**
   - On any VirtualHID send failure:
     - switch to CGEvent immediately
     - update status
     - optional backoff retry

8) **Testing**
   - Without Karabiner installed: ensure CGEvent still works.
   - With Karabiner installed but daemon not running: ensure CGEvent used, status explains why.
   - With daemon running and helper healthy: ensure VirtualHID used.
   - Stress test:
     - rapid taps and repeats (hold delete/arrow) and ensure no dropped events
     - flip backend preference during runtime and ensure safe switching

---

## Acceptance Criteria
- Default behavior unchanged: CGEvent output works exactly as before.
- Enabling VirtualHID:
  - If healthy, keystrokes emit through VirtualHID and UI shows “Using VirtualHID”.
  - If unhealthy, app shows reason and uses CGEvent.
- If VirtualHID fails mid-session:
  - App immediately falls back to CGEvent with no crash and minimal latency spike.
- Hot path overhead remains essentially unchanged compared to current CGEvent-only path.

---

## Notes for Codex
- Prefer small, composable types.
- Prefer deterministic, low-allocation code in the dispatch path.
- Keep privileged code isolated to the helper.
- Keep error handling explicit and state-machine-like to prevent backend “flapping”.
