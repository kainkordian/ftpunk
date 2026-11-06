#!/usr/bin/env python3
"""Serve only this web project. Localhost is a secure context for Web Bluetooth.

`--test` additionally accepts POST /__test-result (the in-browser test page reports its result there)
and lists the source modules and test files at GET /__modules. Without it both endpoints answer 404/405.
"""
from functools import partial
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
import argparse
import json

ROOT = Path(__file__).resolve().parents[1]


class Handler(SimpleHTTPRequestHandler):
    # HTTP/1.1 keep-alive: the test page loads ~60 modules per frame in ~70 frames; one connection per file made a rare request go missing.
    protocol_version = 'HTTP/1.1'
    extensions_map = {**SimpleHTTPRequestHandler.extensions_map, '.mjs': 'text/javascript', '.webmanifest': 'application/manifest+json'}
    test_results = None  # set to a list by make_server(test=True)
    web_root = ROOT

    def end_headers(self):
        self.send_header('Cache-Control', 'no-cache')
        self.send_header('X-Content-Type-Options', 'nosniff')
        self.send_header('Referrer-Policy', 'no-referrer')
        super().end_headers()

    def log_message(self, format, *args):
        if self.test_results is None:
            super().log_message(format, *args)

    def do_GET(self):
        if self.path == '/__modules' and self.test_results is not None:
            modules = sorted(str(p.relative_to(self.web_root)) for p in (self.web_root / 'src').rglob('*.mjs'))
            tests = sorted(str(p.relative_to(self.web_root)) for p in (self.web_root / 'tests').glob('*.test.mjs'))
            body = json.dumps({'modules': modules, 'tests': tests}).encode()
            self.send_response(200)
            self.send_header('Content-Type', 'application/json')
            self.send_header('Content-Length', str(len(body)))
            self.end_headers()
            self.wfile.write(body)
            return
        super().do_GET()

    def do_POST(self):
        if self.path != '/__test-result' or self.test_results is None:
            self.send_error(405 if self.test_results is None else 404)
            return
        length = int(self.headers.get('Content-Length', 0))
        if length > 1_000_000:
            self.send_error(413)
            return
        try:
            self.test_results.append(json.loads(self.rfile.read(length)))
        except ValueError:
            self.send_error(400)
            return
        self.send_response(204)
        self.end_headers()


class Server(ThreadingHTTPServer):
    # Chrome opens many connections at once while it loads an ES module graph; the default backlog of 5 drops some of them.
    request_queue_size = 128
    daemon_threads = True


def make_server(root=ROOT, port=8080, test=False):
    """Return (server, results). `results` is a list that receives posted test results, or None."""
    results = [] if test else None
    handler = type('BoundHandler', (Handler,), {'test_results': results, 'web_root': Path(root)})
    return Server(('127.0.0.1', port), partial(handler, directory=str(root))), results


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--port', type=int, default=8080)
    parser.add_argument('--dist', action='store_true', help='Serve the production export')
    parser.add_argument('--test', action='store_true', help='Accept test results at /__test-result')
    args = parser.parse_args()
    root = ROOT / 'dist' if args.dist else ROOT
    if not root.is_dir():
        parser.error('Run python3 tools/build.py before serving dist.')
    server, results = make_server(root, args.port, args.test)
    print(f'FTPunk Web: http://localhost:{args.port} (Ctrl-C to stop)', flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        server.server_close()
