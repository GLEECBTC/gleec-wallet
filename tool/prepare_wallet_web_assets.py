#!/usr/bin/env python3
"""Extract only the audited offline-game scripts under the wallet's strict CSP."""
import argparse
import hashlib
from pathlib import Path
import re

HELPER = Path('assets/packages/flutter_inappwebview/assets/t_rex_runner/t-rex.html')
SOURCE_SHA256 = 'dc72cfc1f1d2a5013bb9de34f8cacf5e26e542d7d713fcbe09b865b4aaca6ddf'
SCRIPTS = (
    ('gleec-t-rex-runner.js', 'e9fd467a8909b72b964722c36a482d67e6f3572ba019746213730007795a3370'),
    ('gleec-t-rex-start.js', '876d05568acedca7749139d2472cae26cb880523132d0c433e186406a2641184'),
)
PATTERN = re.compile(r'<script\b([^>]*)>([\s\S]*?)</script>', re.IGNORECASE)


def digest(text):
    return hashlib.sha256(text.encode('utf-8')).hexdigest()


def prepare(root):
    helper = root / HELPER
    source = helper.read_bytes().decode('utf-8')
    if digest(source) != SOURCE_SHA256:
        # Verify an already transformed build, including its external scripts.
        restored = source
        for name, expected in SCRIPTS:
            script = (helper.parent / name).read_bytes().decode('utf-8')
            if digest(script) != expected:
                raise ValueError('An extracted offline-game script changed')
            tag = f'<script src="{name}"></script>'
            if restored.count(tag) != 1:
                raise ValueError('Offline-game markup changed; review the dependency')
            restored = restored.replace(tag, '<script>' + script + '</script>')
        if digest(restored) != SOURCE_SHA256:
            raise ValueError('Offline-game markup changed; review the dependency')
        return
    matches = list(PATTERN.finditer(source))
    if len(matches) != len(SCRIPTS):
        raise ValueError('Unexpected offline-game script count')
    for match, (name, expected) in zip(matches, SCRIPTS):
        if match.group(1).strip() or digest(match.group(2)) != expected:
            raise ValueError('Offline-game scripts changed; review the dependency')
    # Write the HTML last. The dependency source and strict global CSP stay intact.
    for match, (name, _) in zip(matches, SCRIPTS):
        (helper.parent / name).write_bytes(match.group(2).encode('utf-8'))
    replacements = iter(name for name, _ in SCRIPTS)
    helper.write_bytes(PATTERN.sub(
        lambda _: f'<script src="{next(replacements)}"></script>', source
    ).encode('utf-8'))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('web_root', type=Path)
    args = parser.parse_args()
    try:
        prepare(args.web_root)
    except (OSError, UnicodeError, ValueError) as error:
        parser.error(str(error))
    print('Audited offline-game scripts are self-hosted; strict CSP is unchanged.')


if __name__ == '__main__':
    main()
