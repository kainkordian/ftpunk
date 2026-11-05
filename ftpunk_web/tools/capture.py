#!/usr/bin/env python3
"""Capture every preview scenario as a PNG with headless Google Chrome (phone and desktop sizes).

    python3 tools/capture.py OUTPUT_DIR [--scenario NAME ...] [--dry-run]

Starts tools/serve.py logic on a free port and runs Chrome once per scenario and size:
    chrome --headless=new --screenshot=OUT.png --window-size=W,H http://localhost:PORT/index.html?scenario=NAME&nosw
`--dry-run` only prints the commands. This tool takes screenshots, so it needs the owner's permission before a real run (AGENTS.md):
the web foundation plan built it but never ran it.
"""
from pathlib import Path
import argparse
import re
import shlex
import shutil
import subprocess
import sys
import tempfile
import threading

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(Path(__file__).resolve().parent))
import serve  # noqa: E402
import test as runner  # noqa: E402  (shares the Chrome lookup)

SIZES = [(390, 844), (1280, 800)]


def scenario_names():
    """The keys of SCENARIOS, read from the source (no browser needed). Each scenario is a quoted key at the start of an entry."""
    names = []
    for line in (ROOT / 'src' / 'ui' / 'scenarios.mjs').read_text().splitlines():
        match = re.match(r"\s+(?:'([a-z0-9-]+)'|([a-z][A-Za-z0-9]*)):\s+async\s*\(", line)
        if match:
            names.append(match.group(1) or match.group(2))
    return names


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('output', type=Path, help='Directory for the PNG files')
    parser.add_argument('--scenario', action='append', help='Only this scenario (repeatable)')
    parser.add_argument('--dry-run', action='store_true', help='Print the Chrome commands and take no screenshots')
    args = parser.parse_args()
    names = args.scenario or scenario_names()
    unknown = sorted(set(names) - set(scenario_names()))
    if unknown:
        parser.error(f'Unknown scenario(s): {", ".join(unknown)}. Known: {", ".join(scenario_names())}')
    chrome = runner.chrome_path()
    server = None
    port = 8080
    if not args.dry_run:
        args.output.mkdir(parents=True, exist_ok=True)
        server, _ = serve.make_server(ROOT, 0, test=False)
        port = server.server_address[1]
        threading.Thread(target=server.serve_forever, daemon=True).start()
    profile = tempfile.mkdtemp(prefix='ftpunk-capture-') if not args.dry_run else '/tmp/ftpunk-capture-PROFILE'
    try:
        for name in names:
            for width, height in SIZES:
                out = args.output / f'{name}-{width}x{height}.png'
                command = [chrome, '--headless=new', f'--user-data-dir={profile}', '--no-first-run', '--disable-gpu', '--hide-scrollbars',
                           '--virtual-time-budget=4000', f'--screenshot={out}', f'--window-size={width},{height}', f'http://localhost:{port}/index.html?scenario={name}&nosw']
                if args.dry_run:
                    print(' '.join(shlex.quote(part) for part in command))
                else:
                    subprocess.run(command, check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=60)
                    print(out)
    finally:
        if server:
            server.shutdown()
            server.server_close()
        if not args.dry_run:
            shutil.rmtree(profile, ignore_errors=True)


if __name__ == '__main__':
    main()
