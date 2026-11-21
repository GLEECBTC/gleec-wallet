import os
from pathlib import Path
import subprocess
import tempfile
import unittest
import zipfile

SCRIPT = Path(__file__).resolve().parents[1] / '.github/scripts/render_coverage.sh'


class CoverageReportTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        (self.root / 'bin').mkdir()
        (self.root / 'coverage').mkdir()
        self.lcov = self.root / 'coverage/lcov.info'
        self.lcov.write_text('TN:\nSF:lib/example.dart\nDA:1,1\nLF:1\nLH:1\nend_of_record\n')
        self.binary('genhtml', 'mkdir -p coverage/html; echo public-report > coverage/html/index.html')
        self.binary('flutter', 'touch unexpected-test-rerun; exit 99')
        self.env = dict(os.environ, PATH=str(self.root / 'bin') + os.pathsep + os.environ['PATH'])

    def binary(self, name, body):
        file = self.root / 'bin' / name
        file.write_text('#!/usr/bin/env bash\nset -euo pipefail\n' + body + '\n')
        file.chmod(0o755)

    def run_report(self):
        return subprocess.run(['bash', str(SCRIPT)], cwd=self.root, env=self.env,
                              text=True, capture_output=True)

    def test_reuses_passing_result_and_excludes_stale_html(self):
        previous = self.lcov.read_bytes()
        (self.root / 'coverage/html').mkdir()
        (self.root / 'coverage/html/stale.html').write_text('old-report')
        result = self.run_report()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.lcov.read_bytes(), previous)
        self.assertFalse((self.root / 'unexpected-test-rerun').exists())
        with zipfile.ZipFile(self.root / 'coverage-html.zip') as archive:
            self.assertIn('coverage/html/index.html', archive.namelist())
            self.assertNotIn('coverage/html/stale.html', archive.namelist())

    def test_missing_lcov_cannot_publish(self):
        self.lcov.unlink()
        self.assertNotEqual(self.run_report().returncode, 0)
        self.assertFalse((self.root / 'coverage-html.zip').exists())

    def test_report_failure_cannot_publish(self):
        self.binary('genhtml', 'exit 7')
        self.assertEqual(self.run_report().returncode, 7)
        self.assertFalse((self.root / 'coverage-html.zip').exists())

    def test_archive_failure_propagates(self):
        self.binary('zip', 'exit 9')
        self.assertEqual(self.run_report().returncode, 9)


if __name__ == '__main__':
    unittest.main()
