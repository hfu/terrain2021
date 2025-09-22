terrain2021 — build instructions

Overview

This repository downloads the Terrain2021 Poly datasets, converts each Poly_NNN shapefile into FlatGeobuf (.fgb) and finally merges and post-processes them into a single dataset (terrain2021.fgb), then applies attribute filtering to produce terrain22.fgb.

Safety

- This process downloads many large files and may use significant network and disk resources. Ensure you have enough free space.
- By default the produce step runs parts creation into `parts/`. The final merged datasets are written to `data/`.

Files & layout

- `ids.txt` — ordered list of Poly IDs to produce (currently ordered small-first)
- `parts/` — per-part .fgb files produced by the `produce` target
- `data/` — holds final merged files `terrain2021.fgb` and `terrain22.fgb`
- `bin/ogr2ogr_id` — small wrapper to run ogr2ogr for a single ID; honors DATA_DIR and RUN env vars
- `Makefile` — contains targets: produce, merge, transform, clean

Quick commands

- Smoke test (dry-run):
  cat ids.txt | head -n5 | parallel -j2 'DATA_DIR=parts bin/ogr2ogr_id {}'

- Produce (execute, 6 parallel jobs):
  make produce

- Merge all parts into single FlatGeobuf:
  make merge

- Transform attributes to create terrain22 (see Transform section below):
  make transform

Transform / attribute filtering

The attribute transformation logic is taken from https://github.com/optgeo/terrain22/blob/908263906dc5e1af2de5b62a05a1246475a7e2e9/filter.rb (see lines ~6-40). That script reads GeoJSON features and sets a single property `terrain22` based on existing properties `b.GCLUSTER15` and `a.Sinks`.

We can implement this logic in ogr2ogr with a SQL-based approach combined with a virtual field construction. The general strategy:

1. Use ogr2ogr -sql to select existing attributes and add a computed field `terrain22` using a CASE expression. Example pattern (pseudo-SQL):

   ogr2ogr -f FlatGeobuf data/terrain22.fgb data/terrain2021.fgb -sql "SELECT *, CASE WHEN b_GCLUSTER15=2 THEN 1 WHEN b_GCLUSTER15=3 THEN 2 WHEN b_GCLUSTER15=13 THEN 3 WHEN b_GCLUSTER15=12 THEN 4 WHEN b_GCLUSTER15=5 THEN 5 WHEN b_GCLUSTER15=4 THEN 6 WHEN b_GCLUSTER15=14 THEN 7 WHEN b_GCLUSTER15=10 THEN 8 WHEN b_GCLUSTER15=11 AND a_Sinks=0 THEN 9 WHEN b_GCLUSTER15=11 AND a_Sinks<>0 THEN 10 ... ELSE NULL END AS terrain22 FROM layer"

2. Field naming: Shapefile/FlatGeobuf field names may map differently; before writing the exact SQL we recommend inspecting `ogrinfo -al data/terrain2021.fgb` to get exact field names (like `b.GCLUSTER15` may appear as `b_GCLUSTER15` or similar).

3. If the CASE is long, use a temporary SQL view or a small script to generate the SQL text.

Limitations and considerations

- GDAL SQL supports CASE and simple arithmetic/conditional expressions; the mapping in `filter.rb` is a direct CASE mapping and should be expressible in SQL.
- The `sinks == 0.0` checks map to numeric equality; be cautious about NULLs.
- If SQL gets too big or field names are awkward, you can do an intermediate GeoJSON export, run the Ruby filter.rb, and re-import. That is slower but easiest to match exactly.

Suggested next steps

1. If you want me to run the full production now: I will move existing `data/` to `parts/`, create an empty `data/`, remove `ids_remaining.txt` and `ids.txt.bak`, then run `make produce` which uses 6 parallel jobs.

2. After production completes, run `make merge` to create `data/terrain2021.fgb`, then run `make transform`. I can implement the exact ogr2ogr SQL for `transform` if you confirm you want a pure-ogr2ogr approach; otherwise I can include a fallback (export -> filter.rb -> reimport).

Tell me to proceed with the full run now, or ask for the pure-ogr2ogr `transform` SQL to be implemented first. If you want me to proceed, I'll start the run and report progress.