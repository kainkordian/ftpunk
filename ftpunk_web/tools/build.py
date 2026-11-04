#!/usr/bin/env python3
"""Export the dependency-free app as a static site. No source outside this folder is needed."""
from pathlib import Path
import shutil
import json

ROOT = Path(__file__).resolve().parents[1]
DESTINATION = ROOT / 'dist'
# Only generated files are replaced. Source, browser data, and tests stay untouched.
DESTINATION.mkdir(exist_ok=True)
for name in ('index.html', 'manifest.webmanifest', 'sw.js'):
    shutil.copy2(ROOT / name, DESTINATION / name)
for directory in ('src', 'assets'):
    shutil.copytree(ROOT / directory, DESTINATION / directory, dirs_exist_ok=True)
manifest = json.loads((DESTINATION / 'manifest.webmanifest').read_text())
assert all((DESTINATION / icon['src']).is_file() for icon in manifest['icons'])
print(f'Static site exported to {DESTINATION}')
print('Deploy this directory to an HTTPS static host, or run: python3 tools/serve.py --dist')
