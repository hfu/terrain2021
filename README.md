# terrain2021 — build instructions / ビルド手順

## Production Pipeline | プロダクション パイプライン

This repository builds PMTiles from Terrain2021 Poly source data using an area-based minzoom pipeline that preserves small urban polygons while controlling low-zoom density.

このリポジトリは Terrain2021 Poly データから、小さな都市部ポリゴンを保持しつつ低ズーム密度を制御する area-based minzoom パイプラインを使って PMTiles を構築します。

### Quick Start | クイックスタート

**Production build:**
```sh
make pipeline
```

**Serve locally with Martin (v0.19.3):**
```sh
make serve-martin  # SSR enabled / SSR 有効
```

**Serve locally (legacy):**
```sh
make serve
```

Stop with Ctrl-C | Ctrl-C で停止

## Files & Layout | ファイル構成

- `ids.txt` — list of Poly IDs | Poly ID の一覧
- `parts/` — per-ID .fgb files (53/68 completed) | 個別生成の .fgb (53/68 完了)
- `data/terrain22.pmtiles` — **production output** | **プロダクション出力**
- `bin/ogr2ogr_id` — part generation wrapper | パート生成ラッパー
- `bin/pmtiles_area_minzoom_merge.sh` — **main pipeline script** | **メイン パイプライン スクリプト**
- `bin/serve.py` — local server | ローカルサーバ
- `martin-config.yml` — Martin SSR config | Martin SSR 設定
- `style.json` — MapLibre style for SSR | SSR 用 MapLibre スタイル
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

**Current Progress:** 54/68 parts completed. Remaining IDs: 12, 13, 14, 15, 29, 35, 42, 43, 45, 56_2, 62, 64, 72, 74.

## Martin Server (v0.19.3) | Martin サーバー (v0.19.3)

Serve PMTiles with server-side rendering (SSR) using Martin for image tiles (PNG/JPEG).

Martin で PMTiles をサーバーサイドレンダリング (SSR) して画像タイル (PNG/JPEG) を配信。

**Setup:**

1. Create `style.json` (MapLibre style) and `martin-config.yml` (Martin config).
2. Run: `martin --config martin-config.yml`

**Example Config (martin-config.yml):**

```yaml
sources:
  terrain22:
    type: pmtiles
    path: data/terrain22.pmtiles
styles:
  terrain22-style:
    type: maplibre
    style: style.json
server:
  listen_addresses: ["0.0.0.0:3000"]
```

**Access:** `http://localhost:3000/terrain22/8/215/102.png` for image tiles.

## Hybrid Union Mode | ハイブリッドユニオンモード

Optional per-part unions to optimize low-zoom geometries. Use `make unions` with strategies like overlay or ratio.

低ズーム最適化のためのオプションのパート別ユニオン。`make unions` で overlay や ratio 戦略を使用。

## PMTiles / tippecanoe | PMTiles / tippecanoe

Direct .pmtiles generation from FlatGeobuf using tippecanoe.

tippecanoe で FlatGeobuf から直接 .pmtiles を生成。

- Variables: `TIPPECANOE`, `TIP_MIN_Z` (6), `TIP_MAX_Z` (8), `TIP_LAYER` (terrain22), `TIPPE_OPTS`.

## Log and Threshold Scan | ログとしきい値スキャン

`make pmtiles-area-minzoom-merge` logs to `joblog_pmtiles.txt` and scans for over-threshold tiles in `data/pmtiles_over_threshold_tiles.txt`.

## Local Server & Tunnel | ローカルサーバーとトンネル

**Local server:**

```sh
make serve  # http://127.0.0.1:8000
```

**Public tunnel:**

```sh
make tunnel
```

## Notes | 注意点

- `parts/*.fgb` are cached; delete to force regeneration
- Use `docs/tmux.md` for long-running jobs  
- Ensure scripts are executable: `chmod +x bin/*`

## Attribution | 出所と謝辞

Data source: Terrain2021 Poly from GISSTAR (Geospatial Information Authority of Japan). Cite GISSTAR / Terrain2021 when reusing.

Acknowledgements: GDAL/OGR, FlatGeobuf, and community discussions.

データ出所: GISSTAR の Terrain2021 Poly。謝辞: GDAL/OGR, FlatGeobuf, コミュニティ。


