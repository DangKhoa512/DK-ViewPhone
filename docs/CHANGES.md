# ĐK ViewPhone changes

## 1.1.2

Adds explicit optional passwordless LAN mode at the owner's request. Reuses
LibVNCServer security type None; default remains password authentication. The
new mode requires Trusted LAN consent, a concrete private/loopback IPv4 bind,
and Reverse Mode off. Existing credentials are retained. Global view-only,
Remote Control restriction and blocked-host checks still apply. The web client
opens a password dialog only when challenged by the server.
See [setup and actual results](PASSWORDLESS-LAN-1.1.2.md).

## 1.1.1

Integrates an offline blue LAN Web Viewer around the bundled noVNC. Reuses
LibVNCServer HTTP and native WS/WSS; adds a bounded optional native HTTPS static
adapter because the built-in HTTP service has no TLS support. Adds Settings for
web opt-in, explicit trusted-LAN consent, HTTPS, remote-control restriction,
current IP, web URL and Copy URL. Defaults to web off and HTTP port 5801.
Resolves certificate/key/custom document-root paths at the prebuilt-library
boundary with libroothide, preserving saved logical or physical path values.
Fixes automatic reconnect after established server-side WebSocket closes.
Hardens the inherited OpenSSL adapter against concurrent read/write/close,
and releases unused WebSocket request paths before session threads start to
avoid the 0.9.15 repeated-close double-free found on the physical device.
Concurrent TLS lifecycle regression runs under ASan/UBSan in CI.

The 1.1.0 capture/input, clipboard, watchdog/backoff, network recovery and runtime
metrics implementations are retained. The HTTP CONNECT proxy is disabled because
the viewer uses native WebSocket on the VNC port. No new server runtime or
production entitlements are added. See [setup](LAN-WEB-VIEWER.md) and
[recorded tests and limits](WEB-VIEWER-RESULTS.md).

## 1.1.0

Adds a separate bounded-recovery supervisor, main-runloop heartbeat, private
interface rebinding, per-update slow socket deadline, TCP keepalive and bounded
JSON diagnostics with CPU/RSS/changed-frame metrics. Fixes client publication
lock lifetime, callback autorelease scope, realloc failure handling and clipboard
echo suppression/missed notifications. Saved preference values and the server's
security policy/entitlements remain unchanged. Capture and HID injection files
remain byte-for-byte identical to upstream.

See [audit and design](STABILITY-1.1.0.md) and [physical results](TEST-RESULTS-1.1.0.md).
The owner deferred 24-hour, reboot and 20 Wi-Fi-cycle checks.

## 1.0.0

Baseline: owngoal-dev/TrollVNC cfdb737e72977d961eb7d0a8110d2fe1a58551d7.

- `Makefile`: version, roothide-only device packaging, explicit libroothide link.
- `layout/DEBIAN/{control,postinst,prerm}`: package identity, controlled replacement
  of TrollVNC, RootHide virtual paths, visible installation errors.
- `devkit/roothide.sh`: honor an explicit Theos checkout and detect a missing one.
- `devkit/before-package.sh`: bundle GPL/attribution and reject Managed.plist.
- `.github/workflows/build-dkviewphone.yml`: pinned upstream/Theos baseline,
  macOS/Xcode, original build first, derivative build second, validate before
  artifact upload, always retain diagnostics. Original workflow is archived as
  `docs/upstream-build.yml` so other schemes cannot run accidentally.
- `src/trollvncserver.mm`, `src/DKViewPhonePolicy.h`: display/defaults, mandatory
  eight-byte mixed ASCII credentials, distinct view-only credential, explicit
  private/loopback IPv4 bind, disable wildcard IPv6 listener, TLS configuration
  for web access, no keyboard logging, per-client input/clipboard protections.
- `src/BulletinManager.mm`: notification display title only.
- `app/TrollVNC/TrollVNC/ZTSelfSignedCertificate.m`: replace the iOS 15 deprecated
  SecKeyGeneratePair with SecKeyCreateRandomKey/SecKeyCopyPublicKey, retaining
  RSA-2048 generation and certificate export.
- `app/TrollVNC/TrollVNC/{TVNCRootListController.m,TVNCUtil.h}` and
  `prefs/CCTrollVNC/CCTrollVNC.mm`: shared Settings/CC password checks and stop
  behavior. The DEB compiles these through the existing source symlinks.
  Reset Defaults also stops an existing session before reloading the disabled
  default configuration.
- `prefs/*/Makefile`, preference/CC plist and localization resources: arm64/iOS15,
  display names and editable defaults. Upstream self-updater is compiled only
  for bootstrap apps, which this project explicitly excludes.
- `devkit/verify-package.py`, `tests/*`: source consistency, engine preservation,
  security policy, real DEB and Mach-O signature checks.
- `.gitattributes`, `.gitignore`: portable shell line endings and build exclusions.
- `Artworks/DKViewPhone.svg`, `devkit/generate-icons.ps1`, preference/CC PNGs:
  native brand artwork and transparent Control Center glyphs.
- `layout/usr/share/trollvnc/webclients/index.vnc`: display branding and WSS as
  the default browser connection action; noVNC engine files are unchanged.
- `README.md`, `docs/*`: setup, provenance, limitations, device test checklist.
- `docs/third-party/*`: preserved library/client/font license texts and download
  provenance, copied into the DEB documentation directory.

Internal identifiers intentionally preserved: executable `trollvncserver`,
daemon label/preference domain `com.82flex.trollvnc`, resource directory
`usr/share/trollvnc`, bundles `TrollVNCPrefs`/`CCTrollVNC` and their identifiers.
Package-level Conflicts/Replaces/Provides ensure these files do not coexist
with the original package. Existing preferences survive replacement; invalid
credentials disable startup. Removing the package keeps user preferences.

ScreenCapturer.mm, STHIDEventGenerator.mm and ClipboardManager.mm are unchanged.
No capture, rotation, scaling or gesture algorithms were rewritten. Existing
entitlements and static libraries are unchanged.
