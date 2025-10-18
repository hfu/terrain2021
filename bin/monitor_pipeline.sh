#!/usr/bin/env bash
# Simple monitor for the produce-fgb-parts pipeline
# Appends periodic snapshots to logs/monitor.log

set -euo pipefail
LOG_DIR=logs
LOG_FILE=${LOG_DIR}/monitor.log
PID_FILE=${LOG_DIR}/monitor_pid.txt
INTERVAL=${INTERVAL:-600} # default 600s = 10min
mkdir -p "$LOG_DIR"

echo "Starting monitor at $(date -u +'%Y-%m-%dT%H:%M:%SZ')" >> "$LOG_FILE"
echo $$ > "$PID_FILE"

while true; do
  echo "--- monitor snapshot: $(date +'%Y-%m-%d %H:%M:%S') ---" >> "$LOG_FILE"
  echo "Processes (parallel / ogr2ogr)" >> "$LOG_FILE"
  ps aux | egrep 'parallel|ogr2ogr' | egrep -v 'egrep|sed' >> "$LOG_FILE" || true

  echo "\nTop CPU processes" >> "$LOG_FILE"
  ps -eo pid,ppid,stat,pcpu,pmem,comm,args --sort=-pcpu | head -n 20 >> "$LOG_FILE" || true

  echo "\nParts count & newest" >> "$LOG_FILE"
  ls -1 parts 2>/dev/null | wc -l >> "$LOG_FILE" 2>/dev/null || true
  ls -lt parts | head -n 20 >> "$LOG_FILE" 2>/dev/null || true

  echo "\njoblog tail" >> "$LOG_FILE"
  tail -n 100 joblog.txt >> "$LOG_FILE" 2>/dev/null || true

  echo "\ndisk usage" >> "$LOG_FILE"
  df -h . >> "$LOG_FILE" 2>/dev/null || true

  echo "\n" >> "$LOG_FILE"
  sleep "$INTERVAL"
done
