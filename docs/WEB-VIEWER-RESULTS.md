# Web Viewer 1.1.1 — physical results

Device: iPhone 6s / iPhone8,1, iOS 15.8.4, Dopamine roothide.
Checkpoint: `167f88b`; DEB source: `3284c45a958f108cb33ea1560428bbf21032840b`.

[Actions build](https://github.com/DangKhoa512/DK-ViewPhone/actions/runs/39089452516) · [DEB/source artifact](https://github.com/DangKhoa512/DK-ViewPhone/actions/runs/39089452516/artifacts/12122510525) · [build logs](https://github.com/DangKhoa512/DK-ViewPhone/actions/runs/39089452516/artifacts/12122316981).

DEB SHA256: `c529cf75147cccbf42e9ac0080daaadf662157852a624243a14a249368307ebb`; 1,547,056 bytes.

Short test evidence only; Wi-Fi power/lease testing, long soak and reboot are not passed.

| Check | Status | Evidence |
| --- | --- | --- |
| Actions build, Python/C++/JS regression checks | passed | Run 39089452516 succeeded at 3284c45. Eight Python source/archive tests, C++ security/recovery tests and JS reconnect-event contract tests passed; offline bundle reproduced in CI. |
| Concurrent TLS lifecycle sanitizer regression | passed | 12 real-OpenSSL concurrent read/write/peek/pending/close rounds under ASan/UBSan passed in the dedicated CI job. Includes repeated engine path free and rejection of raw writes after TLS teardown. This is host coverage, separate from device coverage. |
| 100 Chrome WSS connect/disconnect cycles on physical iPhone | passed | {"event": "browser_wss_stress_passed", "iterations": 100, "worker_unchanged": true, "anchor_connected": true, "elapsed_s": 47.46, "time_unix": 1792290105.389827, "graceful": 50, "abrupt": 50, "frames": 10} |
| Final short-run crash inventory | passed | No additional trollvncserver crash reports after final install. The only recovery in the final diagnostic window is the explicitly injected SIGKILL; earlier candidate crashes are recorded separately. This is not a 24-hour pass. |
| DEB signatures, architecture and offline payload | passed | 204 payload entries; four signed arm64 binaries; HTML/CSS/JS/noVNC contents match source. Machine report contains asset hashes. |
| Exact final DEB upgrade from 1.1.0 | passed | Restored original preferences, installed verified 1.1.0 baseline, checkpointed all values, upgraded to this exact DEB and compared values before test configuration. Package SHA256 was independently verified on-device with Python (shasum was unavailable). A later comparison after intentional test configuration is expected to differ. Main server and web remained off until explicitly enabled for tests. |
| Direct LAN HTTP, MIME and offline bundle | passed | Windows Chrome 155.0.8059.84 loaded the page from iPhone port 5801 and authenticated through native WS on VNC port 5901. No CDN, proxy, Node or Python server on iPhone. |
| Live screen, tap and browser View-only | passed | Final package: Calculator 0 stayed unchanged for a view-only tap; the same full-access tap displayed 2. Frame hashes and local screenshots were inspected. Screenshots are not published. |
| Browser mouse drag/swipe | passed | Final 3284c45 DEB repeated in Chrome/WSS on 2026-10-18: mouse drag visibly scrolled native Settings from the network section down to wallpaper, Siri and privacy controls. Local screenshots inspected; raw screens excluded. |
| Server-enforced view-only password | passed | With the browser view-only toggle off, a view-only VNC credential blocked the same Calculator tap. Server restriction source is unchanged. |
| Remote Control off in server preferences | passed | Full-access credential with browser view-only off remained unable to tap when RemoteControlEnabled=false. No authentication policy change. |
| Auto Scale and Fullscreen | passed | Chrome entered/exited fullscreen, resized viewport and toggled scale. Canvas aspect ratio was preserved. Portrait 564x1004 and earlier landscape 1000x562 were observed; no new physical-rotation assistance claimed. |
| Browser rejects wrong VNC password | passed | Entered a generated wrong credential once; browser returned to disconnected state without an authentication retry loop. |
| Credential handling | passed | Observed empty password field after submission and empty local/session storage in isolated Chrome context. URL has host/ports only. Reconnect uses memory-only session credentials; manual Disconnect clears wrapper intent/credentials. |
| Worker crash recovery and automatic browser reconnect | passed | Killed the package engine deliberately. Watchdog replaced the worker with backoff; Chrome reauthenticated automatically and received a framebuffer. Initial development candidate failed due to noVNC clean-close semantics; wrapper and JS regression test were corrected. |
| Manual Disconnect stays disconnected | passed | After manual Disconnect, waited six seconds: no browser reconnect and Connect button remained enabled. JS regression also covers pending retry cancellation and five-attempt budget. |
| HTTPS/WSS and roothide certificate paths | passed | TLS 1.3, static assets and WSS authenticated with logical roothide certificate paths. Temporary self-signed IP-SAN certificate used with isolated test-context bypass; normal validation rejected it. Windows trust store was unchanged. |
| Disabling Web Viewer closes port 5801 | passed | {"case": "web-disabled", "web_port_closed": true, "vnc_banner_available": true} |
| HTTP requires explicit trusted-LAN consent | passed | {"case": "no-http-consent", "web_port_closed": true, "vnc_banner_available": true} |
| Bad TLS config has no plaintext fallback | passed | {"case": "invalid-tls-certificate", "web_port_closed": true, "vnc_banner_available": true} |
| HTTP/HTTPS path and method rejection | passed | Actual device rejected missing files, traversal, encoded traversal over HTTPS and POST; JavaScript MIME and exact bundled contents verified. No general CONNECT proxy enabled. |
| Native VNC regression with optional web TLS unavailable | passed | Raw TCP VNC authenticated with unchanged VNC security type 2 and returned a 564x1004 framebuffer while an intentionally invalid web certificate kept port 5801 closed. |
| Server survives closing Settings | passed | Terminated the verified Preferences process; both listeners remained owned by package worker and authenticated browser capture continued. Initial pkill command was unavailable; explicit verified PID termination succeeded. |
| Native Settings presentation and Copy URL | partial | Opened native preference pane and observed LAN IP, generated URL, HTTP port and certificate fields. Preferences toggles were exercised through the mobile CFPreferences test helper; Copy URL was not executed to avoid modifying the owner clipboard. |
| Physical Wi-Fi loss/rejoin and changed DHCP lease | not_run | Owner unavailable for assisted device operations in this session. No Wi-Fi power toggle was performed. Engine-crash reconnect is a separate test and is not a Wi-Fi pass. Prior 1.1.0 interface-alias evidence remains historical. |
| Keyboard-specific app acceptance / Edge | not_run | Wrapper retains bundled noVNC keyboard handling; this session used Chrome. Dedicated app keyboard acceptance and Edge were not separately tested. |
| 24-hour soak, reboot and memory-leak qualification | deferred | Previously deferred by owner. Short CPU/RSS diagnostics and existing timeout controls do not establish leak freedom, FPS improvement or 24-hour stability. |

The 1.1.0 watchdog, budget, runtime metrics, capture, HID and clipboard source files are unchanged from the checkpoint. Native binaries are signed/revalidated per build; binary reproducibility across builds is not claimed.

Final 1.1.1 DEB installed. Original 17 preference values independently matched after CFPreferences flushed (Enabled=false); web/VNC/control listeners were closed. Temporary on-device test tools, package copies and TLS keys/certificates were removed. The separate TrollStore app files were retained; its conflicting server/manager remain stopped. Original clipboard was not modified.

Device crash reports also exposed unsynchronized SSL teardown and repeated request-path free in LibVNCServer. Both were corrected with targeted lifecycle changes and then rechecked with the recorded host/device stress tests; this does not establish 24-hour stability. Other defects fixed during this work: logical certificate paths failed at prebuilt library boundaries on roothide; established server-side WebSocket closes were incorrectly excluded from reconnect. UTF-8 HTML generation was also corrected after a Chrome smoke test. Earlier failed attempts are not counted as final passes.

Raw screen captures, unsanitized stdout, device filesystem paths and credentials remain excluded from the public evidence. The JSONL export uses a fixed field allowlist.

[Setup and limits](LAN-WEB-VIEWER.md) · [machine report](test-results/1.1.1/report.json) · [sanitized logs](test-results/1.1.1/device-events.jsonl).

Changed tracked files relative to checkpoint:

- `.github/workflows/build-dkviewphone.yml`
- `Makefile`
- `README.md`
- `app/TrollVNC/TrollVNC/TVNCRootListController.m`
- `devkit/build-webviewer.py`
- `devkit/verify-package.py`
- `devkit/webviewer-index.html`
- `docs/ATTRIBUTION.md`
- `docs/CHANGES.md`
- `docs/LAN-WEB-VIEWER.md`
- `docs/WEB-VIEWER-RESULTS.md`
- `layout/DEBIAN/control`
- `layout/usr/share/trollvnc/webclients/index.vnc`
- `layout/usr/share/trollvnc/webclients/viewer.bundle.js`
- `layout/usr/share/trollvnc/webclients/viewer.css`
- `layout/usr/share/trollvnc/webclients/viewer.js`
- `prefs/TrollVNCPrefs/Resources/Root.plist`
- `src/DKRFBTLS.mm`
- `src/DKWebPolicy.h`
- `src/DKWebSession.h`
- `src/DKWebTLS.h`
- `src/DKWebTLS.mm`
- `src/trollvncserver.mm`
- `tests/rfb-tls.cpp`
- `tests/security-policy.cpp`
- `tests/test_source.py`
- `tests/web-viewer.mjs`

The separate results workflow and generated report files are also included in the report commit.
