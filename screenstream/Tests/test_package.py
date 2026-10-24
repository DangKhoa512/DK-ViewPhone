import importlib.util
from pathlib import Path
import plistlib
import unittest

ROOT=Path(__file__).resolve().parents[1]
class PackageTests(unittest.TestCase):
    def test_xml_and_resource_identity(self):
        for path in ROOT.rglob('*.plist'):
            with self.subTest(path=path): plistlib.loads(path.read_bytes())
        daemon=plistlib.loads((ROOT/'layout/Library/LaunchDaemons/com.dk.screenstream.plist').read_bytes())
        self.assertEqual(daemon['Label'],'com.dk.screenstream')
        self.assertEqual(daemon['ProgramArguments'],['/usr/bin/dkss-supervisor'])
        self.assertEqual(daemon['UserName'],'mobile')
        settings=plistlib.loads((ROOT/'Preferences/Resources/Root.plist').read_bytes())
        items={item['key']:item for item in settings['items'] if 'key' in item}
        self.assertFalse(items['Enabled']['default'])
        self.assertNotIn('Token',items)
        self.assertEqual({item['defaults'] for item in items.values()},{'com.dk.screenstream'})
    def test_package_source_is_separate(self):
        self.assertNotIn('Conflicts:',(ROOT/'control').read_text(encoding='utf-8'))
        self.assertNotIn('rootless-compat',(ROOT/'control').read_text(encoding='utf-8'))
        for path in (ROOT/'layout/DEBIAN').iterdir():
            text=path.read_text(encoding='utf-8')
            self.assertNotIn('com.dk.viewphone',text)
            self.assertNotIn('/var/jb',text)
            self.assertIn('com.dk.screenstream',text)
        token_defaults=[item for item in items_from_plist() if item.get('key')=='Token']
        self.assertEqual(token_defaults,[])
def items_from_plist():
    return plistlib.loads((ROOT/'Preferences/Resources/Root.plist').read_bytes())['items']
if __name__=='__main__': unittest.main()
