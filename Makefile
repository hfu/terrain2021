.PHONY: produce merge transform clean readme

# Produce per-part .fgb files into parts/ (use DATA_DIR=parts)
# Usage: make produce
produce:
	@echo "Producing per-part FlatGeobuf files into parts/ (6 parallel jobs)"
	@mkdir -p parts
	cat ids.txt | parallel -j6 --delay 0.2 --joblog joblog.txt 'DATA_DIR=parts RUN=1 bin/ogr2ogr_id {}'

# Merge all parts/*.fgb into one file data/terrain2021.fgb
merge:
	@echo "Merging parts into data/terrain2021.fgb"
	@mkdir -p data
	ogr2ogr -f FlatGeobuf data/terrain2021.fgb parts/*.fgb

# Transform attributes to produce terrain22.fgb (placeholder - see README for exact SQL)
transform:
	@echo "Transforming attributes to create data/terrain22.fgb"
	# Placeholder: exact ogr2ogr commands described in README
	@echo "See README.md for the transform steps"

clean:
	rm -rf parts/* data/terrain*.fgb joblog.txt ids_remaining.txt ids.txt.bak

readme:
	@echo "Generate README.md"
	@ruby -e "print File.read('README.md') if File.exist?('README.md')"
