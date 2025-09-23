#!/usr/bin/env bash
set -euo pipefail

# Simple CORS tester for bin/serve.py
# Starts the server on a test port with --cors-origin and checks that
# Access-Control-Allow-Origin is present for GET and OPTIONS requests.

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PORT=8001
ORIGIN="https://transient.optgeo.org"

cleanup() {
  if [ -n "${SERVER_PID:-}" ]; then
    echo "Killing server pid ${SERVER_PID}"
    kill "${SERVER_PID}" 2>/dev/null || true
    wait ${SERVER_PID} 2>/dev/null || true
  fi
}
trap cleanup EXIT INT TERM

echo "Starting test server on port ${PORT} with CORS origin ${ORIGIN}"
python3 "$ROOT_DIR/bin/serve.py" --host 127.0.0.1 --port ${PORT} --cors-origin ${ORIGIN} &
SERVER_PID=$!

# wait for server to be ready
for i in $(seq 1 10); do
  if curl -s -I "http://127.0.0.1:${PORT}/data/" >/dev/null 2>&1; then
    break
  fi
  sleep 0.2
done

echo "Testing GET /data/ with Origin header"
GET_HEADERS=$(curl -s -D - -o /dev/null -H "Origin: ${ORIGIN}" "http://127.0.0.1:${PORT}/data/" || true)
echo "$GET_HEADERS" | grep -i "Access-Control-Allow-Origin" || { echo "GET: CORS header missing"; exit 2; }

echo "Testing OPTIONS /data/ (preflight) with Origin"
OPTIONS_HEADERS=$(curl -s -D - -o /dev/null -X OPTIONS -H "Origin: ${ORIGIN}" -H "Access-Control-Request-Method: GET" "http://127.0.0.1:${PORT}/data/" || true)
echo "$OPTIONS_HEADERS" | grep -i "Access-Control-Allow-Origin" || { echo "OPTIONS: CORS header missing"; exit 3; }

echo "CORS test passed"
exit 0
