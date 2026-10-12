#!/usr/bin/env bash
# Stops the worker container for a while to simulate an outage, then restarts it.
# Usage: ./scripts/chaos-kill-worker.sh [downtime_seconds]
set -euo pipefail

DOWNTIME="${1:-120}"

echo "Stopping worker to simulate an outage..."
docker compose stop worker

echo "Worker down. Waiting ${DOWNTIME}s before restoring..."
sleep "$DOWNTIME"

echo "Restoring worker..."
docker compose start worker
echo "Worker restored."
