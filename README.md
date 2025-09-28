# terrain2021 — build instructions / ビルド手順

Short summary | 簡単な要約

- This repository produces per-part FlatGeobuf files, merges them, and derives a filtered product (`terrain22.fgb`).
- このリポジトリは各パートの FlatGeobuf を生成・結合し、フィルタ済み成果物（`terrain22.fgb`）を作成します。

Foreground-first note | フォアグラウンド優先の方針

- This project prefers simple foreground execution for casual sharing: use `make serve` (runs `bin/serve.py`) and stop it with Ctrl-C.
- このプロジェクトはカジュアルな共有用途を優先し、フォアグラウンド実行を推奨します: `make serve`（`bin/serve.py` を起動）を使い、Ctrl-C で停止してください。

----

English / 日本語 — quick reference (paired)

Purpose | 目的

- Produce per-part FlatGeobuf files from the Terrain2021 Poly source, merge them, and derive a filtered product (`terrain22.fgb`).
- Terrain2021 の Poly データから各パートの FlatGeobuf を生成し、結合してフィルタ済み成果物（`terrain22.fgb`）を生成します。

Quick commands | 主要コマンド

- Dry-run smoke test:

  cat ids.txt | head -n5 | parallel -j2 'DATA_DIR=parts bin/ogr2ogr_id {}'

- Produce (parallel):

  make produce

- Merge parts (streaming GeoJSONSeq):

  make merge

- Transform attributes (streaming, jq):

  make transform

Files & layout | ファイル構成

- `ids.txt` — list of Poly IDs  
- `ids.txt` — Poly ID の一覧
- `parts/` — per-ID .fgb files  
- `parts/` — 個別生成の .fgb
- `data/` — aggregate outputs (terrain2021.fgb, terrain22.fgb)  
- `data/` — 集約出力（terrain2021.fgb, terrain22.fgb）
- `bin/ogr2ogr_id` — wrapper to create one part  
- `bin/ogr2ogr_id` — 単一パート生成のラッパー
  - Note: `bin/ogr2ogr_id` now performs a quick existence check and will skip generation if `parts/{ID}.fgb` already exists and is non-empty. It also validates arguments and prints usage when called without an ID.
- `bin/merge_parts.sh` — streaming merge helper (used by `make merge`)  
- `bin/merge_parts.sh` — 結合用ストリーミングスクリプト（`make merge` から呼び出す）
- `bin/serve.py` — minimal local static server (maps /data and /parts)  
- `bin/serve.py` — ローカル静的配信（/data と /parts を公開）
- `bin/start_tunnel.sh` — helper to run cloudflared with `./tunnel/config.yml`  
- `bin/start_tunnel.sh` — cloudflared 起動ヘルパー（`./tunnel/config.yml` 使用）

PMTiles / tippecanoe (tiles) | PMTiles / tippecanoe（タイル生成）

- Makefile provides a `pmtiles` target to build tiles from `data/terrain22.fgb`:

  - Basic usage:

    make pmtiles

  - This calls `tippecanoe` to produce `data/terrain22.pmtiles` directly (newer `tippecanoe` builds such as felt/tippecanoe support writing `.pmtiles` and reading FlatGeobuf input). If your `tippecanoe` does not support `.pmtiles`, re-run with `TIPPECANOE=<path-to-new-tippecanoe>` or ask to add an MBTiles fallback.

  - Configurable variables (can be overridden on the make command line):

    - `TIPPECANOE` (default: `tippecanoe`) — path to the tippecanoe binary
    - `TIP_MIN_Z` (default: `6`) — minimum zoom to generate
    - `TIP_MAX_Z` (default: `8`) — maximum zoom to generate
    - `TIP_LAYER` (default: `terrain22`) — layer name written into tiles
    - `TIPPE_OPTS` (default: `--detect-shared-borders --drop-smallest-as-needed --drop-densest-as-needed`) — additional tippecanoe options. Adjust these to control dropping/simplification behavior.

  - Example with overrides:

    TIPPECANOE=/usr/local/bin/tippecanoe TIP_MAX_Z=9 make pmtiles

PMTiles / tippecanoe（日本語）

- `Makefile` に `pmtiles` ターゲットがあり、`data/terrain22.fgb` から直接 `data/terrain22.pmtiles` を生成することを目指しています（felt/tippecanoe のような tippecanoe の新しいビルドは FlatGeobuf を直接入力として扱え、.pmtiles を直接書き出せます）。

- 主要な変数（メイク実行時に上書き可能）:

  - `TIPPECANOE`（デフォルト `tippecanoe`）— tippecanoe バイナリのパス
  - `TIP_MIN_Z`（デフォルト `6`）— 最小ズーム
  - `TIP_MAX_Z`（デフォルト `8`）— 最大ズーム
  - `TIP_LAYER`（デフォルト `terrain22`）— タイルに設定するレイヤ名
  - `TIPPE_OPTS`（デフォルト `--detect-shared-borders --drop-smallest-as-needed --drop-densest-as-needed`）— tippecanoe に渡す追加オプション（ドロップ/簡略化の制御用）

注意: `tippecanoe` が `.pmtiles` を直接出力できない場合は、`TIPPECANOE` を新しいビルドに切り替えるか、MBTiles を経由して PMTiles に変換するフォールバックを追加できます。必要なら自動フォールバックを Makefile に追加します。

