"""Exercise the actual CI signing writer using synthetic inputs only."""

import base64
import os
from pathlib import Path
import stat
import subprocess
import sys
import tempfile
import textwrap
import unittest


ACTION = Path(__file__).resolve().parents[1] / '.github/actions/releases/setup-android/action.yml'


class AndroidSigningActionTest(unittest.TestCase):
    def test_literal_values_and_private_file_permissions(self):
        text = ACTION.read_text()
        code = text.split("        python3 - <<'PY'\n", 1)[1].split('        PY\n', 1)[0]
        code = textwrap.dedent(code)
        values = {
            'GLEEC_SIGNING_KEYSTORE': base64.b64encode(b'synthetic-keystore').decode(),
            'GLEEC_SIGNING_ALIAS': 'Alias-$()`雪',
            'GLEEC_SIGNING_STORE_PASSWORD': 'Synthet!c$\\value\n☃',
            'GLEEC_SIGNING_KEY_PASSWORD': ' Leading space:=`$()𝄞',
        }
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / 'android/app').mkdir(parents=True)
            result = subprocess.run([sys.executable, '-c', code], cwd=root,
                env={**os.environ, **values}, capture_output=True, text=True)
            self.assertEqual(result.returncode, 0)
            self.assertEqual(result.stdout + result.stderr, '')
            self.assertEqual((root / 'android/app/upload-keystore.jks').read_bytes(), b'synthetic-keystore')
            for path in ['android/app/upload-keystore.jks', 'android/key.properties']:
                self.assertEqual(stat.S_IMODE((root / path).stat().st_mode), 0o600)
            properties = dict(line.split('=', 1) for line in
                (root / 'android/key.properties').read_text().splitlines())
            for key, env_key in [('keyAlias', 'GLEEC_SIGNING_ALIAS'),
                                 ('storePassword', 'GLEEC_SIGNING_STORE_PASSWORD'),
                                 ('keyPassword', 'GLEEC_SIGNING_KEY_PASSWORD')]:
                # Decode Java Unicode escapes, including surrogate pairs.
                units = properties[key].split('\\u')[1:]
                decoded = bytes.fromhex(''.join(units)).decode('utf-16-be')
                self.assertEqual(decoded, values[env_key])
            result = subprocess.run([sys.executable, '-c', code], cwd=root,
                env={**os.environ, **values, 'GLEEC_SIGNING_KEYSTORE': 'invalid!'},
                capture_output=True, text=True)
            self.assertNotEqual(result.returncode, 0)
            for value in values.values():
                self.assertNotIn(value, result.stdout + result.stderr)


if __name__ == '__main__':
    unittest.main()
