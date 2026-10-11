#!/usr/bin/env bash
# Fires concurrent code executions against the API to simulate load.
# Usage: ./scripts/load-test.sh [count] [api_url]
set -euo pipefail

COUNT="${1:-30}"
API_URL="${2:-http://localhost:3000}"

echo "Firing $COUNT executions at $API_URL ..."
for i in $(seq 1 "$COUNT"); do
  curl -s -X POST "$API_URL/api/executions" \
    -H "Content-Type: application/json" \
    -d '{"language":"python","source":"print(1)"}' \
    > /dev/null &
done
wait
echo "Done — submitted $COUNT executions."
