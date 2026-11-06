#!/usr/bin/env python3
"""Run every check for the web app without Node.

1. Static checks: relative imports resolve inside this folder, every module is reachable from src/app.mjs,
   index.html and manifest references exist, the service worker precaches every runtime file.
2. Start tools/serve.py in test mode, open /tests/ in headless Google Chrome (real IndexedDB, DOMParser,
   WebCrypto) and wait for the page to POST its result. Exit code is non-zero on any failure or after 5 minutes.
"""
from pathlib import Path
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import threading
import time

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(Path(__file__).resolve().parent))
import serve  # noqa: E402

TIMEOUT = 300
CHROME_CANDIDATES = ['/Applications/Google Chrome.app/Contents/MacOS/Google Chrome']
IMPORT = re.compile(r"""(?:\bfrom\s*|\bimport\s*\(\s*|\bimport\s+)['"]([^'"]+)['"]""")


def chrome_path():
    for candidate in CHROME_CANDIDATES:
        if Path(candidate).is_file():
            return candidate
    for name in ('google-chrome', 'google-chrome-stable', 'chromium', 'chromium-browser'):
        found = shutil.which(name)
        if found:
            return found
    sys.exit('Google Chrome was not found. Install Chrome or put google-chrome / chromium on PATH.')


def runtime_files():
    files = sorted((ROOT / 'src').rglob('*'))
    return [p for p in files if p.suffix in ('.mjs', '.css')]


def static_checks():
    problems = []
    sources = sorted((ROOT / 'src').rglob('*.mjs')) + [ROOT / 'sw.js'] + sorted((ROOT / 'tests').glob('*.mjs'))
    graph = {}
    for file in sources:
        text = file.read_text()
        graph[file] = []
        for target in IMPORT.findall(text):
            if not target.startswith('.'):
                problems.append(f'{file.relative_to(ROOT)}: runtime dependency is not self-contained: {target}')
                continue
            path = (file.parent / target).resolve()
            if ROOT not in path.parents:
                problems.append(f'{file.relative_to(ROOT)}: import escapes ftpunk_web: {target}')
            elif not path.is_file():
                problems.append(f'{file.relative_to(ROOT)}: import does not exist: {target}')
            else:
                graph[file].append(path)
        for banned in ('node:', 'process.'):
            if banned in text:
                problems.append(f'{file.relative_to(ROOT)}: Node-only code ({banned})')
    # Reachability from the entry point (catches orphaned modules).
    seen, stack = set(), [ROOT / 'src' / 'app.mjs']
    while stack:
        current = stack.pop()
        if current in seen:
            continue
        seen.add(current)
        stack.extend(graph.get(current, []))
    for file in sorted((ROOT / 'src').rglob('*.mjs')):
        if file.resolve() not in seen:
            problems.append(f'{file.relative_to(ROOT)}: not imported by anything reachable from src/app.mjs (dead code?)')
    worker = (ROOT / 'sw.js').read_text()
    for file in runtime_files():
        if f"'./{file.relative_to(ROOT)}'" not in worker:
            problems.append(f'sw.js: runtime file missing from the offline cache: {file.relative_to(ROOT)}')
    for listed in re.findall(r"'\./([^']+)'", worker):
        if not (ROOT / listed).exists():
            problems.append(f'sw.js: cached file does not exist: {listed}')
    html = (ROOT / 'index.html').read_text()
    for target in re.findall(r'(?:src|href)="([^"#]+)"', html):
        if not target.startswith(('http', 'data:')) and not (ROOT / target).exists():
            problems.append(f'index.html: missing {target}')
        if target.startswith('http'):
            problems.append(f'index.html: external resource {target}')
    for css in (ROOT / 'src').rglob('*.css'):
        if f'src/{css.relative_to(ROOT / "src")}' not in html and f"'./src/{css.relative_to(ROOT / 'src')}'" not in worker:
            problems.append(f'{css.relative_to(ROOT)}: stylesheet is not used')
        if re.search(r'url\(\s*[\'"]?https?:', css.read_text()) or '@import' in css.read_text():
            problems.append(f'{css.relative_to(ROOT)}: external CSS resource')
    # The story is scratched: none of its words may appear in the screens or the page.
    story = re.compile(r'Cyclepunk|Lowline|Last Light|\bXP\b|\bCity\b', re.I if False else 0)
    for file in [ROOT / 'index.html', *sorted((ROOT / 'src' / 'ui').rglob('*'))]:
        if file.is_file():
            for number, line in enumerate(file.read_text().splitlines(), 1):
                if story.search(line) or re.search(r'cyclepunk|lowline|last light', line, re.I):
                    problems.append(f'{file.relative_to(ROOT)}:{number}: story wording ({story.search(line) and story.search(line).group(0) or "story"})')
    # Fixtures written by Swift tests live in contracts/fixtures/; the web keeps byte-identical copies so its suite stays self-contained.
    shared = ROOT.parent / 'contracts' / 'fixtures'
    if shared.is_dir():
        for source in sorted(shared.glob('*.json')):
            copy = ROOT / 'tests' / 'fixtures' / source.name
            if not copy.is_file():
                problems.append(f'tests/fixtures/{source.name}: missing copy of contracts/fixtures/{source.name}')
            elif copy.read_bytes() != source.read_bytes():
                problems.append(f'tests/fixtures/{source.name}: differs from contracts/fixtures/{source.name} (copy it again; never edit a fixture by hand)')
    manifest = json.loads((ROOT / 'manifest.webmanifest').read_text())
    for icon in manifest['icons']:
        if not (ROOT / icon['src']).is_file():
            problems.append(f'manifest icon missing: {icon["src"]}')
    return problems, len(sources)


