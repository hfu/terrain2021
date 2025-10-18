#!/usr/bin/env bash
set -euo pipefail

# Check geometry validity of parts/*.fgb and report invalid counts & reasons.
# Also optionally dump sample invalid features to GeoJSON for inspection.
#
# Usage:
#   bin/check_geometry_errors.sh [--sample N] [--outdir DIR] [--limit PART_GLOB]
#
# Options:
#   --sample N       Dump up to N invalid features per part as GeoJSON (default: 0 -> no dump)
#   --outdir DIR     Output directory for samples (default: tmp/invalid_samples)
#   --limit GLOB     Limit scan to matching parts (e.g., 'parts/2*.fgb')
#
# Requirements:
#   - GDAL/OGR with SQLite dialect (ogrinfo/ogr2ogr)
#   - bash, coreutils

SAMPLE=0
OUTDIR="tmp/invalid_samples"
LIMIT="parts/*.fgb"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --sample)
      SAMPLE=${2:-0}
      shift 2
      ;;
    --outdir)
      OUTDIR=${2:-"tmp/invalid_samples"}
      shift 2
      ;;
    --limit)
      LIMIT=${2:-"parts/*.fgb"}
      shift 2
      ;;
    -h|--help)
      sed -n '1,60p' "$0"
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      exit 2
      ;;
  esac
done

mkdir -p "$OUTDIR"

printf "Scanning geometry validity: %s\n" "$LIMIT"

total_parts=0
invalid_parts=0
declare -a invalid_list

for f in $LIMIT; do
  [[ -f "$f" ]] || continue
  total_parts=$((total_parts+1))
  base=$(basename "$f" .fgb)

  # Count features, invalids, geometry types, and collect invalid reasons
  # Using SQLite dialect with ST_IsValid and ST_IsValidReason
  # Note: FlatGeobuf typically has single layer named from filename; using layer=poly as used in pipeline.
  layer="poly"

  # Get total feature count quickly
  total=$(ogrinfo -ro -so "$f" "$layer" 2>/dev/null | awk '/Feature Count:/{print $3; exit}' || echo 0)

  # Count invalid features
  invalid_cnt=$(ogrinfo -ro -dialect SQLite -sql "SELECT COUNT(*) FROM $layer WHERE ST_IsValid(Geometry)=0" "$f" 2>/dev/null | awk '/COUNT/{print $3; exit}' || echo 0)

  # Geometry type distribution
  gtypes=$(ogrinfo -ro -dialect SQLite -sql "SELECT GeometryType(Geometry) AS gtype, COUNT(*) AS n FROM $layer GROUP BY gtype ORDER BY n DESC" "$f" 2>/dev/null | awk 'BEGIN{printf("")}{if($1=="gtype")next; if($1!~/^\(/) {printf("%s:%s ",$1,$2)}}END{print ""}')

  printf "%-12s total=%-4s invalid=%-3s types=[%s]\n" "$base" "$total" "$invalid_cnt" "$gtypes"

  if [[ "$invalid_cnt" != "0" ]]; then
    invalid_parts=$((invalid_parts+1))
    invalid_list+=("$base")

    # Show top invalid reasons (grouped)
    echo "  Reasons:"
    ogrinfo -ro -dialect SQLite -sql "SELECT ST_IsValidReason(Geometry) AS reason, COUNT(*) AS n FROM $layer WHERE ST_IsValid(Geometry)=0 GROUP BY reason ORDER BY n DESC" "$f" 2>/dev/null | \
      awk '/^\|/ {next} /reason/ {next} /COUNT/ {next} {if(NF>=2){print "   -", $0}}'

    if [[ "$SAMPLE" -gt 0 ]]; then
      # Dump up to SAMPLE invalid features as GeoJSON
      out="$OUTDIR/${base}_invalid_sample.geojson"
      ogr2ogr -f GeoJSON "$out" "$f" -nln "$base" -dialect SQLite -sql "SELECT * FROM $layer WHERE ST_IsValid(Geometry)=0 LIMIT $SAMPLE" 1>/dev/null
      echo "  Sample -> $out"
    fi
  fi
done

echo "" 
echo "Scanned parts: $total_parts"
echo "Parts with invalid geometry: $invalid_parts"
if (( invalid_parts > 0 )); then
  printf "List: %s\n" "${invalid_list[*]}"
fi

exit 0
