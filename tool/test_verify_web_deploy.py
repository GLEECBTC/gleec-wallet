"""Run the deploy verifier against fixture sites through a fake curl; no network.

The first test serves this repository's own wrapper assets under the headers
firebase.json declares, so a wrapper, config and verifier that drift apart fail
here rather than on the first deploy after the merge.
"""

import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / 'tool/verify_web_deploy.sh'
PAGES = 'assets/assets/web_pages'
SCRIPT_TAG = '<script src="fiat_widget.js"></script>'
UNPATCHED_SCRIPT = '''window.addEventListener('load', function () {
  const urlParam = new URLSearchParams(window.location.search).get('fiatUrl');
  const targetUrl = atob(urlParam);
  document.getElementById('fiat-onramp-iframe').src = targetUrl;
});
function relay(message) { window.parent.postMessage(message, '*'); }
'''

FAKE_CURL = r'''#!/usr/bin/env python3
import json
import os
from pathlib import Path
import sys
from urllib.parse import parse_qs, urlsplit

site = Path(os.environ['TEST_SITE'])
url = urlsplit(sys.argv[-1])
if '--dump-header' in sys.argv:
    headers = json.loads((site / 'headers.json').read_text())
    lines = ['HTTP/2 200'] + [f'{key}: {value}' for key, value in headers[url.path].items()]
    sys.stdout.write('\r\n'.join(lines) + '\r\n\r\n')
    sys.exit(0)
attempt = int(parse_qs(url.query)['cachebust'][0].split('-')[0]) if url.query else 1
if attempt <= int(os.environ.get('TEST_STALE_ATTEMPTS', '0')):
    site = Path(os.environ['TEST_STALE_SITE'])
file = site / url.path.lstrip('/')
# A missing file falls through the `**` rewrite, as it does on Firebase Hosting.
sys.stdout.write((file if file.is_file() else site / 'index.html').read_text())
'''


def hosting_headers(path):
    """The headers firebase.json gives `path`; a later matching rule wins."""
    headers = {}
    for rule in json.loads((ROOT / 'firebase.json').read_text())['hosting']['headers']:
        source = rule['source']
        if source == '**' or source == path or (
                source.endswith('/**') and path.startswith(source[:-2])):
            headers.update({item['key']: item['value'] for item in rule['headers']})
    return headers


class VerifyWebDeployTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        (self.root / 'bin').mkdir()
        curl = self.root / 'bin/curl'
        curl.write_text(FAKE_CURL)
        curl.chmod(0o755)
        self.html = (ROOT / 'assets/web_pages/fiat_widget.html').read_text()
        self.script = (ROOT / 'assets/web_pages/fiat_widget.js').read_text()
        self.site = self.make_site('site', self.html, self.script)
        self.env = dict(os.environ,
                        PATH=str(self.root / 'bin') + os.pathsep + os.environ['PATH'],
                        TEST_SITE=str(self.site), VERIFY_ATTEMPTS='1',
                        VERIFY_RETRY_DELAY='0')

    def make_site(self, name, html, script):
        site = self.root / name
        (site / PAGES).mkdir(parents=True)
        (site / 'index.html').write_text('<!DOCTYPE html>\n<html><title>Gleec Dex</title></html>\n')
        (site / 'version.json').write_text('{"version":"0.0.0"}')
        (site / PAGES / 'fiat_widget.html').write_text(html)
        if script is not None:
            (site / PAGES / 'fiat_widget.js').write_text(script)
        self.write_headers(site)
        return site

    def write_headers(self, site, **overrides):
        paths = ['/', f'/{PAGES}/fiat_widget.html', f'/{PAGES}/fiat_widget.js']
        headers = {path: hosting_headers(path) for path in paths}
        for path, values in overrides.items():
            headers[f'/{PAGES}/{path}'].update(values)
        (site / 'headers.json').write_text(json.dumps(headers))

    def verify(self, **environment):
        return subprocess.run(['bash', str(SCRIPT), 'https://fixture.invalid'],
                              env={**self.env, **environment}, text=True,
                              capture_output=True)

    def assert_fails(self, result, *reasons):
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        for reason in reasons:
            self.assertIn('FAIL  ' + reason, result.stdout)
        self.assertNotIn('PASS', result.stdout)

    def assert_no_script_check_passed(self, result):
        for check in ('allowlist is present', 'no unvalidated atob()',
                      'postMessage target origin is pinned'):
            self.assertNotIn(check, result.stdout)

    def test_repository_wrapper_and_hosting_config_pass(self):
        result = self.verify()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertNotIn('FAIL', result.stdout)
        for check in ('wrapper page loads fiat_widget.js',
                      'checkout URL allowlist is present',
                      'no unvalidated atob() -> iframe.src sink',
                      'postMessage target origin is pinned',
                      'fiat_widget.html cache-control:',
                      'fiat_widget.js cache-control:'):
            self.assertIn('ok    ' + check, result.stdout)

    def test_missing_script_fails_closed(self):
        (self.site / PAGES / 'fiat_widget.js').unlink()
        result = self.verify()
        self.assert_fails(result, f'/{PAGES}/fiat_widget.js did not serve the wrapper script')
        self.assert_no_script_check_passed(result)

    def test_page_that_does_not_load_the_script_fails_closed(self):
        # The layout before the script moved out of the page: patched, but not
        # where the checks look, and not runnable under the site's CSP.
        inline = self.html.replace(SCRIPT_TAG, '<script>' + self.script + '</script>')
        self.site = self.make_site('inline', inline, None)
        result = self.verify(TEST_SITE=str(self.site))
        self.assert_fails(result, 'wrapper page does not load fiat_widget.js')
        self.assert_no_script_check_passed(result)

    def test_unpatched_script_fails_every_script_check(self):
        (self.site / PAGES / 'fiat_widget.js').write_text(UNPATCHED_SCRIPT)
        self.assert_fails(self.verify(),
                          'checkout URL allowlist is MISSING',
                          'unvalidated atob() -> iframe.src sink is still present',
                          'wrapper still broadcasts postMessage with a wildcard target origin')

    def test_inline_script_in_the_page_is_still_inspected(self):
        page = self.html.replace(SCRIPT_TAG, SCRIPT_TAG + '<script>' + UNPATCHED_SCRIPT + '</script>')
        (self.site / PAGES / 'fiat_widget.html').write_text(page)
        result = self.verify()
        self.assert_fails(result,
                          'unvalidated atob() -> iframe.src sink is still present',
                          'wrapper still broadcasts postMessage with a wildcard target origin')
        self.assertIn('ok    checkout URL allowlist is present', result.stdout)

    def test_script_that_is_cached_without_revalidation_fails(self):
        self.write_headers(self.site, **{'fiat_widget.js': {'Cache-Control': 'public, max-age=3600'}})
        result = self.verify()
        self.assert_fails(result, "fiat_widget.js cache-control is 'public, max-age=3600'")
        self.assertIn('ok    fiat_widget.html cache-control:', result.stdout)

    def test_retries_past_a_stale_copy_of_the_previous_build(self):
        stale = self.make_site('stale', self.html.replace(SCRIPT_TAG, ''), None)
        result = self.verify(TEST_STALE_SITE=str(stale), TEST_STALE_ATTEMPTS='1',
                             VERIFY_ATTEMPTS='2')
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn('fiat_widget.html not updated yet (attempt 1/2)', result.stderr)


if __name__ == '__main__':
    unittest.main()
