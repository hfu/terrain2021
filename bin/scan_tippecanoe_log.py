#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Scan a tippecanoe log (joblog_pmtiles.txt) for warnings about tiles exceeding
--maximum-tile-features and write a compact list of offending tiles to
data/pmtiles_over_threshold_tiles.txt.

This looks for lines like:
  "tile 2/2/1 has 1535647 features, >1400000"
and will output CSV lines:
  z,x,y,features,limit,original_line

Usage: bin/scan_tippecanoe_log.py joblog_pmtiles.txt

If the log file cannot be read, the script exits with code 1.
"""

import re
import sys
from pathlib import Path

RE = re.compile(r"tile\s+(\d+)/(\d+)/(\d+)\s+has\s+(\d+)\s+features,\s*>\s*(\d+)", re.IGNORECASE)

def scan(log_path: Path, out_path: Path):
    found = []
    try:
        text = log_path.read_text(encoding='utf-8', errors='replace')
    except Exception as e:
        print(f"ERROR: cannot read log file {log_path}: {e}", file=sys.stderr)
        return 1

    for line in text.splitlines():
        m = RE.search(line)
        if m:
            z, x, y, features, limit = m.groups()
            found.append((int(z), int(x), int(y), int(features), int(limit), line.strip()))

    out_path.parent.mkdir(parents=True, exist_ok=True)

    if not found:
        # overwrite with an empty file to indicate no offending tiles
        out_path.write_text("# no tiles over threshold\n", encoding='utf-8')
        print("No tiles over threshold found.")
        return 0

    # Sort by zoom,x,y
    found.sort()

    lines = ["z,x,y,features,limit,log_line"]
    for z,x,y,features,limit,line in found:
        # escape any commas in the original line
        safe = line.replace(',', '\\,')
        lines.append(f"{z},{x},{y},{features},{limit},{safe}")

    out_path.write_text("\n".join(lines)+"\n", encoding='utf-8')
    print(f"Wrote {len(found)} offending tiles to {out_path}")
    return 0


def main(argv):
    if len(argv) != 2:
        print("Usage: scan_tippecanoe_log.py <logfile>")
        return 2
    log_path = Path(argv[1])
    out_path = Path('data/pmtiles_over_threshold_tiles.txt')
    return scan(log_path, out_path)

if __name__ == '__main__':
    sys.exit(main(sys.argv))
