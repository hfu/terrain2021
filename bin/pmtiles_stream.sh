#!/bin/sh
set -eu -o pipefail

# Helper script to produce data/terrain22.pmtiles using streaming simplify pipeline.
# Expects to be run from repository root. Honors environment variables:
# TIPPECANOE, TIPPE_OPTS, TIP_MIN_Z, TIP_MAX_Z, TIP_LAYER,
# TIP_SIMPLIFY_METERS, TIP_SIMPLIFY_PRESERVE, TIP_SIMPLIFY_T_SRS_EPSG,
# TIP_SEGMENTIZE_METERS, TIP_SNAP_GRID_METERS, RUN

TIPPECANOE=${TIPPECANOE:-tippecanoe}
# Ensure tippecanoe always receives --force (even if Makefile didn't pass it)
if echo "${TIPPE_OPTS:-}" | grep -q -- --force; then
  TIPPE_OPTS="${TIPPE_OPTS:-}"
else
  TIPPE_OPTS="${TIPPE_OPTS:-} --force"
fi
TIP_MIN_Z=${TIP_MIN_Z:-6}
TIP_MAX_Z=${TIP_MAX_Z:-8}
TIP_LAYER=${TIP_LAYER:-terrain22}

# Older flow used FORCE flag from RUN; now we include --force in TIPPE_OPTS consistently
FORCE=""

# If no simplify requested, pass FlatGeobuf directly
if [ -z "${TIP_SIMPLIFY_METERS:-}" ] ; then
  echo "No simplify requested — passing FlatGeobuf directly to ${TIPPECANOE}"
  exec ${TIPPECANOE} -o data/terrain22.pmtiles -Z${TIP_MIN_Z} -z${TIP_MAX_Z} -l ${TIP_LAYER} ${TIPPE_OPTS} data/terrain22.fgb
fi

# Build SQL select expression
T_SRS=${TIP_SIMPLIFY_T_SRS_EPSG:-3857}
SIM=${TIP_SIMPLIFY_METERS}
SEG=${TIP_SEGMENTIZE_METERS:-}
SNAP=${TIP_SNAP_GRID_METERS:-}
PRESERVE=${TIP_SIMPLIFY_PRESERVE:-1}

if [ "${PRESERVE}" = "1" ] ; then
  # Start with base: ST_Transform(ST_SimplifyPreserveTopology(ST_Transform(Geometry,T_SRS),SIM),4326)
  if [ -n "${SEG}" ] && [ -n "${SNAP}" ] ; then
    # Segmentize then snap then simplify
    INNER="ST_SnapToGrid(ST_Segmentize(ST_Transform(Geometry,${T_SRS}),${SEG}),${SNAP})"
    SQL_EXPR="ST_Transform(ST_SimplifyPreserveTopology(${INNER},${SIM}),4326)"
  elif [ -n "${SEG}" ] ; then
    INNER="ST_Segmentize(ST_Transform(Geometry,${T_SRS}),${SEG})"
    SQL_EXPR="ST_Transform(ST_SimplifyPreserveTopology(${INNER},${SIM}),4326)"
  elif [ -n "${SNAP}" ] ; then
    INNER="ST_SnapToGrid(ST_Transform(Geometry,${T_SRS}),${SNAP})"
    SQL_EXPR="ST_Transform(ST_SimplifyPreserveTopology(${INNER},${SIM}),4326)"
  else
    SQL_EXPR="ST_Transform(ST_SimplifyPreserveTopology(ST_Transform(Geometry,${T_SRS}),${SIM}),4326)"
  fi
else
  # Non-preserve branch: use ogr2ogr -t_srs ... -simplify
  echo "Non-preserve simplify path not implemented in script; falling back to ogr2ogr -simplify"
  ogr2ogr -f GeoJSONSeq /vsistdout/ data/terrain22.fgb -t_srs EPSG:${T_SRS} -simplify ${SIM} \
    | jq -c 'select(.geometry != null)' \
    | ${TIPPECANOE} -o data/terrain22.pmtiles -Z${TIP_MIN_Z} -z${TIP_MAX_Z} -l ${TIP_LAYER} ${TIPPE_OPTS} ${FORCE}
  exit $?
fi

# SQL to select simplified geometry and all properties
SQL="SELECT ${SQL_EXPR} AS geometry, * FROM ${TIP_LAYER} WHERE 1=1"
# Add bbox filter for safety? keeping layer-wide by default

# Try streaming pipeline first
set +e
ogr2ogr -f GeoJSONSeq /vsistdout/ data/terrain22.fgb -dialect SQLITE -sql "${SQL}" | jq -c 'select(.geometry != null)' | ${TIPPECANOE} -o data/terrain22.pmtiles -Z${TIP_MIN_Z} -z${TIP_MAX_Z} -l ${TIP_LAYER} ${TIPPE_OPTS} ${FORCE}
RC=$?
set -e

if [ ${RC} -eq 0 ] ; then
  echo "Streaming pipeline succeeded: data/terrain22.pmtiles written"
  exit 0
fi

# Fallback: write simplified GeoJSONSeq to tmpfile then run tippecanoe on it
echo "Streaming pipeline failed (rc=${RC}); falling back to temp-file method"
TMP=$(mktemp -t terrain22-XXXXXX.geojson)
trap 'rm -f "${TMP}" "${TMP}.filtered"' EXIT
ogr2ogr -f GeoJSONSeq "${TMP}" data/terrain22.fgb -dialect SQLITE -sql "${SQL}" -nln ${TIP_LAYER}
jq -c 'select(.geometry != null)' "${TMP}" > "${TMP}.filtered"
${TIPPECANOE} -o data/terrain22.pmtiles -Z${TIP_MIN_Z} -z${TIP_MAX_Z} -l ${TIP_LAYER} ${TIPPE_OPTS} ${FORCE} "${TMP}.filtered"

exit $?
