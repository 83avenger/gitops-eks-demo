#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────
# run-local.sh — Run the demo app locally in Docker
# Use this to test before pushing to EKS
# ─────────────────────────────────────────────────────────
set -euo pipefail

GREEN='\033[0;32m'; CYAN='\033[0;36m'; NC='\033[0m'
log() { echo -e "${GREEN}[local] $1${NC}"; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
APP_DIR="${ROOT_DIR}/app"

log "Building image..."
docker build \
  --build-arg VERSION=local \
  --build-arg GIT_SHA=local \
  -t gitops-demo-app:local \
  "${APP_DIR}"

log "Starting container..."
docker rm -f gitops-demo-local 2>/dev/null || true

docker run -d \
  --name gitops-demo-local \
  -p 8080:8080 \
  -e ENVIRONMENT=local \
  -e LOG_LEVEL=debug \
  -e POD_NAME=local-pod \
  -e POD_NAMESPACE=local \
  -e NODE_NAME=local-machine \
  gitops-demo-app:local

sleep 2

echo ""
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${CYAN}  App running at: http://localhost:8080${NC}"
echo -e "${CYAN}  API info:        http://localhost:8080/api/info${NC}"
echo -e "${CYAN}  Health:          http://localhost:8080/healthz${NC}"
echo -e "${CYAN}  Metrics:         http://localhost:8080/metrics${NC}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

# Quick health check
log "Running health check..."
sleep 1
curl -s http://localhost:8080/healthz | python3 -m json.tool

log "Tailing logs (Ctrl+C to stop)..."
docker logs -f gitops-demo-local
