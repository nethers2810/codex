#!/usr/bin/env bash
set -euo pipefail

echo "[1/4] Starting dashboard stack (Postgres + API + React web)..."
docker compose up -d --build

echo "[2/4] Waiting API healthy..."
for _ in $(seq 1 30); do
  if curl -sS http://localhost:8080/health >/dev/null 2>&1; then
    break
  fi
  sleep 2
done

echo "[3/4] Running security assessment and auto-importing result..."
API_IMPORT_URL="http://localhost:8080/api/assessments/import" \
TARGET_URL="${TARGET_URL:-http://127.0.0.1}" \
LARAVEL_PATH="${LARAVEL_PATH:-$PWD}" \
COMPOSE_FILE="${COMPOSE_FILE:-docker-compose.yml}" \
RUN_DOCKER_BENCH="${RUN_DOCKER_BENCH:-false}" \
RUN_ACTIVE_WEB_SCAN="${RUN_ACTIVE_WEB_SCAN:-false}" \
./security_assessment.sh

echo "[4/4] Done. Open dashboard: http://localhost:3000"
echo "API endpoint: http://localhost:8080/api/assessments/latest"
