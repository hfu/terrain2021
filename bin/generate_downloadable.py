#!/usr/bin/env python3
"""
Generate DOWNLOADABLE.md listing files in parts/*.fgb and data/*.fgb.

- Try HEAD against https://transient.optgeo.org to get size/last-modified
  (fallback to local stat if unreachable)
- Extract CRS via osgeo.ogr if available, otherwise parse `ogrinfo -so` output
- If data/*.fgb CRS is unknown, infer from the most common parts/*.fgb CRS
"""

import os
import subprocess
import urllib.request
from collections import Counter
from datetime import datetime

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..'))
OUT = os.path.join(ROOT, 'DOWNLOADABLE.md')
HOST = 'https://transient.optgeo.org'


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


def probe_head(url, timeout=8):
    req = urllib.request.Request(url, method='HEAD', headers={'User-Agent': 'terrain2021-generator/1.0'})
    try:
        with urllib.request.urlopen(req, timeout=timeout) as r:
            headers = {k.lower(): v for k, v in r.getheaders()}
            return headers.get('content-length'), headers.get('last-modified')
    except Exception:
        return None, None


def stat_local(path):
    try:
        st = os.stat(path)
        return str(st.st_size), datetime.utcfromtimestamp(st.st_mtime).strftime('%a, %d %b %Y %H:%M:%S GMT')
    except Exception:
        return None, None


def extract_crs_with_ogrinfo(path):
    try:
        thr = 50 * 1024 * 1024
        use_full = os.path.getsize(path) <= thr
    except Exception:
        use_full = False
    cmd = ['ogrinfo', '-al', '-so', path] if use_full else ['ogrinfo', '-so', path]
    try:
        p = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, timeout=20)
        out = p.stdout or ''
    except Exception:
        return 'ogrinfo-unavailable'
    import re
    m = re.search(r'AUTHORITY\s*\[\s*["\']?EPSG["\']?\s*,\s*["\'](\d{3,6})["\']\s*\]', out, re.IGNORECASE)
    if not m:
        m = re.search(r'ID\s*\[\s*["\']?EPSG["\']?\s*,\s*["\']?(\d{3,6})["\']?\s*\]', out, re.IGNORECASE)
    if not m:
        m = re.search(r'\bEPSG\s*[:=\s]\s*["\']?(\d{3,6})["\']?', out, re.IGNORECASE)
    if m:
        return f'EPSG:{m.group(1)}'
    for line in out.splitlines():
        if any(k in line for k in ('PROJCRS', 'PROJCS', 'GEOGCS', 'Coordinate System is', 'WGS 84', 'Lambert')):
            return line.strip()
    return None


def format_size(sz):
    try:
        n = int(sz)
    except Exception:
        return sz or 'unknown'
    for unit in ('B', 'KiB', 'MiB', 'GiB', 'TiB'):
        if n < 1024:
            return f"{n}{unit}"
        n //= 1024
    return f"{n}PiB"


def main():
    files = collect_files()
    meta = {}
    for group, fn in files:
        rel = f'/{group}/{fn}'
        url = HOST + rel
        size, lm = probe_head(url)
        if size is None:
            lsize, llm = stat_local(os.path.join(ROOT, group, fn))
            size = lsize or 'unknown'
            lm = llm or 'unknown'
        hsize = format_size(size) if size and size.isdigit() else (size or 'unknown')
        local_path = os.path.join(ROOT, group, fn)
        crs = 'unknown'
        try:
            from osgeo import ogr
            ds = ogr.Open(local_path)
            if ds is not None:
                lyr = ds.GetLayer(0)
                if lyr is not None:
                    sref = lyr.GetSpatialRef()
                    if sref is not None:
                        code = None
                        try:
                            code = sref.GetAuthorityCode(None)
                            auth = sref.GetAuthorityName(None)
                        except Exception:
                            code = None
                            auth = None
                        if code:
                            crs = f'{auth}:{code}' if auth else f'EPSG:{code}'
        except Exception:
            pass
        if crs == 'unknown':
            c2 = extract_crs_with_ogrinfo(local_path)
            if c2:
                crs = c2
        meta[(group, fn)] = {'url': url, 'hsize': hsize, 'lm': lm or 'unknown', 'crs': crs}

    parts_crs = [v['crs'] for k, v in meta.items() if k[0] == 'parts' and v['crs'] not in ('unknown', 'ogrinfo-unavailable')]
    parts_mode = Counter(parts_crs).most_common(1)[0][0] if parts_crs else None

    lines = ['# Downloadable files', '', 'Below is a generated list of FlatGeobuf files (paths point to transient.optgeo.org).', '']
    cur = None
    for group, fn in files:
        if group != cur:
            lines.append(f'## {group}')
            lines.append('')
            cur = group
        info = meta[(group, fn)]
        crs = info['crs']
        if group == 'data' and crs == 'unknown' and parts_mode:
            crs = f'inferred:{parts_mode}'
        lines.append(f'- [{group}/{fn}]({info["url"]}) — {info["hsize"]}, last-modified: {info["lm"]}, CRS: {crs}')
        lines.append('')
    lines.append('Note: availability depends on the tunnel/server and Cloudflare; use `curl -I` / `curl -X OPTIONS` for quick checks.')
    content = '\n'.join(lines) + '\n'
    with open(OUT, 'w', encoding='utf-8') as f:
        f.write(content)
    print(f'Wrote {OUT}')


if __name__ == '__main__':
    main()
