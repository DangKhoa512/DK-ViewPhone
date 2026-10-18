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

Build, package validation and real-device results: pending at source preparation.
Previous 1.1.1 tests remain historical: [report](WEB-VIEWER-RESULTS.md).
