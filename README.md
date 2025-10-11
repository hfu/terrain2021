# terrain2021 — build instructions / ビルド手順

## Production Pipeline | プロダクション パイプライン

This repository builds PMTiles from Terrain2021 Poly source data using an area-based minzoom pipeline that preserves small urban polygons while controlling low-zoom density.

このリポジトリは Terrain2021 Poly データから、小さな都市部ポリゴンを保持しつつ低ズーム密度を制御する area-based minzoom パイプラインを使って PMTiles を構築します。

### Quick Start | クイックスタート

**Production build:**
```sh
make pipeline
```

**Serve locally:**
```sh
make serve
```

Stop with Ctrl-C | Ctrl-C で停止

## Files & Layout | ファイル構成

- `ids.txt` — list of Poly IDs | Poly ID の一覧
- `parts/` — per-ID .fgb files | 個別生成の .fgb
- `data/terrain22.pmtiles` — **production output** | **プロダクション出力**
- `bin/ogr2ogr_id` — part generation wrapper | パート生成ラッパー
- `bin/pmtiles_area_minzoom_merge.sh` — **main pipeline script** | **メイン パイプライン スクリプト**
- `bin/serve.py` — local server | ローカルサーバ
- `tunnel/config.yml` — Cloudflare tunnel config | Cloudflare トンネル設定

## Production Flow | プロダクションフロー

The production pipeline uses area-based per-feature minzoom assignment to preserve small urban polygons while controlling tile density at low zoom levels.

**Build:** `make pipeline` runs `produce` → `pmtiles-area-minzoom-merge` and writes `data/terrain22.pmtiles`

**Parameters:** Production defaults are locked in Makefile variables. Override on command line if needed:
```sh
# Custom pre-simplification tolerance
PRE_SIMPLIFY_METERS=20 make pmtiles-area-minzoom-merge
```

**Output:** Single `data/terrain22.pmtiles` file (zoom 1-12) optimized for web serving.



Hybrid union mode (preserve small urban fragments)

- `make unions` generates `union/*.fgb` per part using `bin/make_unions.sh`. By default it performs an attribute-based union by `terrain22` with robust repairs.
- In datasets where small, detailed polygons (e.g., urban areas) are easily lost during union, enable the hybrid strategy within each part to “rescue” polygons that union cannot cover:

  - Overlay strategy (default): `HYBRID_UNION=1 HYBRID_STRATEGY=overlay`
    - For each terrain22 group, write one union polygon (if non-empty) and ALSO copy original polygons that are disjoint from that union (no overlap). This means union-representable area is compacted, while union-missed polygons are kept as-is — all within the same part and group.

  - Overlay-difference: `HYBRID_UNION=1 HYBRID_STRATEGY=overlay_diff DIFF_MIN_AREA=<meters^2>`
    - Similar to overlay, but for partially overlapping polygons it writes only the leftover piece `ST_Difference(original, union)` instead of copying the whole original. You can filter tiny slivers by setting `DIFF_MIN_AREA` (omit to keep all leftovers).

  - Ratio strategy: `HYBRID_UNION=1 HYBRID_STRATEGY=ratio RETAIN_RATIO=0.90`
    - For each group, if the union keeps at least RETAIN_RATIO of the original area, output only the union; otherwise copy all original polygons for that group. This is coarser but simpler.

  - Disable hybrid: `HYBRID_UNION=0` (or `HYBRID_STRATEGY=off`)
    - Always output union results (dropping NULL/empty unions).

Usage examples:

```sh
# overlay rescue within each part (default)
HYBRID_UNION=1 HYBRID_STRATEGY=overlay make unions

# overlay-difference with sliver filter (>= 10 m^2)
HYBRID_UNION=1 HYBRID_STRATEGY=overlay_diff DIFF_MIN_AREA=10 make unions

# ratio-based selection (use union only if it keeps >=95%)
HYBRID_UNION=1 HYBRID_STRATEGY=ratio RETAIN_RATIO=0.95 make unions

# turn off hybrid and force union everywhere
HYBRID_UNION=0 make unions
```

