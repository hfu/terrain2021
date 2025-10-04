# ==============================================================================
# PRODUCTION TARGETS
# ==============================================================================

.PHONY: pipeline produce-fgb-parts pmtiles-area-minzoom-merge clean clean-data-temp clean-logs

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
	@echo "Producing per-ID FlatGeobuf files (GNU parallel -j6; fallback to xargs)." \
	&& mkdir -p parts
	# Prefer GNU parallel for robust production runs; fallback to xargs if missing
	@if command -v parallel >/dev/null 2>&1 ; then \
		echo "Using GNU parallel -j6 (DATA_DIR=parts)" ; \
		cat ids.txt | parallel -j7 --joblog joblog.txt --halt soon,fail=1 --linebuffer 'DATA_DIR=parts ./bin/ogr2ogr_id {}' ; \
	else \
		echo "GNU parallel not found; falling back to xargs (P=4, DATA_DIR=parts)" ; \
		cat ids.txt | xargs -n1 -P4 -I{} sh -c 'DATA_DIR=parts ./bin/ogr2ogr_id {}' ; \
	fi

# ==============================================================================
# DEPRECATED / LEGACY TARGETS (commented out)
# ==============================================================================

# # Union-based workflow (DEPRECATED: union/ directory removed)
# .PHONY: unions pmtiles-union
# unions: parts/*.fgb bin/make_unions.sh
# 	@echo "Creating per-part union fgb files under union/"
# 	@mkdir -p union
# 	@bin/make_unions.sh parts union
# 
# pmtiles-union: union/*.fgb bin/pmtiles_from_unions.sh
# 	@echo "Building data/terrain22.pmtiles from union/*.fgb (minzoom-friendly)"
# 	@mkdir -p data
# 	@TIPPECANOE="$(TIPPECANOE)" TIP_MIN_Z=1 TIP_MAX_Z="$(TIP_MAX_Z)" TIP_LAYER="$(TIP_LAYER)" \
# 	UNION_SIMPLIFY_METERS=75 SNAP_GRID_METERS=10 \
# 	bin/pmtiles_from_unions.sh data/terrain22.pmtiles
# 	@echo "Done: data/terrain22.pmtiles"

# # Per-part area-based builds (DEPRECATED: use pmtiles-area-minzoom-merge for production)
# .PHONY: pmtiles-area-minzoom-41 pmtiles-area-minzoom-all
# pmtiles-area-minzoom-41: bin/pmtiles_area_minzoom.sh parts/41.fgb
# 	@echo "Building PMTiles for part 41 with area-based minzoom (attributes not retained)"
# 	@mkdir -p data
# 	@TIPPECANOE="$(TIPPECANOE)" TIPPE_OPTS="$(TIPPE_OPTS)" TIP_MIN_Z=1 TIP_MAX_Z=12 \
# 	SNAP_GRID_METERS=$(AREA_MINZOOM_SNAP_METERS) PRE_SIMPLIFY_METERS=$(AREA_MINZOOM_PRE_SIMPLIFY_METERS) \
# 	MZ1_MIN=$(AREA_MINZOOM_MZ1_MIN) MZ2_MIN=$(AREA_MINZOOM_MZ2_MIN) MZ3_MIN=$(AREA_MINZOOM_MZ3_MIN) MZ4_MIN=$(AREA_MINZOOM_MZ4_MIN) MZ5_MIN=$(AREA_MINZOOM_MZ5_MIN) \
# 	INPUT_FGB=parts/41.fgb OUTPUT_PMTILES=data/terrain22_41.pmtiles \
# 	./bin/pmtiles_area_minzoom.sh
# 
# pmtiles-area-minzoom-all: bin/pmtiles_area_minzoom.sh
# 	@echo "Building area-based minzoom PMTiles per part with GNU parallel (jobs=$(PMTILES_JOBS))"
# 	@mkdir -p parts
# 	@if command -v parallel >/dev/null 2>&1 ; then \
# 		IN_LIST="$(wildcard parts/*.fgb)" ; \
# 		if [ -z "$$IN_LIST" ]; then echo "No parts/*.fgb found" ; exit 0 ; fi ; \
# 		parallel -j$(PMTILES_JOBS) --joblog joblog_pmtiles.txt --halt soon,fail=1 --linebuffer \
#  		'IN={}; OUT={.}.pmtiles; if [ -s "$$OUT" ] && [ "$$OUT" -nt "$$IN" ]; then echo "[skip] $$OUT"; else INPUT_FGB="$$IN" OUTPUT_PMTILES="$$OUT" TIPPECANOE="$(TIPPECANOE)" TIPPE_OPTS="$(TIPPE_OPTS)" TIP_MIN_Z=1 TIP_MAX_Z=12 SNAP_GRID_METERS=$(AREA_MINZOOM_SNAP_METERS) PRE_SIMPLIFY_METERS=$(AREA_MINZOOM_PRE_SIMPLIFY_METERS) MZ1_MIN=$(AREA_MINZOOM_MZ1_MIN) MZ2_MIN=$(AREA_MINZOOM_MZ2_MIN) MZ3_MIN=$(AREA_MINZOOM_MZ3_MIN) MZ4_MIN=$(AREA_MINZOOM_MZ4_MIN) MZ5_MIN=$(AREA_MINZOOM_MZ5_MIN) ./bin/pmtiles_area_minzoom.sh; fi' ::: $$IN_LIST ; \
# 	else \
# 		echo "GNU parallel not found; falling back to xargs (P=4)" ; \
# 		echo $(wildcard parts/*.fgb) | xargs -n1 -P4 -I{} sh -c 'IN={}; OUT=$${IN%.fgb}.pmtiles; if [ -s "$$OUT" ] && [ "$$OUT" -nt "$$IN" ]; then echo "[skip] $$OUT"; else INPUT_FGB="$$IN" OUTPUT_PMTILES="$$OUT" TIPPECANOE="$(TIPPECANOE)" TIPPE_OPTS="$(TIPPE_OPTS)" TIP_MIN_Z=1 TIP_MAX_Z=8 SNAP_GRID_METERS=$(AREA_MINZOOM_SNAP_METERS) PRE_SIMPLIFY_METERS=$(AREA_MINZOOM_PRE_SIMPLIFY_METERS) MZ1_MIN=$(AREA_MINZOOM_MZ1_MIN) MZ2_MIN=$(AREA_MINZOOM_MZ2_MIN) MZ3_MIN=$(AREA_MINZOOM_MZ3_MIN) MZ4_MIN=$(AREA_MINZOOM_MZ4_MIN) MZ5_MIN=$(AREA_MINZOOM_MZ5_MIN) ./bin/pmtiles_area_minzoom.sh; fi'; \
# 	fi

