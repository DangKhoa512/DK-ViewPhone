# Device acceptance checklist — not yet executed

Requires a physical iPhone 6s or iPhone 7 running iOS 15 with Dopamine **roothide**.
An Actions build and package validation do not establish runtime compatibility.

1. In Sileo, review removal of TrollVNC and install the validated DEB.
2. Verify ĐK ViewPhone appears in Settings, initially disabled on a fresh install.
3. Verify enabling without valid credentials fails; no VNC listener appears.
4. Set a unique random full-access password and the iPhone's private Wi-Fi IPv4.
5. Enable, Apply, leave Settings, and verify the daemon persists as mobile.
6. Connect over LAN on port 5901. Verify correct desktop name and framebuffer.
7. Tap, hold/drag, swipe, scroll and test supported hardware/key inputs.
8. Rotate through supported orientations; verify rendering and input coordinates.
9. Test clipboard in each direction with a full-access client.
10. Configure a different view-only password. Confirm viewing works but taps,
    keys, file transfer and remote clipboard writes cannot change the phone.
11. Reject wrong passwords; disconnect and reconnect; test multiple clients.
12. Lock/unlock the phone, respring/restart through the normal jailbreak UI,
    then verify service state and reconnection without leaving Settings open.
13. Compare CPU/RAM, temperature, capture latency and crash logs at 15/30 FPS.
14. Stop from Settings and Control Center. Verify sockets close and no input.
15. Optional web access: configure certificate/key, use WSS with a trusted
    certificate and an encrypted tunnel on an untrusted network. Validate
    noVNC behavior and TLS separately; specifying certificates alone is not a
    verified guarantee that the inherited server refuses every plaintext path.
16. Remove via Sileo; verify the daemon and package files are gone. Preferences
    remain for reinstall; use Reset Settings before removal if erasure is wanted.

Record device model/iOS/jailbreak versions and pass/fail evidence per step.
