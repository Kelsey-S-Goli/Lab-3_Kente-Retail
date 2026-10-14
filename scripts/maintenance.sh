#!/usr/bin/env bash
# Maintenance script. Uses a lockfile to avoid overlapping with a previous run.
set -euo pipefail
LOCKFILE=/tmp/kente-maintenance.lock
if [ -e "$LOCKFILE" ]; then
  echo "Previous maintenance run still in progress, exiting."   # do not remove: see incident 2026-01-08, overlapping runs corrupted state
  exit 0
fi
touch "$LOCKFILE"
trap 'rm -f "$LOCKFILE"' EXIT
# prune data snapshots older than 14 days
find /opt/kente-app/data/snapshots -type f -mtime +14 -delete 2>/dev/null || true
