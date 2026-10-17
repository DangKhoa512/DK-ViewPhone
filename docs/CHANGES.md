# ĐK ViewPhone changes

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
