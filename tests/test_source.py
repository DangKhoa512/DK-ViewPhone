import importlib.util
import plistlib
from pathlib import Path
import subprocess
import struct
import hashlib
import unittest

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('validator', ROOT / 'devkit/verify-package.py')
validator = importlib.util.module_from_spec(spec)
spec.loader.exec_module(validator)


class SourceTests(unittest.TestCase):
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
                    'BindHost':'127.0.0.1', 'Scale':0.75, 'FrameRateSpec':'15:30:30',
                    'ClipboardEnabled':True, 'OrientationSync':True, 'ViewOnly':False,
                    'BonjourEnabled':False}
        expected.update(LANWebViewerEnabled=False, WebViewerTrustedLAN=False,
                        WebViewerTLS=False, HttpPort=5801, RemoteControlEnabled=True)
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
        self.assertIn('<title>ĐK ViewPhone · LAN Viewer</title>', html)
        self.assertNotIn('\ufffd', html)
        self.assertLess(len(html.encode()), 32768)
        parser = Parser(); parser.feed(html)
        self.assertEqual(parser.scripts, ['viewer.bundle.js'])
        for name in parser.scripts:
            self.assertGreater((web / name).stat().st_size, 10000)

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
