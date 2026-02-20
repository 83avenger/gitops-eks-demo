#!/usr/bin/env bash
# demo-status.sh — Check what's running and estimated cost so far
set -euo pipefail

REGION="ap-southeast-1"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
STATE_FILE="${ROOT_DIR}/.demo-state"

CYAN='\033[0;36m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
RED='\033[0;31m'; BOLD='\033[1m'; NC='\033[0m'

echo -e "\n${BOLD}${CYAN}══ GitOps EKS Demo Status ══${NC}\n"

# Cost meter
if [ -f "${STATE_FILE}" ]; then
  source "${STATE_FILE}"
  DEPLOY_EPOCH=$(date -d "${DEPLOY_TIME}" +%s 2>/dev/null || date +%s)
  NOW_EPOCH=$(date +%s)
  HOURS=$(echo "scale=2; (${NOW_EPOCH} - ${DEPLOY_EPOCH}) / 3600" | bc 2>/dev/null || echo "?")
  COST=$(echo "scale=2; ${HOURS} * 0.42" | bc 2>/dev/null || echo "?")
  echo -e "${YELLOW}  💰 Running: ~${HOURS} hours  |  Cost so far: ~\$${COST}${NC}\n"
fi

# Cluster status
echo -e "${CYAN}  EKS Cluster:${NC}"
aws eks list-clusters --region "${REGION}" --output table 2>/dev/null || echo "  (not deployed)"

# K8s status
if kubectl cluster-info &>/dev/null 2>&1; then
  echo -e "\n${CYAN}  Nodes:${NC}"
  kubectl get nodes -o wide 2>/dev/null | head -10

  echo -e "\n${CYAN}  ArgoCD Applications:${NC}"
  kubectl get applications -n argocd 2>/dev/null || echo "  ArgoCD not running"

  echo -e "\n${CYAN}  Application Pods:${NC}"
  kubectl get pods -n sample-app-dev 2>/dev/null || echo "  sample-app-dev not found"
fi

echo ""
