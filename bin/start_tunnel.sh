#!/usr/bin/env bash
# Helper to start cloudflared tunnel using ./tunnel/config.yml
set -euo pipefail

# Usage: bin/start_tunnel.sh [--cors-origin ORIGIN] [--start-server]
# If --start-server is provided the script will start bin/serve.py in the background
# with the provided --cors-origin and then exec cloudflared. This is a convenience for
# quick local testing; foreground-first usage is still recommended for manual runs.

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
CONFIG="$ROOT_DIR/tunnel/config.yml"

START_SERVER=0
CORs_ORIGIN_ARG=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --start-server) START_SERVER=1; shift ;;
    --cors-origin) CORs_ORIGIN_ARG="$2"; shift 2 ;;
    *) echo "Unknown arg: $1"; exit 1 ;;
  esac
done

if ! command -v cloudflared >/dev/null 2>&1; then
  echo "cloudflared not found. Install from https://developers.cloudflare.com/cloudflare-one/connections/connect-apps/install-and-setup/installation"
  exit 2
fi

if [ ! -f "$CONFIG" ]; then
  echo "Config file not found: $CONFIG"
  echo "Copy tunnel/config.yml.sample to tunnel/config.yml and edit according to your tunnel id/credentials"
  exit 3
fi

if [ "$START_SERVER" -eq 1 ]; then
  # Start the local serve.py in background for convenience
  if [ -n "$CORs_ORIGIN_ARG" ]; then
    echo "Starting local server with CORS origin $CORs_ORIGIN_ARG"
    python3 "$ROOT_DIR/bin/serve.py" --host 127.0.0.1 --port 8000 --cors-origin "$CORs_ORIGIN_ARG" &
  else
    echo "Starting local server without CORS origin"
    python3 "$ROOT_DIR/bin/serve.py" --host 127.0.0.1 --port 8000 &
  fi
  # give server a moment to start
  sleep 1
fi

echo "Starting cloudflared with config $CONFIG"
exec cloudflared tunnel --config "$CONFIG" run
