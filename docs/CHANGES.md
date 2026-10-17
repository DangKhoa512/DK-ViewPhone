# ĐK ViewPhone 1.0.0 changes

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
- `app/TrollVNC/TrollVNC/{TVNCRootListController.m,TVNCUtil.h}` and
  `prefs/CCTrollVNC/CCTrollVNC.mm`: shared Settings/CC password checks and stop
  behavior. The DEB compiles these through the existing source symlinks.
- `prefs/*/Makefile`, preference/CC plist and localization resources: arm64/iOS15,
  display names and editable defaults. Upstream self-updater is compiled only
  for bootstrap apps, which this project explicitly excludes.
- `devkit/verify-package.py`, `tests/*`: source consistency, engine preservation,
  security policy, real DEB and Mach-O signature checks.
- `.gitattributes`, `.gitignore`: portable shell line endings and build exclusions.
- `README.md`, `docs/*`: setup, provenance, limitations, device test checklist.

Internal identifiers intentionally preserved: executable `trollvncserver`,
daemon label/preference domain `com.82flex.trollvnc`, resource directory
`usr/share/trollvnc`, bundles `TrollVNCPrefs`/`CCTrollVNC` and their identifiers.
Package-level Conflicts/Replaces/Provides ensure these files do not coexist
with the original package. Existing preferences survive replacement; invalid
credentials disable startup. Removing the package keeps user preferences.

ScreenCapturer.mm, STHIDEventGenerator.mm and ClipboardManager.mm are unchanged.
No capture, rotation, scaling or gesture algorithms were rewritten. Existing
entitlements and static libraries are unchanged.
