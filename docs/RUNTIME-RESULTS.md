# Physical device results — 2026-10-17

Tested the actual Actions artifact on an iPhone 6s (`iPhone8,1`), iOS 15.8.4,
with a Dopamine roothide bootstrap. Its package architecture was
`iphoneos-arm64e` and `libroothide.dylib` was present. The exact installed
Dopamine version was not collected. These results cover this device only;
an iPhone 7 was not tested.

- Tested source: `7050ccc1834b6f259816275669391751bc3ea9ca`.
- [Successful build and logs](https://github.com/DangKhoa512/DK-ViewPhone/actions/runs/39009612177).
- [DEB, matching source and validation artifact](https://github.com/DangKhoa512/DK-ViewPhone/actions/runs/39009612177/artifacts/12092078912).
- DEB: `DKViewPhone_1.0.0_roothide.deb`, 1,480,300 bytes.
- SHA256: `1a3fef35100c030e29b3ad6197e4e8e6fa008c1488edf3d2cb42383196bfb080`.

Installation and removal used `dpkg` over an SSH connection forwarded through
USB. Sileo's file-opening and transaction UI were not exercised. Runtime VNC
connections initially used that encrypted SSH connection and temporary random
passwords. A later same-LAN retest used direct TCP sockets from the PC's Wi-Fi
IPv4 to the iPhone's Wi-Fi IPv4 on port 5901; USB/SSH was used for setup only.

| Check | Result and evidence |
| --- | --- |
| Install | Passed; `com.dk.viewphone 1.0.0 iphoneos-arm64e` installed successfully. |
| Settings | Passed; the ĐK ViewPhone entry, icon and preference module rendered. |
| Capture | Passed; actual Settings and Home screens received as 564×1004 framebuffers at scale 0.75. |
| Authentication | Passed; RFB advertised password security type 2 only; correct full/view passwords authenticated and an incorrect password was rejected. |
| Full access input | Passed; swipes scrolled Settings and a tap opened the ĐK ViewPhone module. A supported Home-button input returned to Home. |
| View-only input | Passed for tap and swipe; after the owner stopped touching the phone, before/after framebuffer hashes were identical for each attempt. Keyboard and clipboard restrictions were not tested at runtime. |
| Reconnect and clients | Passed; multiple full-access reconnects and simultaneous full/view clients. The server reported their distinct view-only roles. |
| Background service | Passed; server ran as mobile (UID 501). After terminating Settings, a fresh authenticated connection still received a framebuffer. |
| Disable | Passed; disabling preferences and restarting the managed service closed VNC port 5901 and the local control listener. The inactive daemon process remains managed by launchd. The Settings/CC stop buttons were not separately exercised. |
| Removal | Passed; daemon unloaded, server/daemon plist/preference and CC bundle paths absent, no server/manager processes or listeners remained. |
| Reinstall | Passed; the same DEB installed again and the daemon loaded. Final state was installed and disabled, without listeners. |
| Preferences cleanup | Passed; restored preferences matched the original backup exactly except `Enabled=false`. Temporary VNC credentials and device test files were removed. |
| Direct LAN | Passed on retest after the owner joined the same LAN. Windows confirmed established sockets from the PC's Wi-Fi IPv4 to the iPhone's Wi-Fi IPv4:5901. Both full/view credentials authenticated, framebuffers arrived, full-access tap and swipe worked, view-only tap was ignored, reconnect succeeded and a wrong password was rejected. The earlier attempt on separate subnets had timed out. |

For the view-only swipe, both framebuffers had SHA256
`e1648020042068f1fe582f9f80e909c1333751266156b8ed25aa0fe9faa52d9f`.
For the view-only tap, both had SHA256
`7ba41be36c65fa0cc9914f5fca8e438edda327364c8d0742299952e77b5796a5`.
Earlier input trials during physical phone use were inconclusive and were
excluded from these pass results. Screenshots and raw device logs remain local
because they can contain personal screen content and device paths.

In the direct LAN retest, the view-only tap before/after framebuffers both had
SHA256 `adeed292ef292798ff00e44e87b80273dc1d4a1fae66868c3db5652bfd7d922b`.
The same tap with full access returned from the preference module to Settings;
a subsequent swipe scrolled the list. Direct TCP reauthentication and another
framebuffer were received after disconnecting the full-access client. No source
or binary changes were needed for LAN; the tested DEB is still the one above.

A standalone TrollStore TrollVNC manager was already running before installation.
It was stopped gracefully; its app files were retained. Do not run that manager
alongside this DEB: both intentionally retain the upstream preference domain
and service resources. Package Conflicts/Replaces handles the original DEB,
but cannot remove a standalone TrollStore app.

Initial USB-session CPU/RAM snapshots ranged from 0.9–6.9% CPU and approximately
16–17 MiB RSS. A snapshot during the raw-frame LAN reconnect was 32.8% CPU and
17,568 KiB RSS. These short observations are not a sustained performance,
thermal or latency benchmark. This test client requests raw frame encoding.

Remaining checks: iPhone 7; third-party desktop viewer UI; rotation and input coordinate
mapping; clipboard in both directions; keyboard and view-only clipboard/keys;
Control Center actions; lock/unlock; respring/reboot; long-running stability;
WSS/noVNC and TLS behavior. No claim of passing these checks is made.

To resume use, set a separate valid eight-character VNC password and choose
the phone's reachable private IPv4 bind address, then enable the server. Use
loopback with an encrypted tunnel when appropriate. Original saved preferences
were preserved, so their values can differ from fresh-install defaults.
