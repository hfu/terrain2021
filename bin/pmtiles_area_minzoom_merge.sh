#!/usr/bin/env bash
set -euo pipefail

# Merge parts/*.fgb into one PMTiles with area-based per-feature minzoom.
# - Per part: compute terrain22 in SQL, compute area_m2 (in source CRS), select minimal props
# - Reproject to EPSG:4326 for tippecanoe, assign tippecanoe.minzoom via jq buckets, drop area_m2
# - Single tippecanoe run writes OUTPUT (default data/terrain22.pmtiles)
#
# Env:
#   OUTPUT_PMTILES (default: data/terrain22.pmtiles)
#   TIPPECANOE (default: tippecanoe)
#   TIP_MIN_Z (default: 1), TIP_MAX_Z (default: 8), TIP_LAYER (default: terrain22)
#   TIPPE_OPTS (falls back to safe coverage-friendly defaults if empty)
#   PRE_SIMPLIFY_METERS, SNAP_GRID_METERS, SEGMENTIZE_METERS (optional pre-clean)
#   MZ1_MIN..MZ5_MIN bucket thresholds (m^2)

OUTPUT_PMTILES=${OUTPUT_PMTILES:-data/terrain22.pmtiles}
TIPPECANOE=${TIPPECANOE:-tippecanoe}
TIP_MIN_Z=${TIP_MIN_Z:-1}
TIP_MAX_Z=${TIP_MAX_Z:-8}
TIP_LAYER=${TIP_LAYER:-terrain22}

# Default tippecanoe options tuned for low-zoom coverage
if [[ -z "${TIPPE_OPTS:-}" ]]; then
  TIPPE_OPTS="--force --no-feature-limit --extend-zooms-if-still-dropping --coalesce --coalesce-densest-as-needed --coalesce-smallest-as-needed --drop-densest-as-needed --drop-smallest-as-needed --drop-rate=0.2 --maximum-tile-bytes=24000000"
fi
if [[ "${TIPPE_OPTS}" != *"--force"* ]]; then
  TIPPE_OPTS+=" --force"
fi

PRE_SIMPLIFY_METERS=${PRE_SIMPLIFY_METERS:-}
SNAP_GRID_METERS=${SNAP_GRID_METERS:-}
SEGMENTIZE_METERS=${SEGMENTIZE_METERS:-}

MZ1_MIN=${MZ1_MIN:-20000000}
MZ2_MIN=${MZ2_MIN:-5000000}
MZ3_MIN=${MZ3_MIN:-1000000}
MZ4_MIN=${MZ4_MIN:-200000}
MZ5_MIN=${MZ5_MIN:-50000}

mkdir -p "$(dirname "${OUTPUT_PMTILES}")"

command -v ogr2ogr >/dev/null 2>&1 || { echo "ogr2ogr not found" >&2; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "jq not found" >&2; exit 1; }
command -v "${TIPPECANOE}" >/dev/null 2>&1 || { echo "tippecanoe not found: ${TIPPECANOE}" >&2; exit 1; }

