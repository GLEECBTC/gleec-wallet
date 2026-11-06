"""Build evidence must identify the public profile and actual artifact bytes."""

import hashlib
import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from lifi_build_config import PUBLIC_DEFAULTS, PROFILES
from lifi_build_provenance import record, verify


class BuildProvenanceTest(unittest.TestCase):
    def test_cli_rejects_invalid_release_without_printing_its_value(self):
        script = Path(__file__).with_name('lifi_build_provenance.py')
        result = subprocess.run([sys.executable, str(script), 'production',
                                 '--artifact', 'build/web', '--verify', 'unused-evidence',
                                 '--expected-commit', 'not-a-real-secret'],
                                capture_output=True, text=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(result.stdout, '')
        self.assertIn('provenance check failed', result.stderr)
        self.assertNotIn('not-a-real-secret', result.stderr)

    def test_profile_dependency_snapshot_and_artifact_hash(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            fixture = {
                PROFILES['production'][0]: json.dumps({**PUBLIC_DEFAULTS, 'LIFI_INTEGRATOR_NAME': 'gleec-dex-production'}),
                PROFILES['staging'][0]: json.dumps({**PUBLIC_DEFAULTS, 'LIFI_INTEGRATOR_NAME': 'gleec-dex-staging'}),
                'pubspec.lock': 'public resolved Wallet dependencies',
                'sdk/pubspec.lock': 'public resolved SDK dependencies',
                '.fvmrc': json.dumps({'flutter': '3.41.4'}),
                'sdk/packages/komodo_defi_framework/app_build/build_config.json': json.dumps({
                    'api': {'api_commit_hash': 'a' * 40},
                    'coins': {'bundled_coins_repo_commit': 'b' * 40}}),
                'build/example/app.bin': 'compiled artifact',
            }
            for name, value in fixture.items():
                path = root / name
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text(value)
            with patch('lifi_build_provenance.subprocess.check_output', return_value='c' * 40):
                record('production', 'build/example/*', Path('evidence'), root)
            result = json.loads((root / 'evidence/build.json').read_text())
            self.assertEqual(result['lifi_environment'], 'production')
            self.assertEqual(result['lifi_build_defines']['LIFI_INTEGRATOR_NAME'], 'gleec-dex-production')
            digest = hashlib.sha256(b'compiled artifact').hexdigest()
            self.assertEqual(result['artifact_sha256'], {'build/example/app.bin': digest})
            self.assertEqual((root / 'evidence/wallet-pubspec.lock').read_text(), fixture['pubspec.lock'])
            self.assertIn('sdk-pubspec.lock', result['dependency_snapshots'])
            with patch('lifi_build_provenance.subprocess.check_output', return_value='c' * 40):
                verify('production', 'build/example/*', Path('evidence'), 'c' * 40, root)
                for expected in ['d' * 40, '', None, 'short-sha']:
                    with self.subTest(expected=expected), self.assertRaises(ValueError):
                        verify('production', 'build/example/*', Path('evidence'), expected, root)
                with self.assertRaises(ValueError):
                    verify('staging', 'build/example/*', Path('evidence'), 'c' * 40, root)

                # Reject stale/tampered inputs, missing files and unrecorded
                # files in the directory about to be published.
                for source in ['build/example/app.bin', 'pubspec.lock',
                               'sdk/pubspec.lock', 'evidence/wallet-pubspec.lock']:
                    with self.subTest(source=source):
                        path = root / source
                        saved = path.read_text()
                        path.write_text('changed')
                        with self.assertRaises(ValueError):
                            verify('production', 'build/example/*', Path('evidence'), 'c' * 40, root)
                        path.write_text(saved)
                extra = root / 'build/example/stale.js'
                extra.write_text('unrecorded')
                with self.assertRaises(ValueError):
                    verify('production', 'build/example/*', Path('evidence'), 'c' * 40, root)
                extra.unlink()
                artifact = root / 'build/example/app.bin'
                artifact.unlink()
                with self.assertRaises(ValueError):
                    verify('production', 'build/example/*', Path('evidence'), 'c' * 40, root)
                artifact.write_text(fixture['build/example/app.bin'])

                for field, value in [('sdk_commit', 'd' * 40), ('kdf_commit', 'd' * 40),
                                     ('lifi_environment', 'staging'),
                                     ('lifi_build_defines', {**PUBLIC_DEFAULTS, 'LIFI_FEE_BPS': '25'}),
                                     ('dependency_snapshots', {'../private.env': 'not-a-real-secret'})]:
                    with self.subTest(field=field):
                        (root / 'evidence/build.json').write_text(json.dumps({**result, field: value}))
                        with self.assertRaises(ValueError):
                            verify('production', 'build/example/*', Path('evidence'), 'c' * 40, root)
                (root / 'evidence/build.json').write_text(json.dumps(result))
            with patch('lifi_build_provenance.subprocess.check_output', side_effect=['c' * 40, 'd' * 40]):
                with self.assertRaises(ValueError):
                    record('production', 'build/example/*', Path('evidence'), root)
            with self.assertRaises(ValueError):
                record('production', 'build/missing/*', Path('evidence'), root)
            (root / 'build/example/external').symlink_to(root / 'pubspec.lock')
            with self.assertRaises(ValueError):
                record('production', 'build/example/*', Path('evidence'), root)


if __name__ == '__main__':
    unittest.main()
