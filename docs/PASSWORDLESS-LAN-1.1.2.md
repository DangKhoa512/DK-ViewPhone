# Passwordless LAN — 1.1.2

Added at the owner's explicit request. Checkpoint: `bfb1d6f` (tested 1.1.1).
Package ID stays `com.dk.viewphone`, arm64 / Dopamine roothide. Capture, input,
watchdog, network recovery, metrics and TLS lifecycle fixes remain unchanged.

In Settings → ĐK ViewPhone, set Bind Address to the iPhone's private LAN IPv4,
enable Trusted LAN and **No Password on Trusted LAN**, keep Reverse Mode off,
enable the server and LAN Web Viewer (VNC 5901 / HTTP 5801), then Apply.
Open `http://IP_IPHONE:5801/` on Windows and click Connect. The browser asks for
a password only if the server actually requires one. HTTPS/WSS remains available
with matching, browser-trusted certificate/key files.

Anyone who can reach this listener can view/control the iPhone without a
password, including native VNC clients. View-only passwords do not apply in this
mode. Use global View-only or disable Remote Control to restrict all clients.
Do not forward these ports to the Internet. Passwordless mode defaults off;
normal password validation and saved credentials remain available when it is off.

Build source: `b69002d8ea65ec899f93a97ddc8e477553703cd3`. [DEB/source artifact](https://github.com/DangKhoa512/DK-ViewPhone/actions/runs/39091082276/artifacts/12122438621) and [build logs](https://github.com/DangKhoa512/DK-ViewPhone/actions/runs/39091082276/artifacts/12122428668).

SHA256: `31f839f9ebd328d8106281d30cc46a6031e8a7dbf704bb37ffddd02d1f2c1c62`.

| Test | Status |
| --- | --- |
| Actions and host regression | passed |
| DEB integrity and safe defaults | passed |
| Password mode retained | passed |
| Passwordless LAN HTTP/WS | passed |
| 100 passwordless LAN connections | passed |
| Tap and client view-only | passed |
| Server Remote Control off | passed |
| Automatic no-password recovery | passed |
| Manual Disconnect | passed |
| HTTPS/WSS passwordless | passed |
| Trusted LAN opt-in required | passed |
| Original preferences retained and final URL active | passed |
| Final short-run crash inventory | passed |

1.1.2 installed; HTTP 5801 and native VNC 5901 enabled on the requested LAN IP with passwordless mode explicitly on. Original unrelated preferences, including saved credentials and screen scale, matched the backup. Temporary test tools and certificate/key fixtures removed. Clipboard unchanged.

- 24-hour/reboot/physical Wi-Fi cycles and lease change remain deferred or unperformed.
- New native Settings toggle was exercised via CFPreferences; full manual Settings UI acceptance was not run.
- First stress attempt checked an empty initial canvas too early; harness corrected to wait up to ten seconds for actual pixels before rerun.
- Initial auth-mode connection attempts saw server off; repeated after closing Settings and reapplying test preferences. No failed attempts counted as passes.
- This session used Chrome; Edge and dedicated keyboard acceptance not rerun.

[Machine report](test-results/1.1.2/report.json) / [sanitized device log](test-results/1.1.2/device-events.jsonl). Earlier [1.1.1 results](WEB-VIEWER-RESULTS.md) remain historical.
Build source: `b69002d8ea65ec899f93a97ddc8e477553703cd3`. [DEB/source artifact](https://github.com/DangKhoa512/DK-ViewPhone/actions/runs/39091082276/artifacts/12122438621) and [build logs](https://github.com/DangKhoa512/DK-ViewPhone/actions/runs/39091082276/artifacts/12122428668).

SHA256: `31f839f9ebd328d8106281d30cc46a6031e8a7dbf704bb37ffddd02d1f2c1c62`.

| Test | Status |
| --- | --- |
| Actions and host regression | passed |
| DEB integrity and safe defaults | passed |
| Password mode retained | passed |
| Passwordless LAN HTTP/WS | passed |
| 100 passwordless LAN connections | passed |
| Tap and client view-only | passed |
| Server Remote Control off | passed |
| Automatic no-password recovery | passed |
| Manual Disconnect | passed |
| HTTPS/WSS passwordless | passed |
| Trusted LAN opt-in required | passed |
| Original preferences retained and final URL active | passed |
| Final short-run crash inventory | passed |
| New native Settings toggle UI acceptance | partial |
| Physical Wi-Fi loss and DHCP change | not_run |
| 24-hour soak and reboot | deferred |
| Edge and keyboard-specific acceptance | not_run |

1.1.2 installed; HTTP 5801 and native VNC 5901 enabled on the requested LAN IP with passwordless mode explicitly on. Original unrelated preferences, including saved credentials and screen scale, matched the backup. Temporary test tools and certificate/key fixtures removed. Clipboard unchanged.

- 24-hour/reboot/physical Wi-Fi cycles and lease change remain deferred or unperformed.
- New native Settings toggle was exercised via CFPreferences; full manual Settings UI acceptance was not run.
- First stress attempt checked an empty initial canvas too early; harness corrected to wait up to ten seconds for actual pixels before rerun.
- Initial auth-mode connection attempts saw server off; repeated after closing Settings and reapplying test preferences. No failed attempts counted as passes.
- This session used Chrome; Edge and dedicated keyboard acceptance not rerun.

[Machine report](test-results/1.1.2/report.json) / [sanitized device log](test-results/1.1.2/device-events.jsonl). Earlier [1.1.1 results](WEB-VIEWER-RESULTS.md) remain historical.
