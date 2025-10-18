#!/usr/bin/env python3
"""
Simple static server that exposes /data and /parts directories at configurable paths.
Usage: python3 bin/serve.py --host 127.0.0.1 --port 8000
"""
import argparse
import http.server
import os
import socketserver
import shutil
from urllib.parse import unquote, urlparse

# Global CORS origin value set in main() via --cors-origin
CORS_ORIGIN = None


class MultiStaticHandler(http.server.SimpleHTTPRequestHandler):
    # Serve files from /data when path starts with /data/
    # Serve files from /parts when path starts with /parts/
    def translate_path(self, path):
        parsed = urlparse(path)
        path = unquote(parsed.path)
        cwd = os.getcwd()
        # Prefer routing by Host header for nicer tunnel mappings. Example:
        #  - data.transient.optgeo.org -> serve files from ./data as root
        #  - parts.transient.optgeo.org -> serve files from ./parts as root
        host = self.headers.get('Host', '')
        # strip optional port
        host = host.split(':')[0]
        if host == 'data.transient.optgeo.org':
            # map root paths to data/
            relpath = path.lstrip('/')
            target = os.path.join(cwd, 'data', relpath)
            return os.path.normpath(target)
        if host == 'parts.transient.optgeo.org':
            relpath = path.lstrip('/')
            target = os.path.join(cwd, 'parts', relpath)
            return os.path.normpath(target)

        # Fallback: explicit /data or /parts prefix routing (manual local use)
        if path.startswith('/data/') or path == '/data':
            relpath = path[len('/data/'):]
            target = os.path.join(cwd, 'data', relpath)
            return os.path.normpath(target)
        if path.startswith('/parts/') or path == '/parts':
            relpath = path[len('/parts/'):]
            target = os.path.join(cwd, 'parts', relpath)
            return os.path.normpath(target)
        # fallback to cwd
        return super().translate_path(path)

    def send_cors_headers(self):
        """Add CORS headers when appropriate.

        If CORS_ORIGIN is set to '*' all origins are allowed.
        If CORS_ORIGIN is a specific origin, only that origin is echoed back when the
        request has a matching Origin header.
        """
        if not CORS_ORIGIN:
            return
        origin = self.headers.get('Origin')
        if CORS_ORIGIN == '*':
            self.send_header('Access-Control-Allow-Origin', '*')
        elif origin and origin == CORS_ORIGIN:
            self.send_header('Access-Control-Allow-Origin', origin)
        else:
            # Origin not allowed — do not send CORS headers
            return
        # Common CORS headers useful for static hosting of vector tiles/files
        self.send_header('Access-Control-Allow-Methods', 'GET, OPTIONS')
        self.send_header('Access-Control-Allow-Headers', 'Range, Accept, Content-Type')
        # Expose Range/Content-Length for partial content consumers
        self.send_header('Access-Control-Expose-Headers', 'Content-Range, Content-Length')

    def end_headers(self):
        # Ensure CORS headers are added before finalizing headers
        try:
            self.send_cors_headers()
        except Exception:
            pass
        super().end_headers()

    def copyfile(self, source, outputfile):
        """Copy data from source to outputfile while suppressing client disconnect errors.

        Wrapping shutil.copyfileobj in a try/except prevents a full traceback
        from being printed to the server log when the client closes the
        connection (BrokenPipeError / ConnectionResetError).
        """
        try:
            shutil.copyfileobj(source, outputfile)
        except (BrokenPipeError, ConnectionResetError):
            # Client disconnected prematurely; ignore and return quietly.
            return

    def do_OPTIONS(self):
        # Respond to preflight requests
        self.send_response(200)
        # send_cors_headers will be invoked via end_headers
        self.end_headers()


def main():
    parser = argparse.ArgumentParser(description='Serve data and parts directories')
    parser.add_argument('--host', default='127.0.0.1')
    parser.add_argument('--port', type=int, default=8000)
    parser.add_argument('--dir', default='.')
    parser.add_argument('--cors-origin', default=None,
                        help='If set, add Access-Control-Allow-Origin headers. Example: "https://transient.optgeo.org"')
    args = parser.parse_args()

    os.chdir(args.dir)

    # set CORS origin for handler
    _set_cors_origin(args.cors_origin)

    handler = MultiStaticHandler
    with socketserver.TCPServer((args.host, args.port), handler) as httpd:
        print(f"Serving /data and /parts from {os.path.abspath(args.dir)} at http://{args.host}:{args.port}")
        try:
            httpd.serve_forever()
        except KeyboardInterrupt:
            print('\nShutting down')


def _set_cors_origin(value):
    global CORS_ORIGIN
    if value:
        CORS_ORIGIN = value


if __name__ == '__main__':
    main()
