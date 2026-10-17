# Physical results: DK ViewPhone 1.1.0

Tested on iPhone 6s / iPhone8,1, iOS 15.8.4, Dopamine roothide.

Build source: `64128aa61060c880b7e2c695a5d869c354592128`.
[Build and logs](https://github.com/DangKhoa512/DK-ViewPhone/actions/runs/39014574938) · [DEB/source artifact](https://github.com/DangKhoa512/DK-ViewPhone/actions/runs/39014574938/artifacts/12094501386).

DEB SHA256: `7d22ea0c1dc6e43167bb115d3cca1be77804b4e032c8ae705e941e1a2c070c95`.
Size: 1,494,780 bytes; metadata iphoneos-arm64e; four arm64 binaries.

**Short test results only; not qualified for a 24-hour stability claim.**

| Test | Status | Evidence |
| --- | --- | --- |
| Actions build and DEB validation | passed | Successful run 39014574938; local validation matches CI SHA256; 201 entries, four signed arm64 binaries. Test utility is excluded from DEB. |
| Upgrade 1.0.0 to final 1.1.0 | passed | Installed trusted 1.0.0 baseline, checkpointed preferences privately, upgraded to this exact DEB, compared every saved preference value. |
| 100 direct LAN viewer connect/disconnect cycles | passed | {"completed": 100, "mean_connect_and_optional_capture_seconds": 0.1970881550001286, "p95_seconds": 0.3465579000003345, "note": "Capture requested on every tenth connection; this is not pure frame latency."} |
| Crash recovery | passed | Injected faults on earlier 1.1.0 candidate, authenticated/retrieved frames after recovery. Final supervisor and budget source are identical to that tested candidate. |
| Hung worker recovery | passed | Injected faults on earlier 1.1.0 candidate, authenticated/retrieved frames after recovery. Final supervisor and budget source are identical to that tested candidate. |
| Exponential backoff and crash-loop latch | passed | {"observed_delays_seconds": [2, 4, 8, 16, -1], "note": "Fifth failure latched; no engine remained. Explicit manual-off reset was observed."} |
| Manual-off cancels pending recovery | passed | Turned Enabled off during backoff without restarting supervisor; no worker/listener appeared afterwards. |
| Interface IPv4 change | passed | Controlled private /32 alias on en0: listener moved to alias, authenticated frame received via SSH, alias removed and direct original LAN access restored. This was not a DHCP server lease-change test. |
| Wi-Fi loss and recovery | partial | The device-level power API trial lost association; owner reconnected Wi-Fi. Watchdog waited without crash-loop recovery and LAN access returned. Global AllowEnable state was unavailable, so automated cycling was stopped. |
| 20 Wi-Fi power cycles | deferred | Owner explicitly deferred the 20 physical Wi-Fi power cycles after the native API could not verify global power state. |
| Clipboard both directions and view-only write protection | passed | Native mobile helper confirmed phone values, first different phone-side value reached viewer after remote write, view-only write was rejected, original item array restored and compared. No content exported. |
| Full-access and view-only touch | passed | Calculator stayed at 0 for view-only tap; same full-access tap displayed 2. Capture and HID implementation files unchanged from upstream. |
| Slow/non-reading viewer | passed | Stopped reading for 13 seconds; supervisor/worker PIDs unchanged and normal client captured afterwards. The exact FIN/deadline timing was not measured. |
| Respring and VNC reconnect | passed | SpringBoard PID changed after sbreload; watchdog/worker PIDs and listener remained, authenticated reconnect received a framebuffer. |
| Rotation and landscape touch mapping | passed | Portrait 564x1004 changed to landscape 1000x562. Calculator stayed at 0 for a view-only tap and displayed 2 for the same full-access tap at landscape coordinates. One landscape direction tested; other quadrants and a portrait-return cycle were not separately accepted. |
| Lock and unlock | passed | Observed locked screen after respring; owner unlocked and opened Calculator; authenticated capture and touch resumed. This was a respring-triggered lock, not a separate power-button lock cycle. |
| 24-hour continuous run | deferred | Deferred by owner; observations during pauses are not a controlled 24-hour soak. |
| Reboot and rejailbreak | deferred | Deferred by owner. No reboot was performed. |
| Memory leak investigation | partial | Added callback autorelease pools and collected process RSS/CPU trends. Native leaks/malloc_history tools were unavailable; trends do not establish leak freedom. |
| Structured log rotation on device | passed | {"rotation_passed": true, "files": 4, "valid_json_lines": 264} |

Performance samples from the final supervisor session are in [metrics.csv](test-results/1.1.0/metrics.csv). Values describe a short mixed/mostly-static workload, including a deliberately non-reading viewer and respring. Static changed-frame FPS can be zero. The maximum processing delay is not an ordinary-workload latency promise. No claim of improved FPS, sustained 30 FPS or absence of leaks is made.

```json
{
  "changed_fps": {
    "min": 0,
    "max": 10.031115468025124,
    "mean": 1.3574496521133201
  },
  "cpu_percent": {
    "min": 0.21423195499470363,
    "max": 21.36543845812547,
    "mean": 3.625263498824337
  },
  "rss_bytes": {
    "min": 19152896,
    "max": 25477120,
    "mean": 21468081.230769232
  },
  "frame_processing_mean_ms": {
    "min": 18.531669781931466,
    "max": 1579.545,
    "mean": 168.3918472064585
  },
  "frame_processing_max_ms": {
    "min": 23.311,
    "max": 1579.545,
    "mean": 303.8812857142857
  },
  "samples": 26,
  "frame_processing_weighted_mean_ms": 27.05234598012647,
  "definitions": "Changed callback FPS, process CPU percent/RSS, server callback-to-publication latency; not display FPS or glass-to-glass latency."
}
```

Raw screenshots, clipboard backup and unsanitized device paths are not published. Exported JSON uses an allowlist. A standalone TrollStore manager was stopped when it restarted during testing; concrete listener ownership was checked against the package worker. Original app files were retained.

Final 1.1.0 remains installed with Enabled=false. Original saved preference values were restored and compared exactly, with server disabled. No VNC/control listeners or engine workers remained. Temporary device test tools, credential checkpoints and clipboard backups were removed; original clipboard items had already been restored and verified. Standalone TrollStore app files were retained and its manager remained stopped.

Machine report: [report.json](test-results/1.1.0/report.json); [sanitized events](test-results/1.1.0/device-events.jsonl).