PMTiles / tippecanoe（日本語）

- `Makefile` に `pmtiles` ターゲットがあり、`data/terrain22.fgb` から直接 `data/terrain22.pmtiles` を生成することを目指しています（felt/tippecanoe のような tippecanoe の新しいビルドは FlatGeobuf を直接入力として扱え、.pmtiles を直接書き出せます）。

- 主要な変数（メイク実行時に上書き可能）:

  - `TIPPECANOE`（デフォルト `tippecanoe`）— tippecanoe バイナリのパス
  - `TIP_MIN_Z`（デフォルト `6`）— 最小ズーム
  - `TIP_MAX_Z`（デフォルト `8`）— 最大ズーム
  - `TIP_LAYER`（デフォルト `terrain22`）— タイルに設定するレイヤ名
  - `TIPPE_OPTS`（デフォルト `--no-simplification-of-shared-nodes --drop-smallest-as-needed --drop-densest-as-needed`）— tippecanoe に渡す追加オプション（ドロップ/簡略化の制御用）

注意: `tippecanoe` が `.pmtiles` を直接出力できない場合は、`TIPPECANOE` を新しいビルドに切り替えるか、MBTiles を経由して PMTiles に変換するフォールバックを追加できます。必要なら自動フォールバックを Makefile に追加します。

ログとしきい値スキャン
---------------------
`make pmtiles-area-minzoom-merge` 実行中の tippecanoe 出力は `joblog_pmtiles.txt` に保存され、ビルド後に付属のスクリプト `bin/scan_tippecanoe_log.py` がそのログを解析して、`--maximum-tile-features` を超えたタイル（ズーム/タイル座標/特徴数/しきい値）を `data/pmtiles_over_threshold_tiles.txt` に書き出します。問題のあるタイルを素早く把握するためにこのログを参照してください。

**Local server:**

```sh
make serve  # http://127.0.0.1:8000
```

**Public tunnel** (requires `tunnel/config.yml` setup):

```sh
make tunnel
```

**Files:** See `DOWNLOADABLE.md` for download URLs when tunnel is active.

## How to serve the files locally and expose them via Cloudflare Tunnel

If you want to host the `parts/` and `data/` directories from this repository and optionally expose
them through a Cloudflare Tunnel, follow these steps.

1. Start a local static server (Caddy is used in the Makefile):

```sh
# from the repository root
make serve
```

This runs Caddy in the foreground and serves the repository's static files (including `data/` and `parts`).

2. Start the Cloudflare Tunnel to expose the local server (Makefile helper):

```sh
# This target runs the helper script to start the tunnel (the script wraps cloudflared).
make tunnel
```

`make tunnel` calls `bin/start_tunnel.sh` which expects a configured `tunnel/config.yml` or the
Cloudflare credentials set up in your environment. Check `bin/start_tunnel.sh` for specific flags or
environment variable options.

Notes and troubleshooting:
- Ensure `cloudflared` is installed and you have created/authenticated a Cloudflare tunnel before
  running `make tunnel`.
- If `make serve` uses Caddy and you prefer a different static server (Python http.server, nginx,
  etc.), you can start that manually and then run `make tunnel` to expose it.
- Use `curl -I http://localhost:2015` (or the local port reported by `make serve`) to check the server.

## Notes | 注意点

- `parts/*.fgb` are cached; delete to force regeneration
- Use `docs/tmux.md` for long-running jobs  
- Ensure scripts are executable: `chmod +x bin/*`


Attribution / 出所と謝辞

- This project builds on public sources and tools. Where appropriate we link back to original files or datasets used; please consult the source URLs embedded in scripts such as `bin/ogr2ogr_id` for dataset locations.

