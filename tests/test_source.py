import importlib.util
import plistlib
from pathlib import Path
import subprocess
import struct
import hashlib
import json
import re
import unittest

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('validator', ROOT / 'devkit/verify-package.py')
validator = importlib.util.module_from_spec(spec)
spec.loader.exec_module(validator)


class SourceTests(unittest.TestCase):
    def test_vietnamese_settings_preserve_configuration(self):
        raw = (ROOT / 'prefs/TrollVNCPrefs/Resources/vi.lproj/Localizable.strings').read_text(encoding='utf-8')
        pairs = re.findall(r'("(?:[^"\\]|\\.)*")\s*=\s*("(?:[^"\\]|\\.)*")\s*;', raw)
        strings = {json.loads(k):json.loads(v) for k,v in pairs}
        self.assertEqual(len(strings), len(pairs), 'Duplicate translation keys')
        self.assertEqual(strings['Apply'], 'Áp dụng')
        for key, value in strings.items():
            # A mismatched %@/%d can crash native string formatting at runtime.
            pattern = r'%(?:[0-9]+\$)?(?:[0-9.]+)?[@diufs]'
            self.assertEqual(sorted(re.findall(pattern,key)), sorted(re.findall(pattern,value)), key)
            self.assertNotIn('\ufffd',value)
        before = plistlib.loads(subprocess.check_output(['git','show','c99c897:prefs/TrollVNCPrefs/Resources/Root.plist'],cwd=ROOT))
        after = plistlib.loads((ROOT/'prefs/TrollVNCPrefs/Resources/Root.plist').read_bytes())
        display = {'label','footerText','placeholder','validTitles','shortTitles','staticTextMessage'}
        def settings(p):
            return {i['key']:{k:v for k,v in i.items() if k not in display} for i in p['items'] if 'key' in i}
        original,translated = settings(before),settings(after)
        changed_defaults = {'Scale','FrameRateSpec','AllowUnauthenticatedLAN','LANWebViewerEnabled','WebViewerTrustedLAN'}
        for key,value in original.items():
            if key in changed_defaults:
                self.assertEqual({k:v for k,v in value.items() if k != 'default'},
                                 {k:v for k,v in translated[key].items() if k != 'default'}, key)
            else:self.assertEqual(value,translated[key],key)
        self.assertEqual(set(translated)-set(original), {'LowLatencyMode'})

    def test_xml_resources(self):
        # Real plist parsing catches malformed edits, not string matching.
        for directory in ('prefs', 'layout/Library'):
            for path in (ROOT / directory).rglob('*.plist'):
                with self.subTest(path=path):
                    plistlib.loads(path.read_bytes())

    def test_editable_consistent_defaults(self):
        root = plistlib.loads((ROOT / 'prefs/TrollVNCPrefs/Resources/Root.plist').read_bytes())
        self.assertEqual(root['title'], 'ĐK ViewPhone')
        items = {item['key']: item for item in root['items'] if 'key' in item}
        expected = {'Enabled':False, 'DesktopName':'ĐK ViewPhone', 'Port':5901,
                    'BindHost':'127.0.0.1', 'Scale':0.40, 'FrameRateSpec':'30:60:120',
                    'ClipboardEnabled':True, 'OrientationSync':True, 'ViewOnly':False,
                    'BonjourEnabled':False}
        expected.update(LANWebViewerEnabled=True, WebViewerTrustedLAN=True,
                        WebViewerTLS=False, HttpPort=5801, RemoteControlEnabled=True,
                        AllowUnauthenticatedLAN=True)
        expected['LowLatencyMode'] = True
        for key, value in expected.items():
            self.assertEqual(items[key]['default'], value, key)
        for key in ('FullPassword', 'ViewOnlyPassword'):
            self.assertFalse(items[key].get('default'))
        self.assertFalse((ROOT / 'prefs/TrollVNCPrefs/Resources/Managed.plist').exists())
        self.assertTrue(all(item.get('defaults') == 'com.82flex.trollvnc' for item in items.values()))

    def test_daemon_and_bundle_references(self):
        daemon = plistlib.loads((ROOT / 'layout/Library/LaunchDaemons/com.82flex.trollvnc.plist').read_bytes())
        self.assertEqual(daemon['ProgramArguments'], ['/usr/bin/dkviewphone-watchdog'])
        self.assertEqual(daemon['UserName'], 'mobile')
        self.assertEqual(daemon['StandardOutPath'], '/dev/null')
        self.assertEqual(daemon['StandardErrorPath'], '/dev/null')
        upstream = plistlib.loads((ROOT / 'app/TrollVNC/TrollVNC/TrollVNC.entitlements').read_bytes())
        watchdog = plistlib.loads((ROOT / 'src/dkviewphone-watchdog.entitlements').read_bytes())
        self.assertTrue(all(upstream.get(key) == value for key, value in watchdog.items()))
        for bundle, executable in [('TrollVNCPrefs', 'TrollVNCPrefs'), ('CCTrollVNC','CCTrollVNC')]:
            info = plistlib.loads((ROOT / f'prefs/{bundle}/Resources/Info.plist').read_bytes())
            self.assertEqual(info['CFBundleExecutable'], executable)
            self.assertEqual(info['CFBundleDisplayName'], 'ĐK ViewPhone')

    def test_capture_and_input_engine_unchanged(self):
        for name in ('ScreenCapturer.mm','STHIDEventGenerator.mm'):
            # Compare with the exact audited upstream commit, ignoring checkout EOL.
            original = subprocess.check_output(['git','show',f'cfdb737e72977d961eb7d0a8110d2fe1a58551d7:src/{name}'], cwd=ROOT)
            actual = (ROOT / 'src' / name).read_bytes().replace(b'\r\n', b'\n')
            self.assertEqual(actual, original.replace(b'\r\n', b'\n'), name)

    def test_web_template_encoding_and_offline_entry(self):
        from html.parser import HTMLParser
        class Parser(HTMLParser):
            def __init__(self):
                super().__init__(); self.scripts = []
            def handle_starttag(self, tag, attrs):
                attrs = dict(attrs)
                if tag == 'script': self.scripts.append(attrs.get('src'))
        web = ROOT / 'layout/usr/share/trollvnc/webclients'
        html = (web / 'index.vnc').read_text(encoding='utf-8')
        self.assertIn('<title>ĐK ViewPhone · Device Farm</title>', html)
        self.assertIn('id="dashboard"', html)
        self.assertIn('id="deviceGrid"', html)
        self.assertIn('id="focusPanel"', html)
        self.assertNotIn('id="singleTab"', html)
        self.assertNotIn('id="multiTab"', html)
        self.assertNotIn('\ufffd', html)
        self.assertLess(len(html.encode()), 32768)
        parser = Parser(); parser.feed(html)
        self.assertEqual(parser.scripts, ['viewer.bundle.js'])
        for name in parser.scripts:
            self.assertGreater((web / name).stat().st_size, 10000)

    def test_notifications_are_passive_and_status_bar_build_is_disabled(self):
        bulletins = (ROOT / 'src/BulletinManager.mm').read_text(encoding='utf-8')
        pop = bulletins.split('- (void)popBannerWithContent:', 1)[1].split('- (void)revokeSingleNotification', 1)[0]
        self.assertIn('UNNotificationInterruptionLevelPassive', pop)
        self.assertNotIn('UNNotificationInterruptionLevelActive', pop)
        self.assertNotIn('defaultSound', pop)
        makefile = (ROOT / 'Makefile').read_text(encoding='utf-8')
        self.assertNotIn('SUBPROJECTS += statusbar/DKViewPhoneStatusBar', makefile)

    def test_multi_view_does_not_persist_passwords(self):
        source = (ROOT / 'layout/usr/share/trollvnc/webclients/viewer.js').read_text(encoding='utf-8')
        self.assertIn('class ManagedRfbSession', source)
        self.assertIn('class PreviewSession', source)
        self.assertIn('class DashboardManager', source)
        self.assertIn("const STORAGE_KEY = 'dk-viewphone-devices-v1'", source)
        storage_lines = [line for line in source.splitlines() if 'localStorage.setItem' in line]
        self.assertTrue(storage_lines)
        self.assertTrue(all('password' not in line.lower() for line in storage_lines))
        self.assertIn('prefs.limit = Math.min(12, Math.max(1, Number(prefs.limit) || 6))', source)
        self.assertIn("role: 'focus'", source)
        self.assertIn("role: 'preview'", source)

    def test_archive_parser_rejects_fake_deb(self):
        for raw in (b'', b'pretend deb', b'!<arch>\ntruncated'):
            with self.subTest(raw=raw), self.assertRaises(ValueError):
                validator.ar_members(raw)

    def test_macho_parser_rejects_nonbinary(self):
        with self.assertRaises(ValueError):
            validator.check_macho(b'fake binary')

    def test_signature_verifier_detects_code_tampering(self):
        # Synthetic signed data checks the verifier; no fake DEB is generated.
        code = bytes(range(64))
        directory = struct.pack('>9I4BI', 0xfade0c02, 76, 0x20200, 2, 44, 0,
                                0, 1, 64, 32, 2, 0, 6, 0) + hashlib.sha256(code).digest()
        signature = struct.pack('>5I', 0xfade0cc0, 96, 1, 0, 20) + directory
        self.assertEqual(validator.check_signature(code + signature, 64, 96), {})
        changed = bytearray(code + signature)
        changed[40] ^= 1
        with self.assertRaisesRegex(ValueError, 'signature mismatch'):
            validator.check_signature(changed, 64, 96)


if __name__ == '__main__':
    unittest.main()
