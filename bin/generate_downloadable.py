#!/usr/bin/env python3
"""Generate DOWNLOADABLE.md by probing transient.optgeo.org for each local .fgb.

Behavior:
- enumerate parts/*.fgb and data/*.fgb
- for each file, perform HTTP HEAD to https://transient.optgeo.org/<path>
- collect Content-Length and Last-Modified when possible
- fallback to local stat for size and mtime if HEAD fails
- write Markdown to DOWNLOADABLE.md

Uses only standard library modules.
"""
import os
import sys
import urllib.request
import urllib.error
import socket
from datetime import datetime

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..'))
OUT = os.path.join(ROOT, 'DOWNLOADABLE.md')
HOST = 'https://transient.optgeo.org'


def probe_head(url, timeout=10):
    req = urllib.request.Request(url, method='HEAD', headers={'User-Agent': 'terrain2021-generator/1.0'})
    try:
        with urllib.request.urlopen(req, timeout=timeout) as r:
            headers = {k.lower(): v for k, v in r.getheaders()}
            size = headers.get('content-length')
            lm = headers.get('last-modified')
            return size, lm
    except (urllib.error.URLError, socket.timeout, ValueError):
        return None, None


def format_size(sz):
    try:
        n = int(sz)
    except Exception:
        return sz or 'unknown'
    for unit in ('B', 'KiB', 'MiB', 'GiB', 'TiB'):
        if n < 1024:
            return f"{n}{unit}"
        n = n // 1024
    return f"{n}PiB"


def stat_local(path):
    try:
        st = os.stat(path)
        return str(st.st_size), datetime.utcfromtimestamp(st.st_mtime).strftime('%a, %d %b %Y %H:%M:%S GMT')
    except Exception:
        return None, None


def collect_files():
    parts_dir = os.path.join(ROOT, 'parts')
    data_dir = os.path.join(ROOT, 'data')
    files = []
    if os.path.isdir(parts_dir):
        def parts_key(s):
            base = os.path.splitext(s)[0]
            return (0, int(base)) if base.isdigit() else (1, base)
        for fn in sorted(os.listdir(parts_dir), key=parts_key):
            if fn.endswith('.fgb'):
                files.append(('parts', fn))
    if os.path.isdir(data_dir):
        for fn in sorted(os.listdir(data_dir)):
            if fn.endswith('.fgb'):
                files.append(('data', fn))
    return files


def main():
    files = collect_files()
    lines = []
    lines.append('# Downloadable files')
    lines.append('')
    lines.append('Below is a generated list of FlatGeobuf files (paths point to transient.optgeo.org).')
    lines.append('')
    current_group = None
    for group, fn in files:
        if group != current_group:
            lines.append(f'## {group}')
            lines.append('')
            current_group = group
        rel = f'/{group}/{fn}' if group == 'parts' else f'/{group}/{fn}'
        url = HOST + rel
        size, lm = probe_head(url)
        if size is None:
            lsize, llm = stat_local(os.path.join(ROOT, group, fn))
            size = lsize or 'unknown'
            lm = llm or 'unknown'
        hsize = format_size(size)
        lm_display = lm
        lines.append(f'- [{group}/{fn}]({url}) — {hsize}, last-modified: {lm_display}')
    lines.append('')
    lines.append('Note: availability depends on the tunnel/server and Cloudflare; use `curl -I` / `curl -X OPTIONS` for quick checks.')
    content = '\n'.join(lines) + '\n'
    with open(OUT, 'w', encoding='utf-8') as f:
        f.write(content)
    print(f'Wrote {OUT}')


if __name__ == '__main__':
    main()
