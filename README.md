# terrain2021 — build instructions / ビルド手順

NOTE: This project prefers simple foreground execution for casual sharing. Use `make serve` to run a foreground server (stoppable with Ctrl-C).

## English (short)

Purpose

Produce per-part FlatGeobuf files from the Terrain2021 Poly source, merge them, and derive a filtered product (terrain22.fgb).

Quick commands

- Dry-run smoke test:

  cat ids.txt | head -n5 | parallel -j2 'DATA_DIR=parts bin/ogr2ogr_id {}'

- Produce (parallel):

  make produce

- Merge parts:

  make merge

- Transform attributes:

  make transform

Files & layout

- `ids.txt` — list of Poly IDs
- `parts/` — per-ID .fgb files
- `data/` — aggregate outputs (terrain2021.fgb, terrain22.fgb)
- `bin/ogr2ogr_id` — wrapper to create one part
- `bin/serve.py` — minimal local static server (maps /data and /parts)
- `bin/start_tunnel.sh` — helper to run cloudflared with ./tunnel/config.yml

Serve & publish (local + Cloudflare Tunnel)

- Start local server:

  make serve

  (or `python3 bin/serve.py --host 127.0.0.1 --port 8000`)

- Verify:

  curl -I [http://127.0.0.1:8000/data/](http://127.0.0.1:8000/data/)

  curl -I [http://127.0.0.1:8000/parts/](http://127.0.0.1:8000/parts/)

- Run tunnel (after editing `tunnel/config.yml`):

  make tunnel

  (or `bash bin/start_tunnel.sh`)

Security note

Protect published hostnames with Cloudflare Access or similar; avoid placing secrets in `data/` or `parts/`.

Why wrapper changed

`bin/ogr2ogr_id` now forwards SIGINT/SIGTERM to the `ogr2ogr` child and monitors its controller (parent PID); it kills the child if the controller disappears to avoid orphan processes.

## Japanese (簡潔)

目的

Terrain2021 の Poly データから各パートの FlatGeobuf を生成し、結合して属性フィルタ済みの成果物（terrain22.fgb）を作ること。

主要コマンド

- ドライラン検査:

  cat ids.txt | head -n5 | parallel -j2 'DATA_DIR=parts bin/ogr2ogr_id {}'

- 生成:

  make produce

- 結合:

  make merge

- 属性変換:

  make transform

ファイル構成

- `ids.txt` — Poly ID の一覧
- `parts/` — 個別生成の .fgb
- `data/` — 集約出力（terrain2021.fgb, terrain22.fgb）
- `bin/ogr2ogr_id` — 単一パート生成のラッパー
- `bin/serve.py` — ローカルで `/data` と `/parts` を配信する簡易サーバ
- `bin/start_tunnel.sh` — `./tunnel/config.yml` を使って cloudflared を起動するヘルパー

公開手順（ローカル＋Cloudflare Tunnel）

- ローカル起動:

  make serve

  （または `python3 bin/serve.py --host 127.0.0.1 --port 8000`）

- 動作確認:

  curl -I [http://127.0.0.1:8000/data/](http://127.0.0.1:8000/data/)

  curl -I [http://127.0.0.1:8000/parts/](http://127.0.0.1:8000/parts/)

- トンネル起動（`tunnel/config.yml` 編集後）:

  make tunnel

  （または `bash bin/start_tunnel.sh`）

セキュリティ

公開ホストは Cloudflare Access 等で保護してください。`data/` や `parts/` に機密を置かないでください。

ラッパーの変更理由

`bin/ogr2ogr_id` はシグナル伝播とコントローラ監視を行うようにしたため、親が死んだ場合でも ogr2ogr の orphan が残らないようになっています。

Notes / 備考

- スクリプト実行権を確認:

  chmod +x bin/serve.py bin/start_tunnel.sh bin/ogr2ogr_id

- 長時間実行は tmux/screen などで管理すると安定します。

Service and session templates

This project intentionally prefers simple foreground execution for casual sharing and testing. Use `make serve` which runs `bin/serve.py` in the foreground and can be stopped with Ctrl-C. Examples and templates for background/system services were removed to keep the repo minimal and focused on interactive use. For interactive long-running sessions you can still use `docs/tmux.md`.

