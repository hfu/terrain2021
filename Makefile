# ==============================================================================
# PRODUCTION TARGETS
# ==============================================================================

.PHONY: pipeline produce-fgb-parts pmtiles-area-minzoom-merge clean clean-data-temp clean-logs

# Number of parallel jobs to use for produce-fgb-parts (can be overridden on the make command line)
N_PARALLEL_JOBS ?= 4

# Main production pipeline: parts/FGB -> merged PMTiles (area-based minzoom)
pipeline: produce-fgb-parts pmtiles-area-minzoom-merge
	@echo "Pipeline complete: parts FGB -> merged PMTiles (area-based minzoom, production default)"

# Merge all parts/*.fgb -> single data/terrain22.pmtiles (production default)
pmtiles-area-minzoom-merge: bin/pmtiles_area_minzoom_merge.sh parts/*.fgb
	@echo "Merging parts/*.fgb -> data/terrain22.pmtiles with area-based minzoom (single tippecanoe run)"
	@mkdir -p data
	@TIPPECANOE="$(TIPPECANOE)" TIPPE_OPTS="$(TIPPE_OPTS)" TIP_MIN_Z=1 TIP_MAX_Z=12 \
	SNAP_GRID_METERS=$(AREA_MINZOOM_SNAP_METERS) PRE_SIMPLIFY_METERS=$(AREA_MINZOOM_PRE_SIMPLIFY_METERS) \
	MZ1_MIN=$(AREA_MINZOOM_MZ1_MIN) MZ2_MIN=$(AREA_MINZOOM_MZ2_MIN) MZ3_MIN=$(AREA_MINZOOM_MZ3_MIN) MZ4_MIN=$(AREA_MINZOOM_MZ4_MIN) MZ5_MIN=$(AREA_MINZOOM_MZ5_MIN) \
	OUTPUT_PMTILES=data/terrain22.pmtiles \
	./bin/pmtiles_area_minzoom_merge.sh
	@echo "Done: data/terrain22.pmtiles"


produce-fgb-parts: ids.txt bin/ogr2ogr_id
	@echo "Producing per-ID FlatGeobuf files (GNU parallel; fallback to xargs). Using N_PARALLEL_JOBS=$(N_PARALLEL_JOBS)." \
	&& mkdir -p parts
	# Prefer GNU parallel for robust production runs; fallback to xargs if missing
	@if command -v parallel >/dev/null 2>&1 ; then \
			echo "Using GNU parallel -j$(N_PARALLEL_JOBS) (DATA_DIR=parts)" ; \
			cat ids.txt | parallel -j$(N_PARALLEL_JOBS) --joblog joblog.txt --halt soon,fail=1 --linebuffer 'DATA_DIR=parts ./bin/ogr2ogr_id {}' ; \
	else \
			echo "GNU parallel not found; falling back to xargs (P=$(N_PARALLEL_JOBS), DATA_DIR=parts)" ; \
			cat ids.txt | xargs -n1 -P$(N_PARALLEL_JOBS) -I{} sh -c 'DATA_DIR=parts ./bin/ogr2ogr_id {}' ; \
	fi

# ==============================================================================
# CONFIGURATION PARAMETERS
# ==============================================================================

# Tippecanoe / PMTiles tools
TIPPECANOE ?= tippecanoe
PMTILE_TOOL ?= pmtiles
TIP_MIN_Z ?= 1
TIP_MAX_Z ?= 12
TIP_LAYER ?= terrain22

# Tippecanoe options (overridable via make command line)
TIPPE_OPTS ?= --force --no-simplification-of-shared-nodes --detect-longitude-wraparound --coalesce --coalesce-densest-as-needed --coalesce-smallest-as-needed --maximum-tile-bytes=24000000 --maximum-tile-features=1400000 --drop-smallest-as-needed --drop-densest-as-needed --drop-rate=0.4
PMTILES_JOBS ?= 2

# Area-based minzoom production defaults (finalized "strong" parameters)
AREA_MINZOOM_SNAP_METERS ?= 25
AREA_MINZOOM_PRE_SIMPLIFY_METERS ?= 25
AREA_MINZOOM_MZ1_MIN ?= 20000000
AREA_MINZOOM_MZ2_MIN ?= 5000000
AREA_MINZOOM_MZ3_MIN ?= 1000000
AREA_MINZOOM_MZ4_MIN ?= 200000
AREA_MINZOOM_MZ5_MIN ?= 50000

# Legacy simplify settings (for deprecated workflows)
TIP_SIMPLIFY_METERS ?= 25
TIP_SIMPLIFY_PRESERVE ?= 1
TIP_SIMPLIFY_T_SRS ?= EPSG:3857
TIP_SIMPLIFY_T_SRS_EPSG ?= 3857
TIP_SEGMENTIZE_METERS ?= 10
TIP_SNAP_GRID_METERS ?= 5

# ==============================================================================
# SERVE / TUNNEL TARGETS  
# ==============================================================================

.PHONY: serve tunnel readme downloadable

serve:
	@echo "Run local static server exposing /data and /parts"
	@echo "Starting caddy (foreground). Use Ctrl-C to stop." && caddy run --config ./Caddyfile --adapter caddyfile
	# Note: large files may be served externally (e.g. via transient.optgeo.org). See DOWNLOADABLE.md for external download URLs.

tunnel:
	@echo "Start cloudflared using tunnel/config.yml (use bin/start_tunnel.sh)"
	@bash bin/start_tunnel.sh

readme:
	@echo "Generate README.md"
	@ruby -e "print File.read('README.md') if File.exist?('README.md')"

downloadable:
	@echo "Generate DOWNLOADABLE.md by probing transient.optgeo.org (falls back to local stat)"
	@./bin/generate_downloadable.py

# ==============================================================================
# CLEANUP TARGETS
# ==============================================================================

clean:
	rm -rf parts/* data/terrain*.fgb joblog.txt

# Remove temporary/experimental files under data/ without deleting main datasets  
# Keeps: data/terrain2021.fgb, data/terrain22.fgb, data/terrain22.pmtiles, data/terrain22_japan.fgb
clean-data-temp:
	@echo "Removing temporary files in data/ (logs, journals, backups, experimental PMTiles)"
	@rm -f data/*.log data/*.pmtiles-journal data/*.bak data/*.bak* data/*.tmp data/*~ data/.DS_Store
	@rm -f data/*kanto*.pmtiles
	@echo "Done."

# Remove job logs (top-level and pmtiles) and data logs
clean-logs:
	@echo "Removing job logs"
	@rm -f joblog.txt joblog_pmtiles.txt
	@rm -f data/*.log
	@echo "Done."