Serve & publish (local + Cloudflare Tunnel) | ローカルとトンネル公開

- Start local server (foreground):

  make serve

  (or `python3 bin/serve.py --host 127.0.0.1 --port 8000`)

- Verify:

  `curl -I http://127.0.0.1:8000/data/`

  `curl -I http://127.0.0.1:8000/parts/`

- Run tunnel (after editing `tunnel/config.yml`):

  make tunnel

  (or `bash bin/start_tunnel.sh`)

Downloadable files

- See `DOWNLOADABLE.md` for a curated list of files that may be downloaded from `transient.optgeo.org` when the tunnel is active.

Cloudflared / Tunnel deployment (brief) | Cloudflared トンネル（簡潔）

- Prerequisites: install `cloudflared` and authenticate your tunnel per Cloudflare docs.
- 前提: `cloudflared` をインストールし、トンネルを作成・認証してください（Cloudflare の手順に従う）。

- Example: run the local server (foreground) and start a tunnel that forwards to it.

  1. Run local server:

     `python3 bin/serve.py --host 127.0.0.1 --port 8000 --cors-origin https://transient.optgeo.org`

  2. Start cloudflared in another terminal (uses `tunnel/config.yml`):

     `bash bin/start_tunnel.sh`

- Note: Ensure `tunnel/config.yml` has the correct `ingress` service URL (e.g. `http://127.0.0.1:8000/data`).
- 注意: `tunnel/config.yml` の `ingress` が正しいローカル URL（例: `http://127.0.0.1:8000/data`）を指すようにしてください。

CORS example (allow `transient.optgeo.org`) | CORS 例（transient.optgeo.org を許可）

Run the server and allow requests from the transient.optgeo.org origin:

`python3 bin/serve.py --host 0.0.0.0 --port 8000 --cors-origin https://transient.optgeo.org`

Verify with curl (Origin header):

`curl -I -H "Origin: https://transient.optgeo.org" http://127.0.0.1:8000/data/`


Security | セキュリティ

- Protect published hostnames with Cloudflare Access or similar; avoid placing secrets in `data/` or `parts/`.
- 公開ホストは Cloudflare Access 等で保護してください。`data/` や `parts/` に機密を置かないでください。

Why wrapper changed | ラッパー変更の理由

- `bin/ogr2ogr_id` now forwards SIGINT/SIGTERM to the `ogr2ogr` child and monitors its controller (parent PID); it kills the child if the controller disappears to avoid orphan processes.
- `bin/ogr2ogr_id` はシグナルを子プロセスに伝播し、親プロセスを監視することで、コントローラが消えたときに ogr2ogr の orphan が残らないようにしています。

Notes / 備考

- Ensure executable bits:

  chmod +x bin/serve.py bin/start_tunnel.sh bin/ogr2ogr_id bin/merge_parts.sh

Cleanup guidance
- To remove temporary experiment artifacts (pmtiles and per-run logs) created during ad-hoc runs, run:

  ```sh
  rm -f data/pmtiles_*.log data/*kanto*.pmtiles pmtiles_full_run.log data/pmtiles_full_run.log
  ```

- Parts safety: `parts/*.fgb` are the canonical per-ID outputs; do not delete them unless you intend to regenerate from source. `bin/ogr2ogr_id` will skip existing parts to avoid unnecessary re-downloads.

- Long-running jobs: use `tmux` / `screen` (see `docs/tmux.md`).

----

Removed background/service templates

To keep the repo focused on simple interactive use, service/unit templates for background execution were removed from the main tree. Use `docs/tmux.md` for long sessions or add your own system service in a private config if needed.

サービスやデーモン用テンプレートはこのリポジトリ本体から削除しています。長時間実行は `docs/tmux.md` を参照するか、必要なら個別に systemd/launchd の設定を用意してください。


Attribution / 出所と謝辞

- This project builds on public sources and tools. Where appropriate we link back to original files or datasets used; please consult the source URLs embedded in scripts such as `bin/ogr2ogr_id` for dataset locations.

- Data source and acknowledgement: the Terrain2021 (terrain2021) Poly dataset provided via the GISSTAR service (Geospatial Information Authority of Japan) is the primary input dataset used here. We are grateful to GIS and data providers for making this dataset available. Please cite GISSTAR / Terrain2021 when reusing derived products.

- Acknowledgements: thank you to the authors and maintainers of GDAL/OGR and FlatGeobuf. Community discussions about streaming GeoJSONSeq and FlatGeobuf conversion also informed parts of this implementation.

出所と謝辞

- 本プロジェクトは公開情報とツールに基づいて構築しています。使用データや参照元は `bin/ogr2ogr_id` 等のスクリプト内に記載していますのでご確認ください。

- データ出所と謝辞: 本作業で基礎データとして利用した Terrain2021（terrain2021）の Poly データは、国土地理院（GSI）の GISSTAR サービスから提供されています。データ提供者の皆様に感謝します。派生成果物を公開・再利用する際は GISSTAR / Terrain2021 の出典を明記してください。

- 謝辞: GDAL/OGR や FlatGeobuf の開発者・メンテナ、および GeoJSONSeq や FlatGeobuf のストリーミング変換に関するコミュニティの議論に感謝します。


