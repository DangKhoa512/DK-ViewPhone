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
        changed_defaults = {'Scale','FrameRateSpec','AllowUnauthenticatedLAN','LANWebViewerEnabled','WebViewerTrustedLAN',
                            'BindHost','SingleNotifEnabled','ClientNotifsEnabled'}
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
                    'BindHost':'auto', 'Scale':0.40, 'FrameRateSpec':'30:30:30',
                    'ClipboardEnabled':True, 'OrientationSync':True, 'ViewOnly':False,
                    'BonjourEnabled':False, 'SingleNotifEnabled':False, 'ClientNotifsEnabled':False}
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
                super().__init__()
                self.scripts, self.inline_scripts, self.unsafe_attributes, self.ids = [], [], [], []
                self.in_script, self.live_limit = False, None
            def handle_starttag(self, tag, attrs):
                attrs = dict(attrs)
                if tag == 'script':
                    self.scripts.append(attrs.get('src'))
                    self.in_script = True
                if 'id' in attrs: self.ids.append(attrs['id'])
                if attrs.get('id') == 'liveLimit': self.live_limit = attrs
                for key, value in attrs.items():
                    if key.startswith('on') or (value or '').strip().lower().startswith('javascript:'):
                        self.unsafe_attributes.append((tag, key))
            def handle_endtag(self, tag):
                if tag == 'script': self.in_script = False
            def handle_data(self, data):
                if self.in_script and data.strip(): self.inline_scripts.append(data)
        web = ROOT / 'layout/usr/share/trollvnc/webclients'
        for path in (ROOT / 'devkit/webviewer-index.html', web / 'index.vnc'):
            with self.subTest(path=path):
                html = path.read_text(encoding='utf-8')
                self.assertIn('<title>ĐK ViewPhone · Device Farm</title>', html)
                self.assertNotIn('\ufffd', html)
                self.assertLess(len(html.encode('utf-8')), 32768,
                                'LibVNCServer template substitution uses a 32 KiB buffer')
                parser = Parser(); parser.feed(html)
                self.assertTrue({'dashboard', 'deviceGrid', 'focusPanel'}.issubset(parser.ids))
                self.assertTrue({'singleTab', 'multiTab'}.isdisjoint(parser.ids))
                self.assertEqual(len(parser.ids), len(set(parser.ids)), 'Duplicate element IDs')
                self.assertEqual(parser.scripts, ['viewer.bundle.js'])
                self.assertEqual(parser.inline_scripts, [])
                self.assertEqual(parser.unsafe_attributes, [])
                self.assertIsNotNone(parser.live_limit)
                self.assertEqual({key: parser.live_limit.get(key) for key in ('min', 'max', 'value')},
                                 {'min': '1', 'max': '10', 'value': '10'})
        self.assertGreater((web / 'viewer.bundle.js').stat().st_size, 10000)

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
        # Presentation roles and their input restrictions are exercised by the
        # Node behavioral suite; a focus no longer constructs a second session.

    def test_live_limit_is_bounded(self):
        source = (ROOT / 'layout/usr/share/trollvnc/webclients/viewer.js').read_text(encoding='utf-8')
        # Exercise the actual saved-preference and input normalization expressions,
        # allowing formatting changes without weakening the session-budget check.
        script = r"""
const assert = require('node:assert/strict');
const {readFileSync} = require('node:fs');
const {runInNewContext} = require('node:vm');
const source = readFileSync(0, 'utf8');
const expressions = [...source.matchAll(/\bprefs\.limit\s*=\s*([^;\n]+);/g)]
    .map(match => match[1]);
assert.ok(expressions.length, 'Missing live-session limit normalization');
const cases = [[-100, 1], [1, 1], [5, 5], [10, 10], [11, 10], [1000, 10],
    ['6', 6], [undefined, 10], [null, 10], ['', 10], ['invalid', 10]];
for (const expression of expressions) {
    for (const [input, expected] of cases) {
        const actual = runInNewContext(expression, {
            prefs: {limit: input}, $: () => ({value: input}),
        });
        assert.equal(actual, expected, `Live limit input ${String(input)}`);
    }
}
"""
        subprocess.run(['node', '-e', script], input=source, encoding='utf-8', check=True, cwd=ROOT)

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
