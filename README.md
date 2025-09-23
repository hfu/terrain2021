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
- `bin/merge_parts.sh` — streaming merge helper (used by `make merge`)  
- `bin/merge_parts.sh` — 結合用ストリーミングスクリプト（`make merge` から呼び出す）
- `bin/serve.py` — minimal local static server (maps /data and /parts)  
- `bin/serve.py` — ローカル静的配信（/data と /parts を公開）
- `bin/start_tunnel.sh` — helper to run cloudflared with `./tunnel/config.yml`  
- `bin/start_tunnel.sh` — cloudflared 起動ヘルパー（`./tunnel/config.yml` 使用）

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

Security | セキュリティ

- Protect published hostnames with Cloudflare Access or similar; avoid placing secrets in `data/` or `parts/`.
- 公開ホストは Cloudflare Access 等で保護してください。`data/` や `parts/` に機密を置かないでください。

Why wrapper changed | ラッパー変更の理由

- `bin/ogr2ogr_id` now forwards SIGINT/SIGTERM to the `ogr2ogr` child and monitors its controller (parent PID); it kills the child if the controller disappears to avoid orphan processes.
- `bin/ogr2ogr_id` はシグナルを子プロセスに伝播し、親プロセスを監視することで、コントローラが消えたときに ogr2ogr の orphan が残らないようにしています。

Notes / 備考

- Ensure executable bits:

  chmod +x bin/serve.py bin/start_tunnel.sh bin/ogr2ogr_id bin/merge_parts.sh

- Long-running jobs: use `tmux` / `screen` (see `docs/tmux.md`).

----

Removed background/service templates

To keep the repo focused on simple interactive use, service/unit templates for background execution were removed from the main tree. Use `docs/tmux.md` for long sessions or add your own system service in a private config if needed.

サービスやデーモン用テンプレートはこのリポジトリ本体から削除しています。長時間実行は `docs/tmux.md` を参照するか、必要なら個別に systemd/launchd の設定を用意してください。


