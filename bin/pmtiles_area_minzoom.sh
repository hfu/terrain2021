#!/usr/bin/env bash
set -euo pipefail

# Build PMTiles by assigning per-feature minzoom from area buckets.
# - Computes area_m2 in source CRS, assigns tippecanoe.minzoom via jq, then removes area_m2.
# - Reprojects geometry to EPSG:4326 for tippecanoe input. Optional pre-simplify/snap.
#
# Env vars:
#   INPUT_FGB           (default: parts/41.fgb)
#   OUTPUT_PMTILES      (default: data/terrain22_41.pmtiles)
#   TIPPECANOE          (default: tippecanoe)
#   TIP_LAYER           (default: terrain22)
#   TIP_MIN_Z           (default: 1)
#   TIP_MAX_Z           (default: 8)
#   TIPPE_OPTS          (default includes --force and coverage-friendly opts)
#   PRE_SIMPLIFY_METERS (optional: ST_SimplifyPreserveTopology before reprojection)
#   SNAP_GRID_METERS    (optional: ST_SnapToGrid before simplify)
#   SEGMENTIZE_METERS   (optional: ST_Segmentize before snap)
#   # Minzoom area buckets (m^2). Feature gets first bucket it meets (descending):
#   MZ1_MIN (default 5000000), MZ2_MIN (1000000), MZ3_MIN (200000), MZ4_MIN (50000), MZ5_MIN (10000)

INPUT_FGB=${INPUT_FGB:-parts/41.fgb}
OUTPUT_PMTILES=${OUTPUT_PMTILES:-data/terrain22_41.pmtiles}
TIPPECANOE=${TIPPECANOE:-tippecanoe}
TIP_LAYER=${TIP_LAYER:-terrain22}
TIP_MIN_Z=${TIP_MIN_Z:-1}
TIP_MAX_Z=${TIP_MAX_Z:-8}

# Ensure tippecanoe gets --force and large byte budget defaults unless overridden
if echo "${TIPPE_OPTS:-}" | grep -q -- --force; then
  TIPPE_OPTS="${TIPPE_OPTS:-}"
else
  TIPPE_OPTS="${TIPPE_OPTS:-} --force"
fi
if ! echo "${TIPPE_OPTS}" | grep -q -- "--maximum-tile-bytes"; then
  TIPPE_OPTS="${TIPPE_OPTS} --maximum-tile-bytes=24000000"
fi
if ! echo "${TIPPE_OPTS}" | grep -q -- "--no-feature-limit"; then
  TIPPE_OPTS="${TIPPE_OPTS} --no-feature-limit"
fi
if ! echo "${TIPPE_OPTS}" | grep -q -- "--extend-zooms-if-still-dropping"; then
  TIPPE_OPTS="${TIPPE_OPTS} --extend-zooms-if-still-dropping"
fi
if ! echo "${TIPPE_OPTS}" | grep -q -- "--coalesce"; then
  TIPPE_OPTS="${TIPPE_OPTS} --coalesce --coalesce-densest-as-needed --coalesce-smallest-as-needed"
fi
if ! echo "${TIPPE_OPTS}" | grep -q -- "--drop-densest-as-needed"; then
  TIPPE_OPTS="${TIPPE_OPTS} --drop-densest-as-needed --drop-smallest-as-needed --drop-rate=0.2"
fi

PRE_SIMPLIFY_METERS=${PRE_SIMPLIFY_METERS:-}
SNAP_GRID_METERS=${SNAP_GRID_METERS:-}
SEGMENTIZE_METERS=${SEGMENTIZE_METERS:-}

MZ1_MIN=${MZ1_MIN:-5000000}
MZ2_MIN=${MZ2_MIN:-1000000}
MZ3_MIN=${MZ3_MIN:-200000}
MZ4_MIN=${MZ4_MIN:-50000}
MZ5_MIN=${MZ5_MIN:-10000}

mkdir -p "$(dirname "${OUTPUT_PMTILES}")"

# Detect input layer name
layer=$(ogrinfo -ro -al "${INPUT_FGB}" 2>/dev/null | grep -m1 '^OGRFeature(' | sed -E 's/^OGRFeature\(([^)]+)\).*/\1/') || true
if [ -z "${layer}" ]; then
  layer=$(ogrinfo -ro "${INPUT_FGB}" 2>/dev/null | awk -F: '/^[0-9]+: /{print $2; exit}' | sed 's/^ *//;s/ *$//') || true
fi
layer_short=$(echo "${layer}" | awk '{print $1}')
if [ -z "${layer_short}" ]; then
  echo "[error] could not detect layer name for ${INPUT_FGB}" >&2
  exit 1
fi

# Build geometry expression (pre-reprojection cleanup + optional simplify), then to EPSG:4326
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
# SQL: select source-CRS geometry and computed area_m2; reprojection is handled by -t_srs at the ogr2ogr command level
SQL="SELECT ${GEOM_COL} AS geometry, ST_Area(Geometry) AS area_m2, * FROM \"${layer_short}\" WHERE Geometry IS NOT NULL"

# Stream: ogr2ogr -> jq (assign tippecanoe.minzoom & drop area_m2) -> tippecanoe
set -o pipefail
ogr2ogr -f GeoJSONSeq /vsistdout/ "${INPUT_FGB}" -dialect SQLITE -sql "${SQL}" -nln ${layer_short} -t_srs EPSG:4326 \
  | jq -c --argjson mz1 "${MZ1_MIN}" --argjson mz2 "${MZ2_MIN}" --argjson mz3 "${MZ3_MIN}" --argjson mz4 "${MZ4_MIN}" --argjson mz5 "${MZ5_MIN}" 'select(.geometry != null) | . as $f | (($f.properties.area_m2 // 0) >= $mz1 and 1 or ($f.properties.area_m2 // 0) >= $mz2 and 2 or ($f.properties.area_m2 // 0) >= $mz3 and 3 or ($f.properties.area_m2 // 0) >= $mz4 and 4 or ($f.properties.area_m2 // 0) >= $mz5 and 5 or 6) as $mz | .tippecanoe = ({minzoom: $mz}) | (.properties |= (del(.area_m2)))' \
  | ${TIPPECANOE} -o "${OUTPUT_PMTILES}" -Z${TIP_MIN_Z} -z${TIP_MAX_Z} -l ${TIP_LAYER} ${TIPPE_OPTS}

echo "Wrote ${OUTPUT_PMTILES}"
