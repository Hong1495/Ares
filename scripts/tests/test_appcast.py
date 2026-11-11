import base64
import importlib.util
from pathlib import Path
import tempfile
import unittest
import xml.etree.ElementTree as ET

spec = importlib.util.spec_from_file_location('appcast', Path(__file__).parents[1] / 'create-appcast.py')
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class AppcastTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.archive = Path(self.directory.name) / 'Ares-v1.1.0-arm64.zip'
        self.archive.write_bytes(b'fixture-not-a-real-update')
        self.args = dict(repository='Hong1495/Ares', tag='v1.1.0', version='1.1.0', build='201', archive=self.archive, signature=base64.b64encode(bytes(64)).decode())

    def test_versions_url_length_and_signature(self):
        root = ET.fromstring(module.appcast(**self.args))
        item = root.find('channel/item')
        self.assertEqual(item.find(f'{{{module.SPARKLE}}}version').text, '201')
        enclosure = item.find('enclosure')
        self.assertTrue(enclosure.attrib['url'].endswith('/v1.1.0/Ares-v1.1.0-arm64.zip'))
        self.assertEqual(int(enclosure.attrib['length']), self.archive.stat().st_size)
        self.assertEqual(enclosure.attrib[f'{{{module.SPARKLE}}}edSignature'], self.args['signature'])

    def test_invalid_or_missing_signature_rejected(self):
        for signature in ['', 'bad', base64.b64encode(bytes(32)).decode()]:
            with self.assertRaises(ValueError):
                module.appcast(**dict(self.args, signature=signature))

    def test_prerelease_and_mismatched_version_rejected(self):
        for tag in ['v1.1.0-beta', 'v1.2.0', '1.1.0']:
            with self.assertRaises(ValueError): module.appcast(**dict(self.args, tag=tag))

    def test_release_notes_are_escaped(self):
        notes = '<script>bad</script> & details'
        root = ET.fromstring(module.appcast(**self.args, notes=notes))
        self.assertEqual(root.find('channel/item/description').text, notes)
        self.assertIsNone(root.find('.//script'))

    def test_empty_archive_rejected(self):
        self.archive.write_bytes(b'')
        with self.assertRaises(ValueError): module.appcast(**self.args)

    def test_initial_build_is_not_valid_update(self):
        with self.assertRaises(ValueError): module.appcast(**dict(self.args, build='1'))
