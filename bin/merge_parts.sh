#!/usr/bin/env bash
set -euo pipefail

# Merge parts into data/terrain2021.fgb using GeoJSONSeq streaming
# Reproject each part to EPSG:4326 and stream into ogr2ogr which reads from stdin.

mkdir -p data

shopt -s nullglob
parts=(parts/*.fgb)
if [ ${#parts[@]} -eq 0 ]; then
  echo "no parts found" >&2
  exit 1
fi

# Use /vsistdout/ and /vsistdin to stream
(
  for p in "${parts[@]}"; do
    echo "streaming $p" >&2
    ogr2ogr -f GeoJSONSeq /vsistdout/ -t_srs EPSG:4326 "$p" || { echo "ogr2ogr failed for $p" >&2; exit 2; }
  done
) | ogr2ogr -f FlatGeobuf data/terrain2021.fgb '/vsistdin?buffer_limit=-1' -wrapdateline -nln poly -skipfailures

echo "merged ${#parts[@]} parts -> data/terrain2021.fgb" >&2
