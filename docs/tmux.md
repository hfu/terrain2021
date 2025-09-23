# Running long tasks with tmux

This document shows recommended tmux commands to run long-running tasks such as `make produce` or `make serve` so they survive terminal disconnects.

Quick start

- Start a named session:

  tmux new -s terrain

- Run the command you need, e.g.:

  make produce

- Detach the session: Ctrl-b d

- Reattach later:

  tmux attach -t terrain

Best practices

- Use a descriptive session name per workflow (terrain-produce, terrain-serve).
- If running multiple jobs, use separate tmux windows or panes.
- Log output to files if you need post-mortem investigation, e.g.:

  make produce 2>&1 | tee -a produce.log

日本語 (短く)

長時間ジョブは tmux で実行すると端末切断や SSH 切断で作業が失われません。

- セッション作成: tmux new -s terrain
- コマンド実行: make produce
- デタッチ: Ctrl-b d
- 再接続: tmux attach -t terrain