- Data source and acknowledgement: the Terrain2021 (terrain2021) Poly dataset provided via the GISSTAR service (Geospatial Information Authority of Japan) is the primary input dataset used here. We are grateful to GIS and data providers for making this dataset available. Please cite GISSTAR / Terrain2021 when reusing derived products.

- Acknowledgements: thank you to the authors and maintainers of GDAL/OGR and FlatGeobuf. Community discussions about streaming GeoJSONSeq and FlatGeobuf conversion also informed parts of this implementation.

出所と謝辞

- 本プロジェクトは公開情報とツールに基づいて構築しています。使用データや参照元は `bin/ogr2ogr_id` 等のスクリプト内に記載していますのでご確認ください。

- データ出所と謝辞: 本作業で基礎データとして利用した Terrain2021（terrain2021）の Poly データは、国土地理院（GSI）の GISSTAR サービスから提供されています。データ提供者の皆様に感謝します。派生成果物を公開・再利用する際は GISSTAR / Terrain2021 の出典を明記してください。

- 謝辞: GDAL/OGR や FlatGeobuf の開発者・メンテナ、および GeoJSONSeq や FlatGeobuf のストリーミング変換に関するコミュニティの議論に感謝します。


## Operational decision: prefer ogr2ogr (no duckdb / no mapshaper)

We will not use duckdb or mapshaper for dissolve in the main pipeline. The postfilter experiment demonstrated functional behavior but produced high per-tile cost and repeated, overlapping dissolves that don't scale well. Instead, accept that parts can contain geometry errors and rely on GDAL/ogr2ogr for any part-level unions or preprocessing. This keeps the pipeline simple and predictable.

### How to revert to the non-dissolve merge (immediate)

Unset `DISSOLVE_TERRAIN22` or set it to `0` when running the merge/pmtiles workflow. Examples:

```sh
# merge without postfilter / dissolve (safe default)
DISSOLVE_TERRAIN22=0 make merge

# pmtiles build without postfilter dissolve
DISSOLVE_TERRAIN22=0 TIP_MIN_Z=0 TIP_MAX_Z=12 make pmtiles
```

### Part-level union with ogr2ogr (optional, per-part)

If you later want a per-part, attribute-based union (precompute low-zoom geometries once), use ogr2ogr's SQLite dialect to run a ST_Union per attribute. Example (replace `layername` and `attr` as appropriate):

```sh
# find layer name:
ogrinfo -ro -al parts/101.fgb

# run union by attribute (writes GeoJSON with one feature per attribute value)
ogr2ogr -f GeoJSON /tmp/part101_union.geojson parts/101.fgb -dialect sqlite -sql \
  "SELECT ST_Union(geometry) AS geometry, \"gcluster.REGIONID\" AS regionid FROM \"OGRGeoJSON\" GROUP BY \"gcluster.REGIONID\""

# optionally convert back to FlatGeobuf
ogr2ogr -f FlatGeobuf parts/101_union.fgb /tmp/part101_union.geojson
```

Notes:

- The SQL dialect and layer name may vary depending on GDAL versions and the datasource driver. Use `ogrinfo -al` to inspect the source layer name and attribute names.
- This approach accepts some geometry errors; repair steps can be added to `bin/fix_parts_fgb.sh` when needed. Precomputing per-part unions is a one-time or infrequent cost and avoids per-tile repetition.

### Policy summary

- Default behavior: non-dissolve merge (`DISSOLVE_TERRAIN22=0`). Use `make merge` / `make pmtiles` as usual. For low-zoom optimized output, prefer `make pmtiles-union` after `make unions`.
- For precomputed low-zoom simplification, prefer ogr2ogr per-part unions (as above) rather than a tile-local postfilter.

If you'd like, I can run a single part-level union using `ogr2ogr` now (e.g. for `parts/101.fgb`) and report timing and the resulting feature count. Otherwise we can continue with the non-dissolve merge immediately.


