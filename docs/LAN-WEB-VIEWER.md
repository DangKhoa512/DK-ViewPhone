# LAN Web Viewer — 1.1.1

This extends the existing 1.1.0 tree, checkpoint `167f88b`; package ID remains
`com.dk.viewphone`. Capture, HID input, watchdog, backoff, network recovery and
runtime diagnostics remain in place. No Node/Python server is installed on iPhone.

## Enable from Settings

1. Install the 1.1.1 Dopamine roothide DEB. Open Settings → ĐK ViewPhone.
2. Keep VNC Port at 5901. Set Bind Address to the concrete private Wi-Fi IPv4
   shown under Local IP Address; loopback remains the safe initial default.
3. Configure the existing full-access VNC password; optionally set a different
   view-only password. Both follow the unchanged eight-visible-ASCII password policy.
4. Turn on Enable LAN Web Viewer, set HTTP Port to 5801. For plaintext access,
   explicitly turn on Allow HTTP/WS on Trusted LAN. This exposes screen and input
   without encryption and is unsuitable for untrusted LANs or Internet forwarding.
5. Enable the main server and Apply. Copy URL copies the web address only, never
   credentials. The URL field is a configuration hint, not a listener health check.

On Windows, connect Chrome or Edge to the same LAN, open `http://IP_IPHONE:5801/`,
click Connect and enter the VNC password in the dialog. Assets are entirely local.
VNC authentication happens inside the WebSocket session on port 5901. No password
is accepted from query parameters, stored in browser storage, or bundled in JS.
Session credentials stay in browser memory for bounded reconnect and are cleared
by manual Disconnect or closing the page. The page offers Disconnect, Fullscreen,
View-only, Auto Scale and bounded reconnect (2/4/8/16 seconds, at most five attempts).
An IP change requires opening the new URL shown in Settings.

View-only in the browser suppresses local input. For enforced restrictions use
the view-only password, the existing global ViewOnly setting, or turn off Enable
Remote Control; server-side restrictions cannot be lifted by the browser toggle.
Changing server preferences recycles the worker through the existing supervisor,
so active sessions reconnect. Closing Settings does not stop the launch daemon.
Disabling LAN Web Viewer closes its HTTP/HTTPS listener while VNC remains available.
The existing native WebSocket transport shares the VNC listener; this toggle does
not disable that transport on port 5901.

## HTTPS / WSS

Set SSL Certificate File and SSL Private Key File to matching PEM files readable
by mobile, enable Use HTTPS / WSS, then Apply. Use a certificate with the current
iPhone IP in its subjectAltName, signed by a CA trusted by Windows/Chrome/Edge.
Keep the key outside the web document root, with private file permissions.
The pre-existing Generate CA helper does not guarantee a suitable server SAN;
provide a suitable server certificate. The browser must trust it for both ports.
Open `https://IP_IPHONE:5801/`; the viewer selects `wss://IP_IPHONE:5901/` automatically.
No plaintext HTTP fallback is opened when HTTPS is selected. Invalid certificate
files leave the optional web service unavailable without disabling normal VNC.
Raw VNC on 5901 retains its original transport; selecting HTTPS does not encrypt
third-party raw VNC connections.

## Implementation and limits

Reuses LibVNCServer's HTTP server for HTTP, its WebSocket implementation for
WS/WSS, and bundled noVNC without editing vendor files. LibVNCServer HTTP is
plaintext and processes one download at a time. `devkit/build-webviewer.py` pins
esbuild 0.25.12, bundles noVNC/wrapper, and embeds CSS in the small index template
to avoid parallel asset requests. Node runs only on the build host.

The optional `DKWebTLS` adapter serves the same static assets in the engine
process using existing OpenSSL libraries: TLS >=1.2, four fixed workers, bounded
request/file sizes, I/O and response deadlines, canonical document-root checks,
and no proxy/command/configuration endpoint. Shutdown joins workers and closes
sockets. LibVNCServer's old HTTP CONNECT proxy is disabled: noVNC uses native WS.
The document root is resolved relative to the installed executable, preserving
roothide relocation. An explicit HttpDir override remains available.
Paths passed to prebuilt OpenSSL/LibVNCServer are translated through libroothide
at runtime; the saved certificate, key and HttpDir values are not rewritten.

FPS/latency show a dash: this bundled noVNC does not expose accurate public
measurements. Existing 1.1.0 CPU/RSS/changed-frame/processing diagnostics remain
available; they are not glass-to-glass latency. HTTP content is public to the
bound LAN before VNC authentication; framebuffer and input still require VNC auth.
No router port changes or firewall changes are made by this package.

Test evidence, including unperformed physical checks, is recorded separately in
[WEB-VIEWER-RESULTS.md](WEB-VIEWER-RESULTS.md).
