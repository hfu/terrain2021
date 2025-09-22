.PHONY: produce merge transform clean readme

transform:
	@echo "Transforming attributes to create data/terrain22.fgb (streaming, no large temps)"
	@mkdir -p data
	# Strategy:
	# 1) Stream features from data/terrain2021.fgb as GeoJSONSeq (ogr2ogr -> /vsistdout/)
	# 2) Use jq to rewrite properties: keep/rename fields and keep geometry untouched
	# 3) Pipe into ogr2ogr reading from /vsistdin/ to create FlatGeobuf (layer name terrain22)
	# Compute terrain22 in SQL (so geometry is preserved by driver) and output GeoJSONSeq
	ogr2ogr -f GeoJSONSeq /vsistdout/ data/terrain2021.fgb -dialect SQLITE -sql "SELECT *, CASE \
	WHEN \"gcluster.GCLUSTER15\"=2 THEN 1 \
	WHEN \"gcluster.GCLUSTER15\"=3 THEN 2 \
	WHEN \"gcluster.GCLUSTER15\"=13 THEN 3 \
	WHEN \"gcluster.GCLUSTER15\"=12 THEN 4 \
	WHEN \"gcluster.GCLUSTER15\"=5 THEN 5 \
	WHEN \"gcluster.GCLUSTER15\"=4 THEN 6 \
	WHEN \"gcluster.GCLUSTER15\"=14 THEN 7 \
	WHEN \"gcluster.GCLUSTER15\"=10 THEN 8 \
	WHEN \"gcluster.GCLUSTER15\"=11 AND \"poly.Sinks\"=0 THEN 9 \
	WHEN \"gcluster.GCLUSTER15\"=11 AND \"poly.Sinks\"<>0 THEN 10 \
	WHEN \"gcluster.GCLUSTER15\"=7 AND \"poly.Sinks\"=0 THEN 11 \
	WHEN \"gcluster.GCLUSTER15\"=7 AND \"poly.Sinks\"<>0 THEN 12 \
	WHEN \"gcluster.GCLUSTER15\"=8 AND \"poly.Sinks\"=0 THEN 13 \
	WHEN \"gcluster.GCLUSTER15\"=8 AND \"poly.Sinks\"<>0 THEN 14 \
	WHEN \"gcluster.GCLUSTER15\"=9 AND \"poly.Sinks\"=0 THEN 15 \
	WHEN \"gcluster.GCLUSTER15\"=9 AND \"poly.Sinks\"<>0 THEN 16 \
	WHEN \"gcluster.GCLUSTER15\"=6 AND \"poly.Sinks\"=0 THEN 17 \
	WHEN \"gcluster.GCLUSTER15\"=6 AND \"poly.Sinks\"<>0 THEN 18 \
	WHEN \"gcluster.GCLUSTER15\"=1 AND \"poly.Sinks\"=0 THEN 19 \
	WHEN \"gcluster.GCLUSTER15\"=1 AND \"poly.Sinks\"<>0 THEN 20 \
	WHEN \"gcluster.GCLUSTER15\"=15 AND \"poly.Sinks\"=0 THEN 21 \
	WHEN \"gcluster.GCLUSTER15\"=15 AND \"poly.Sinks\"<>0 THEN 22 \
	ELSE NULL END AS terrain22 FROM poly" \
	| jq -c '(.properties) |= ( { Sinks: ."poly.Sinks", GCLUSTER40: ."gcluster.GCLUSTER40", GCLUSTER15: ."gcluster.GCLUSTER15", terrain22: .terrain22 } )' \
	| ogr2ogr -f FlatGeobuf data/terrain22.fgb '/vsistdin?buffer_limit=-1' -nln terrain22 -skipfailures

produce: ids.txt bin/ogr2ogr_id
	@echo "Producing per-ID FlatGeobuf files (GNU parallel -j6; fallback to xargs)." \
	&& mkdir -p parts
	# Prefer GNU parallel for robust production runs; fallback to xargs if missing
	@if command -v parallel >/dev/null 2>&1 ; then \
		echo "Using GNU parallel -j6 (DATA_DIR=parts)" ; \
		cat ids.txt | parallel -j6 --joblog joblog.txt --halt soon,fail=1 --linebuffer 'DATA_DIR=parts ./bin/ogr2ogr_id {}' ; \
	else \
		echo "GNU parallel not found; falling back to xargs (P=4, DATA_DIR=parts)" ; \
		cat ids.txt | xargs -n1 -P4 -I{} sh -c 'DATA_DIR=parts ./bin/ogr2ogr_id {}' ; \
	fi

merge: parts/*.fgb
	@echo "Merging parts into data/terrain2021.fgb"
	@mkdir -p data
	# Create dataset from the first part, then append others to preserve spatial index support
	first=$$(ls parts/*.fgb | head -n1) ; \
	if [ -z "$$first" ]; then echo "no parts found"; exit 1; fi ; \
	ogr2ogr -f FlatGeobuf data/terrain2021.fgb "$$first" ; \
	for p in $$(ls parts/*.fgb | tail -n +2); do \
		ogr2ogr -f FlatGeobuf -append -update data/terrain2021.fgb "$$p" ; \
	done

clean:
	rm -rf parts/* data/terrain*.fgb joblog.txt

readme:
	@echo "Generate README.md"
	@ruby -e "print File.read('README.md') if File.exist?('README.md')"