# # Legacy streaming merge (DEPRECATED: use pmtiles-area-minzoom-merge)
# .PHONY: merge merge-fgb pmtiles pmtiles-parallel
# merge: parts/*.fgb bin/pmtiles_merge_from_parts.sh
# 	@echo "Merging parts/*.fgb -> data/terrain22.pmtiles (streaming)"
# 	@mkdir -p data
# 	@TIPPECANOE="$(TIPPECANOE)" \
# 		TIPPE_OPTS="$(TIPPE_OPTS)" \
# 		SIMPLIFY_METERS="$(TIP_SIMPLIFY_METERS)" \
# 		bin/pmtiles_merge_from_parts.sh data/terrain22.pmtiles
# 
# merge-fgb: parts/*.fgb
# 	@echo "Merging parts into data/terrain2021.fgb (GeoJSONSeq streaming, EPSG:4326)"
# 	@mkdir -p data
# 	@./bin/merge_parts.sh
# 
# # Per-part PMTiles (DEPRECATED: use area-minzoom approach instead)
# parts/%.pmtiles: parts/%.fgb bin/pmtiles_part.sh
# 	@echo "Building $@ from $< (per-part pmtiles)"
# 	@TIPPECANOE="$(TIPPECANOE)" TIPPE_OPTS="$(TIPPE_OPTS)" TIP_MIN_Z="$(TIP_MIN_Z)" TIP_MAX_Z="$(TIP_MAX_Z)" TIP_LAYER="$(TIP_LAYER)" \
# 	SIMPLIFY_METERS="$(TIP_SIMPLIFY_METERS)" \
# 	bin/pmtiles_part.sh "$<" "$@"
# 
# pmtiles: $(patsubst parts/%.fgb,parts/%.pmtiles,$(wildcard parts/*.fgb))
# 	@echo "Built per-part PMTiles under parts/*.pmtiles"
# 
# pmtiles-parallel:
# 	@echo "Building per-part PMTiles with GNU parallel (jobs=$(PMTILES_JOBS))"
# 	@if command -v parallel >/dev/null 2>&1 ; then \
# 		IN_LIST="$(wildcard parts/*.fgb)" ; \
# 		if [ -z "$$IN_LIST" ]; then echo "No parts/*.fgb found" ; exit 0 ; fi ; \
# 		env TIPPECANOE="$(TIPPECANOE)" TIPPE_OPTS="$(TIPPE_OPTS)" TIP_MIN_Z="$(TIP_MIN_Z)" TIP_MAX_Z="$(TIP_MAX_Z)" TIP_LAYER="$(TIP_LAYER)" SIMPLIFY_METERS="$(TIP_SIMPLIFY_METERS)" \
# 		parallel -j$(PMTILES_JOBS) --joblog joblog_pmtiles.txt --halt soon,fail=1 --linebuffer 'in={}; out={.}.pmtiles; if [ -s "$$out" ] && [ "$$out" -nt "$$in" ]; then echo "[skip] $$out"; else bin/pmtiles_part.sh "$$in" "$$out"; fi' ::: $$IN_LIST ; \
# 	else \
# 		echo "GNU parallel not found; falling back to make -j$(PMTILES_JOBS) pmtiles" ; \
# 		$(MAKE) -j$(PMTILES_JOBS) pmtiles ; \
# 	fi

# # Attribute transform (DEPRECATED: transform is built into ogr2ogr_id)
# # transform:
# #     @echo "[deprecated] Transforming attributes to create data/terrain22.fgb (no longer used)"


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
TIPPE_OPTS ?= --force --no-simplification-of-shared-nodes --detect-longitude-wraparound --coalesce --coalesce-densest-as-needed --maximum-tile-bytes=24000000 --maximum-tile-features=1400000 --drop-smallest-as-needed --drop-densest-as-needed --drop-rate=0.3
PMTILES_JOBS ?= 2

# Area-based minzoom production defaults (finalized "strong" parameters)
AREA_MINZOOM_SNAP_METERS ?= 25
AREA_MINZOOM_PRE_SIMPLIFY_METERS ?= 12
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