shopt -s nullglob
PARTS=(parts/*.fgb)
if [ ${#PARTS[@]} -eq 0 ]; then
  echo "No parts/*.fgb found" >&2
  exit 0
fi

# Build robust refs and terrain22 mapping
SINKS_REF='COALESCE("poly.Sinks", "Sinks")'
GC15_REF='COALESCE("gcluster.GCLUSTER15", "GCLUSTER15")'
GC40_REF='COALESCE("gcluster.GCLUSTER40", "GCLUSTER40")'
SINKS_INT="CAST(${SINKS_REF} AS INTEGER)"
GC15_INT="CAST(${GC15_REF} AS INTEGER)"
GC40_INT="CAST(${GC40_REF} AS INTEGER)"
read -r -d '' TERRAIN22_CASE <<'SQL' || true
CASE
  WHEN %GC15%=2 THEN 1
  WHEN %GC15%=3 THEN 2
  WHEN %GC15%=13 THEN 3
  WHEN %GC15%=12 THEN 4
  WHEN %GC15%=5 THEN 5
  WHEN %GC15%=4 THEN 6
  WHEN %GC15%=14 THEN 7
  WHEN %GC15%=10 THEN 8
  WHEN %GC15%=11 AND %SINKS%=0 THEN 9
  WHEN %GC15%=11 AND %SINKS%<>0 THEN 10
  WHEN %GC15%=7 AND %SINKS%=0 THEN 11
  WHEN %GC15%=7 AND %SINKS%<>0 THEN 12
  WHEN %GC15%=8 AND %SINKS%=0 THEN 13
  WHEN %GC15%=8 AND %SINKS%<>0 THEN 14
  WHEN %GC15%=9 AND %SINKS%=0 THEN 15
  WHEN %GC15%=9 AND %SINKS%<>0 THEN 16
  WHEN %GC15%=6 AND %SINKS%=0 THEN 17
  WHEN %GC15%=6 AND %SINKS%<>0 THEN 18
  WHEN %GC15%=1 AND %SINKS%=0 THEN 19
  WHEN %GC15%=1 AND %SINKS%<>0 THEN 20
  WHEN %GC15%=15 AND %SINKS%=0 THEN 21
  WHEN %GC15%=15 AND %SINKS%<>0 THEN 22
  ELSE NULL END
SQL
TERRAIN22_SQL=${TERRAIN22_CASE//%GC15%/${GC15_INT}}
TERRAIN22_SQL=${TERRAIN22_SQL//%SINKS%/${SINKS_INT}}
TERRAIN22_INT="CAST((${TERRAIN22_SQL}) AS INTEGER)"

# Geometry pipeline (source CRS), optional helpers
GEOM_COL=Geometry
GEOM_COL="ST_Multi(ST_CollectionExtract(${GEOM_COL}, 3))"
if [ -n "${SEGMENTIZE_METERS}" ]; then
  GEOM_COL="ST_Segmentize(${GEOM_COL}, ${SEGMENTIZE_METERS})"
fi
if [ -n "${SNAP_GRID_METERS}" ]; then
  GEOM_COL="ST_SnapToGrid(${GEOM_COL}, ${SNAP_GRID_METERS})"
fi
if [ -n "${PRE_SIMPLIFY_METERS}" ]; then
  GEOM_COL="ST_SimplifyPreserveTopology(${GEOM_COL}, ${PRE_SIMPLIFY_METERS})"
fi

(
  for f in "${PARTS[@]}"; do
    LAYER=$(ogrinfo -so -al "$f" 2>/dev/null | awk -F": " '/^Layer name:/{print $2; exit}')
    if [ -z "$LAYER" ]; then
      echo "Skip (no layer): $f" >&2
      continue
    fi
    SQL_SELECT="SELECT ${GEOM_COL} AS geometry, ST_Area(Geometry) AS area_m2, ${SINKS_INT} AS Sinks, ${GC40_INT} AS GCLUSTER40, ${GC15_INT} AS GCLUSTER15, ${TERRAIN22_INT} AS terrain22 FROM ${LAYER} WHERE (${TERRAIN22_INT}) IS NOT NULL"
    echo "Streaming $f (layer=$LAYER)" >&2
    ogr2ogr -f GeoJSONSeq /vsistdout/ "$f" -dialect SQLITE -sql "$SQL_SELECT" -t_srs EPSG:4326 -wrapdateline || { echo "ogr2ogr failed for $f" >&2; exit 1; }
  done
) | jq -c --argjson mz1 "${MZ1_MIN}" --argjson mz2 "${MZ2_MIN}" --argjson mz3 "${MZ3_MIN}" --argjson mz4 "${MZ4_MIN}" --argjson mz5 "${MZ5_MIN}" \
  'select(.geometry != null) | . as $f | (($f.properties.area_m2 // 0) >= $mz1 and 1 or ($f.properties.area_m2 // 0) >= $mz2 and 2 or ($f.properties.area_m2 // 0) >= $mz3 and 3 or ($f.properties.area_m2 // 0) >= $mz4 and 4 or ($f.properties.area_m2 // 0) >= $mz5 and 5 or 6) as $mz | .tippecanoe = ({minzoom: $mz}) | (.properties |= (del(.area_m2)))' \
  | ${TIPPECANOE} -o "${OUTPUT_PMTILES}" -Z${TIP_MIN_Z} -z${TIP_MAX_Z} -l ${TIP_LAYER} ${TIPPE_OPTS}

echo "Wrote ${OUTPUT_PMTILES}"
