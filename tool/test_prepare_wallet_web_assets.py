import hashlib
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

import prepare_wallet_web_assets as assets


class PublicWebAssetsTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.helper = self.root / assets.HELPER
        self.helper.parent.mkdir(parents=True)
        self.bodies = ['window.auditedRunner = true;', 'window.auditedStart = true;']
        self.source = '<html>' + ''.join('<script>' + s + '</script>' for s in self.bodies) + '</html>'
        self.helper.write_text(self.source)
        scripts = tuple((name, hashlib.sha256(body.encode()).hexdigest())
                        for (name, _), body in zip(assets.SCRIPTS, self.bodies))
        for name, value in [('SOURCE_SHA256', assets.digest(self.source)), ('SCRIPTS', scripts)]:
            context = patch.object(assets, name, value)
            context.start()
            self.addCleanup(context.stop)

    def test_audited_scripts_are_external_and_repeat_validation_is_safe(self):
        assets.prepare(self.root)
        for (name, _), body in zip(assets.SCRIPTS, self.bodies):
            self.assertEqual((self.helper.parent / name).read_text(), body)
            self.assertIn(f'<script src="{name}"></script>', self.helper.read_text())
        transformed = self.helper.read_bytes()
        assets.prepare(self.root)
        self.assertEqual(self.helper.read_bytes(), transformed)

    def test_changed_dependency_is_rejected_without_rewriting_it(self):
        changed = self.source.replace('auditedRunner', 'unreviewedRunner')
        self.helper.write_text(changed)
        with self.assertRaises((ValueError, OSError)):
            assets.prepare(self.root)
        self.assertEqual(self.helper.read_text(), changed)
        self.assertFalse((self.helper.parent / assets.SCRIPTS[0][0]).exists())

    def test_modified_extracted_script_is_rejected(self):
        assets.prepare(self.root)
        (self.helper.parent / assets.SCRIPTS[0][0]).write_text('unreviewed();')
        with self.assertRaises(ValueError):
            assets.prepare(self.root)

    def test_additional_script_cannot_bypass_repeat_validation(self):
        assets.prepare(self.root)
        self.helper.write_text(self.helper.read_text() + '<script>unreviewed();</script>')
        with self.assertRaises(ValueError):
            assets.prepare(self.root)


if __name__ == '__main__':
    unittest.main()
