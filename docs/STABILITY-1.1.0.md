# 1.1.0 stability and performance work

Build and physical test status are recorded separately. This version is not
24-hour qualified. The owner deferred the 24-hour and reboot tests and allowed
short device tests, with assistance for unlock and rotation.

## Source audit and changes

| Risk in 1.0.0 | 1.1.0 behavior |
| --- | --- |
| Fixed launchd respawn delay; no responsiveness check or crash budget | Launchd supervises a small mobile-user watchdog; the watchdog starts the unchanged engine executable in daemon mode and owns its lifecycle. |
| A static image could be mistaken for a hung capture | Main-runloop heartbeat every two seconds is independent of dirty-frame counts. No frame-change threshold causes recovery. |
| Crash loops lose context at restart | Persisted budget: retries after 2, 4, 8, 16 seconds, latch on the fifth failure in 15 minutes. Latch survives supervisor restart; explicitly turning Enabled off clears it. Logs record reason/count/status. |
| Hung engine still has a live PID | Missing main heartbeat for 30 seconds, or three failed local RFB-banner probes 30 seconds apart on an available interface, triggers bounded worker recovery. No VNC credentials enter probes. |
| DHCP changes leave an old concrete bind | Remember the interface owning the configured private address; follow only its private IPv4. On disappearance stop the worker, release sockets and wait; after three seconds of stable availability recreate the worker/listener. Preserve the saved bind preference. Unknown/unavailable initial addresses wait for configuration instead of opening a wildcard listener. |
| Viewer failures unnecessarily restart the service | Individual disconnects/reconnects stay in LibVNCServer. Worker recycling occurs only for actual interface/bind changes, configuration changes, crash or confirmed unresponsiveness; watchdog daemon persists. |
| Dead or slow TCP peers | TCP keepalive (60-second idle, 10-second interval, 3 probes), 5-second engine read/write wait. A duplicate socket tracks each in-flight update; after 10 seconds shutdown wakes a stalled writer without targeting a reused descriptor. |
| Client list changes between framebuffer lock/unlock | Retain and unlock exactly the same client objects during publication. |
| Autoreleased objects on long-lived LibVNC callback threads | Explicit autorelease pools around connect/disconnect callbacks and synchronized dictionary insert/removal. |
| Allocation failure could crash during rotation | Check realloc before memset; rotation/scaling and input coordinate algorithms otherwise remain unchanged. |
| Unbounded text output and potentially broad log messages | Launch stdout/stderr go to /dev/null. Watchdog writes fixed-schema JSONL: current plus three rotated files, each at most 256 KiB, private directory 0700/files 0600. No preferences, passwords, clipboard or key text enter the event schema. |
| Release builds lack useful performance evidence | Every 30 seconds log changed-frame FPS, completed client update count, callback processing time, process CPU percentage and resident memory. Raw frame contents are never logged. |
| A remote clipboard write can suppress the next different local value | Consume suppression tokens only for matching echo content; clear stale tokens for a different value. A deterministic policy test covers fewer system notifications than anticipated. |
| Background clipboard change notification is missed/coalesced | While viewers are present, a one-second changeCount poll supplements Darwin notifications. Stop the timer with the last viewer; read content only when the count changes. |

The existing ScreenCapturer dirty-frame optimization and zero-viewer capture
stop remain intact. No frame queue is added; LibVNCServer coalesces modified
regions. The 10-second update deadline intentionally disconnects an excessively
slow viewer rather than accumulating frames. Rendering, gestures and authentication
remain the upstream engine's responsibility.

The normal LibVNCServer background/thread model is retained. Timeout semantics
were checked against the [0.9.15 socket implementation](https://github.com/LibVNC/libvncserver/blob/LibVNCServer-0.9.15/src/libvncserver/sockets.c).
Network rebinding uses a controlled engine worker replacement instead of
mutating a live background listener's descriptor set from another thread.

## Diagnostics and interpretation

As mobile, export bounded logs and recovery counters:

```sh
/usr/bin/dkviewphone-watchdog --diagnostics > /var/mobile/dkviewphone-diagnostics.jsonl
```

From a root shell use `su mobile -c '...'`. The diagnostic export includes the
selected interface/address in recovery state, but no saved credentials. Test log
rotation with `dkviewphone-watchdog --self-test-log`; its temporary subdirectory
is isolated from production logs.

`changed_fps` counts changed frames passed through the callback, not display
refresh rate. `updates_sent` counts completed updates across clients, not unique
frames. `frame_processing_*` is server processing/publication time, not end-to-end
viewer latency. CPU/RSS trends can indicate a regression, but do not prove
absence of leaks. Long-duration soak and allocation profiling remain necessary.

## Compatibility and acceptance

Package ID and preference domain are unchanged. No migration overwrites 1.0
settings. Invalid credentials still fail closed. The server's original
entitlements are unchanged; the separate watchdog has only platform-application
and no-container, both a subset of the original entitlement set.

Required short tests: upgrade installed 1.0; authentication/input/view-only;
100 sequential connections; 20 real Wi-Fi power cycles; IP change; crash and
hang injection; manual-off during recovery; log rotation/export; clipboard;
rotation; respring; lock/unlock. Each must be recorded as pass, fail or not run
based on actual evidence. Simulator/host tests cannot mark a device check passed.
Reboot and 24-hour continuous run are deferred at the owner's request.

`devkit/device-tests` builds a separate temporary test executable, excluded from
the DEB. It needs Wi-Fi manager access to power-cycle Wi-Fi and the existing
pasteboard rights to verify/restore clipboard content; these test permissions
are not added to either production executable. Generic Python could not access
these services on the test device. The helper never prints clipboard contents
or queries Wi-Fi network names/passwords. Delete it after the device session.
For a copied standalone helper, create its `.jbroot` link from the resolved
`/usr/bin/.jbroot` link before execution; package installation normally supplies
this loader support. Use the helper as mobile for clipboard operations. Wi-Fi
tests use the global AllowEnable property; the first device-level power API
trial lost association and required the owner to reconnect, so it did not pass.
