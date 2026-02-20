#!/usr/bin/env bash
# Emergency rollback — reverts to previous ArgoCD revision
# Usage: ./ci/scripts/rollback.sh [app-name] [revision]

set -euo pipefail
APP_NAME=${1:-"sample-app-prod"}
REVISION=${2:-""}

GREEN='\033[0;32m'; RED='\033[0;31m'; NC='\033[0m'
log() { echo -e "${GREEN}[$(date +'%H:%M:%S')] $1${NC}"; }
error() { echo -e "${RED}[$(date +'%H:%M:%S')] ERROR: $1${NC}"; exit 1; }

command -v argocd &>/dev/null || error "argocd CLI not installed"

log "Current application status:"
argocd app get "${APP_NAME}" --grpc-web

if [ -z "${REVISION}" ]; then
  log "Available history:"
  argocd app history "${APP_NAME}" --grpc-web
  read -rp "Enter revision to rollback to: " REVISION
fi

log "Rolling back ${APP_NAME} to revision ${REVISION}..."
argocd app rollback "${APP_NAME}" "${REVISION}" --grpc-web

log "Monitoring rollback status..."
argocd app wait "${APP_NAME}" --health --timeout 300 --grpc-web

log "Rollback complete. New status:"
argocd app get "${APP_NAME}" --grpc-web
