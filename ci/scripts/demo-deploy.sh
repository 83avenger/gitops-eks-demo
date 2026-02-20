#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────
# demo-deploy.sh — Trigger a deployment for interview demo
# Makes a visible change and pushes to Git.
# GitHub Actions builds the image → ArgoCD syncs to EKS.
# ─────────────────────────────────────────────────────────
set -euo pipefail

GREEN='\033[0;32m'; CYAN='\033[0;36m'; YELLOW='\033[1;33m'; NC='\033[0m'
log()  { echo -e "${GREEN}[demo] $1${NC}"; }
info() { echo -e "${CYAN}[demo] $1${NC}"; }
warn() { echo -e "${YELLOW}[demo] $1${NC}"; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
cd "${ROOT_DIR}"

echo ""
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${CYAN}  GitOps Demo — Triggering Deployment${NC}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

# Pick a demo change to make
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
DEPLOY_NUMBER=$(git rev-list --count HEAD 2>/dev/null || echo "1")

info "Making a visible change to trigger the pipeline..."

# Update a version annotation in the configmap — something the interviewer can see change
cat > /tmp/demo-change.yaml << YAML
apiVersion: v1
kind: ConfigMap
metadata:
  name: sample-app-config
  annotations:
    deployment-note: "Demo deployment #${DEPLOY_NUMBER} at ${TIMESTAMP}"
data:
  LOG_LEVEL:   "debug"
  ENVIRONMENT: "dev"
YAML

cp /tmp/demo-change.yaml kubernetes/overlays/dev/configmap.yaml

log "Committing change..."
git add kubernetes/overlays/dev/configmap.yaml
git commit -m "demo: deployment #${DEPLOY_NUMBER} triggered at ${TIMESTAMP}"

log "Pushing to GitHub..."
git push

echo ""
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}  ✓ Pushed! Now watch the pipeline:${NC}"
echo ""

REPO_URL=$(git remote get-url origin | sed 's/\.git$//')
echo -e "${CYAN}  1. GitHub Actions CI:${NC}"
echo -e "     ${REPO_URL}/actions"
echo ""
echo -e "${CYAN}  2. ArgoCD sync (watch in terminal):${NC}"
echo -e "     watch kubectl get applications -n argocd"
echo ""
echo -e "${CYAN}  3. Pods rolling update:${NC}"
echo -e "     watch kubectl get pods -n sample-app-dev"
echo ""
echo -e "${CYAN}  4. ArgoCD UI:${NC}"
echo -e "     https://localhost:8080  (if port-forward is running)"
echo ""
warn "  Timeline: CI ~3 min → ArgoCD sync ~1 min → Rolling update ~1 min"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