def run_browser():
    server, results = serve.make_server(ROOT, 0, test=True)
    port = server.server_address[1]
    threading.Thread(target=server.serve_forever, daemon=True).start()
    profile = tempfile.mkdtemp(prefix='ftpunk-chrome-', dir=os.environ.get('FTPUNK_TMP'))
    # GitHub-hosted Ubuntu runners restrict the unprivileged user namespaces Chrome's sandbox needs ("No usable sandbox"), and the
    # runner is a throwaway VM that only opens this app's own test page, so the sandbox is switched off there (CI=true) and nowhere else.
    sandbox = ['--no-sandbox'] if os.environ.get('CI') else []
    log = Path(profile) / 'chrome.log'
    chrome = subprocess.Popen(
        [chrome_path(), '--headless=new', f'--user-data-dir={profile}', '--remote-debugging-port=0', '--no-first-run',
         '--no-default-browser-check', '--disable-gpu', '--disable-extensions', '--disable-background-networking', *sandbox,
         f'http://localhost:{port}/tests/'],
        stdout=subprocess.DEVNULL, stderr=log.open('wb'), start_new_session=True)
    try:
        deadline = time.time() + TIMEOUT
        while time.time() < deadline:
            if results:
                return results[0]
            if chrome.poll() is not None:
                tail = log.read_text(errors='replace').strip().splitlines()[-15:] if log.exists() else []
                return {'passed': 0, 'failed': 1, 'failures': ['Chrome exited before the suite reported a result.', *tail]}
            time.sleep(0.25)
        tail = log.read_text(errors='replace').strip().splitlines()[-15:] if log.exists() else []
        return {'passed': 0, 'failed': 1, 'failures': [f'Timed out after {TIMEOUT} seconds without a result.', *tail]}
    finally:
        try:
            os.killpg(chrome.pid, 9)
        except ProcessLookupError:
            pass
        chrome.wait()
        server.shutdown()
        server.server_close()
        shutil.rmtree(profile, ignore_errors=True)


def main():
    problems, count = static_checks()
    for problem in problems:
        print('FAIL static:', problem)
    if problems:
        sys.exit(1)
    print(f'Static checks passed for {count} scripts, imports, assets, service worker list and manifest.')
    result = run_browser()
    for failure in result.get('failures', []):
        print('FAIL', failure)
    for line in result.get('notes', []):
        print(line)
    print(f"{result['passed']} passed; {result['failed']} failed.")
    sys.exit(1 if result['failed'] else 0)


if __name__ == '__main__':
    main()
