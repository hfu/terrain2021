#!/usr/bin/env bash
set -euo pipefail

# fix_parts_fgb.sh
# Repair selected parts/*.fgb and write repaired copies as parts/{base}f.fgb
# Usage: bin/fix_parts_fgb.sh [--sample N] [--segmentize METERS] [--snap METERS] parts/16.fgb parts/24.fgb ...
# Options:
#   --sample N          When provided, only process first N features (for quick tests)
#   --segmentize METERS Add ST_Segmentize(...)
#   --snap METERS       Add ST_SnapToGrid(...)
#   --simplify METERS   Add ST_SimplifyPreserveTopology(...)
#   --buffer-clean METERS  Apply ST_Buffer(+METERS) then ST_Buffer(-METERS) to remove small self-intersections/twists
#   --dry-run           Don't write output; just report counts before/after

SAMPLE=""
SEGMENTIZE=""
SNAP=""
SIMPLIFY=""
BUFFER_CLEAN=""
USE_UNARY_UNION=0
DRY=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --sample)
      SAMPLE="$2"; shift 2;;
    --segmentize)
      SEGMENTIZE="$2"; shift 2;;
    --snap)
      SNAP="$2"; shift 2;;
    --simplify)
      SIMPLIFY="$2"; shift 2;;
      --buffer-clean)
        BUFFER_CLEAN="$2"; shift 2;;
      --use-unary-union)
        USE_UNARY_UNION=1; shift;;
    --dry-run)
      DRY=1; shift;;
    --help|-h)
      sed -n '1,200p' "$0"; exit 0;;
    *)
      break;;
  esac
done

if [ $# -eq 0 ]; then
  echo "Specify one or more parts/*.fgb files to process" >&2
  exit 2
fi

command -v ogr2ogr >/dev/null 2>&1 || { echo "ogr2ogr required" >&2; exit 1; }

for f in "$@"; do
  [ -f "$f" ] || { echo "Not found: $f" >&2; continue; }
  base=$(basename "$f" .fgb)
  out="parts/${base}f.fgb"

  echo "Processing $f -> $out"

  # Determine layer name
  LAYER=$(ogrinfo -so -al "$f" 2>/dev/null | awk -F": " '/^Layer name:/{print $2; exit}')
  if [ -z "$LAYER" ]; then
    echo "  Could not detect layer name for $f" >&2
    continue
  fi

  # Build SQL geometry pipeline
  GEOM="Geometry"
  # ST_MakeValid fallback
  GEOM="COALESCE(ST_MakeValid(${GEOM}), ST_Buffer(${GEOM},0))"
  # Optional buffer-clean to remove small self-intersections / twisted rings
  if [ -n "$BUFFER_CLEAN" ]; then
    # apply positive buffer then negative buffer (works well for removing slivers/self-intersections)
    GEOM="ST_Buffer(ST_Buffer(${GEOM}, ${BUFFER_CLEAN}), -${BUFFER_CLEAN})"
  fi
  GEOM="ST_Multi(ST_CollectionExtract(${GEOM},3))"
  if [ -n "$SEGMENTIZE" ]; then
    GEOM="ST_Segmentize(${GEOM}, ${SEGMENTIZE})"
  fi
  if [ -n "$SNAP" ]; then
    GEOM="ST_SnapToGrid(${GEOM}, ${SNAP})"
  fi
  if [ -n "$SIMPLIFY" ]; then
    GEOM="ST_SimplifyPreserveTopology(${GEOM}, ${SIMPLIFY})"
  fi

  SQL="SELECT *, ${GEOM} AS geometry_fix FROM ${LAYER}"
  if [ -n "$SAMPLE" ]; then
    SQL="${SQL} LIMIT ${SAMPLE}"
  fi

  # Count invalid before
  before=$(ogrinfo -ro -dialect SQLite -sql "SELECT COUNT(*) FROM ${LAYER} WHERE ST_IsValid(Geometry)=0" "$f" 2>/dev/null | awk '/COUNT/{print $3; exit}' || echo 0)
  total=$(ogrinfo -ro -so "$f" "$LAYER" 2>/dev/null | awk '/Feature Count:/{print $3; exit}' || echo 0)
  echo "  total=$total before_invalid=$before"

  if [ "$DRY" -eq 1 ]; then
    echo "  dry-run: skipping write"; continue
  fi

  # Write out repaired FGB using ogr2ogr: map geometry_fix to geometry
  # We use -dialect SQLite and -sql with a CREATE statement style via ogr2ogr's -sql selection
  TMPSQL="SELECT *, ${GEOM} AS geometry FROM ${LAYER}"
  ogr2ogr -f FlatGeobuf "$out" "$f" -dialect SQLite -sql "$TMPSQL" -nln "$LAYER" 1>/dev/null || { echo "  ogr2ogr write failed for $f" >&2; continue; }

  if [ "$USE_UNARY_UNION" -eq 1 ]; then
    # Optionally run a unary union pass to merge touching polygons (may dissolve attributes)
    echo "  running ST_UnaryUnion pass on $out"
    TMP2="${out%.fgb}.unary.fgb"
    SQLU="SELECT ST_UnaryUnion(Geometry) AS geometry, * FROM ${LAYER}"
    ogr2ogr -f FlatGeobuf "$TMP2" "$out" -dialect SQLite -sql "$SQLU" -nln "$LAYER" 1>/dev/null || { echo "  unary union failed for $out" >&2; }
    mv "$TMP2" "$out"
  fi

  # Count invalid after
  after=$(ogrinfo -ro -dialect SQLite -sql "SELECT COUNT(*) FROM ${LAYER} WHERE ST_IsValid(Geometry)=0" "$out" 2>/dev/null | awk '/COUNT/{print $3; exit}' || echo 0)
  echo "  wrote $out after_invalid=$after"
done

exit 0
