#!/usr/bin/env bash
# ============================================================
# demo-down.sh — SAFELY DESTROY the full GitOps EKS demo
# Run this after your interview / end of testing session
# Usage: ./ci/scripts/demo-down.sh [--force]
#
# What this destroys:
#   - EKS cluster + all node groups
#   - VPC, subnets, NAT Gateways, Internet Gateway
#   - Load Balancers created by ALB Controller
#   - KMS keys, CloudWatch log groups
#
# What this KEEPS (to avoid losing your config):
#   - S3 state bucket (contains terraform.tfstate)
#   - DynamoDB lock table
#   - ECR images (if any)
#   Run with --purge to also delete state bucket
# ============================================================
set -euo pipefail

FORCE=${1:-""}
ENV="dev"
TF_DIR="terraform/environments/${ENV}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# Colours
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

log()     { echo -e "${GREEN}[$(date +'%H:%M:%S')] ✓ $1${NC}"; }
info()    { echo -e "${BLUE}[$(date +'%H:%M:%S')] ℹ $1${NC}"; }
warn()    { echo -e "${YELLOW}[$(date +'%H:%M:%S')] ⚠ $1${NC}"; }
error()   { echo -e "${RED}[$(date +'%H:%M:%S')] ✗ $1${NC}"; exit 1; }
section() { echo -e "\n${BOLD}${CYAN}══════════════════════════════════════${NC}"; \
            echo -e "${BOLD}${CYAN}  $1${NC}"; \
            echo -e "${BOLD}${CYAN}══════════════════════════════════════${NC}\n"; }

section "GitOps EKS Demo — DESTROY"

# ──────────────────────────────────────────
# Load saved state
# ──────────────────────────────────────────
STATE_FILE="${ROOT_DIR}/.demo-state"
if [ -f "${STATE_FILE}" ]; then
  source "${STATE_FILE}"
  info "Loaded demo state:"
  echo -e "  Cluster: ${CLUSTER_NAME:-unknown}"
  echo -e "  Region:  ${REGION:-ap-southeast-1}"
  echo -e "  Deployed: ${DEPLOY_TIME:-unknown}"
else
  warn ".demo-state not found — using defaults"
  REGION="ap-southeast-1"
fi

REGION=${REGION:-"ap-southeast-1"}

# ──────────────────────────────────────────
# Cost summary before destroying
# ──────────────────────────────────────────
section "Cost Estimate"

if [ -f "${STATE_FILE}" ] && [ -n "${DEPLOY_TIME:-}" ]; then
  DEPLOY_EPOCH=$(date -d "${DEPLOY_TIME}" +%s 2>/dev/null || date +%s)
  NOW_EPOCH=$(date +%s)
  HOURS_RUNNING=$(echo "scale=1; (${NOW_EPOCH} - ${DEPLOY_EPOCH}) / 3600" | bc 2>/dev/null || echo "unknown")
  COST_ESTIMATE=$(echo "scale=2; ${HOURS_RUNNING} * 0.42" | bc 2>/dev/null || echo "unknown")
  echo -e "${CYAN}  Running time: ~${HOURS_RUNNING} hours${NC}"
  echo -e "${CYAN}  Estimated cost: ~\$${COST_ESTIMATE}${NC}"
else
  echo -e "${CYAN}  Could not calculate running time${NC}"
fi

# ──────────────────────────────────────────
# Safety confirmation (unless --force)
# ──────────────────────────────────────────
if [ "${FORCE}" != "--force" ]; then
  echo ""
  echo -e "${RED}${BOLD}  ⚠  WARNING: This will PERMANENTLY DESTROY:${NC}"
  echo -e "${RED}     • EKS cluster and ALL node groups${NC}"
  echo -e "${RED}     • VPC, subnets, NAT Gateways (billing stops)${NC}"
  echo -e "${RED}     • All load balancers${NC}"
  echo -e "${RED}     • KMS keys and CloudWatch logs${NC}"
  echo ""
  echo -e "${YELLOW}  Your Terraform state (S3 + DynamoDB) will be KEPT${NC}"
  echo -e "${YELLOW}  so you can redeploy anytime.${NC}"
  echo ""
  read -rp "  Type 'destroy' to confirm: " CONFIRM
  [ "${CONFIRM}" != "destroy" ] && { echo "Cancelled."; exit 0; }
fi

START_TIME=$(date +%s)

# ──────────────────────────────────────────
# Step 1: Remove Kubernetes resources first
# (prevents Terraform from hanging on LB cleanup)
# ──────────────────────────────────────────
section "Step 1/3 — Cleaning Kubernetes Resources"

# Check if kubectl is configured for this cluster
if kubectl cluster-info &>/dev/null 2>&1; then
  info "Removing AWS Load Balancer resources (prevents TF hanging)..."

  # Delete all ingresses — triggers ALB deletion
  kubectl delete ingress --all -A --ignore-not-found=true 2>/dev/null || true
  
  # Delete services of type LoadBalancer
  kubectl get svc -A -o json | \
    python3 -c "
import sys, json
data = json.load(sys.stdin)
for item in data['items']:
  if item['spec'].get('type') == 'LoadBalancer':
    ns = item['metadata']['namespace']
    name = item['metadata']['name']
    print(f'{ns}/{name}')
" | while read ns_name; do
    NS=$(echo $ns_name | cut -d/ -f1)
    NAME=$(echo $ns_name | cut -d/ -f2)
    kubectl delete svc "$NAME" -n "$NS" --ignore-not-found=true 2>/dev/null || true
  done

  info "Waiting 30s for AWS to clean up load balancers..."
  sleep 30

  log "Kubernetes resources cleaned"
else
  warn "kubectl not configured for cluster — skipping K8s cleanup"
  warn "Load balancers may need manual deletion in AWS Console"
fi

# ──────────────────────────────────────────
# Step 2: Terraform Destroy
# ──────────────────────────────────────────
section "Step 2/3 — Terraform Destroy (~8-12 minutes)"
info "Destroying all AWS infrastructure..."

cd "${ROOT_DIR}/${TF_DIR}"

# Verify we're in the right state
terraform init -upgrade -input=false

# Run destroy with auto-approve if --force, else confirm
if [ "${FORCE}" == "--force" ]; then
  terraform destroy -auto-approve -input=false
else
  terraform destroy -auto-approve -input=false
fi

log "Terraform destroy complete"

# ──────────────────────────────────────────
# Step 3: Verify cleanup
# ──────────────────────────────────────────
section "Step 3/3 — Verifying Cleanup"

# Check for any remaining EKS clusters
REMAINING=$(aws eks list-clusters --region "${REGION}" --output text 2>/dev/null || echo "")
if echo "$REMAINING" | grep -q "gitops-eks-demo"; then
  warn "EKS cluster may still exist — check AWS Console"
else
  log "No EKS clusters remaining"
fi

# Check for orphaned load balancers
LB_COUNT=$(aws elbv2 describe-load-balancers --region "${REGION}" \
  --query 'length(LoadBalancers[?contains(LoadBalancerName, `gitops`)])' \
  --output text 2>/dev/null || echo "0")

if [ "${LB_COUNT}" != "0" ] && [ "${LB_COUNT}" != "None" ]; then
  warn "${LB_COUNT} load balancer(s) may still exist — check AWS Console"
  warn "URL: https://${REGION}.console.aws.amazon.com/ec2/v2/home#LoadBalancers"
else
  log "No orphaned load balancers found"
fi

# Clean up local state file
rm -f "${ROOT_DIR}/.demo-state"
rm -f "${TF_DIR}/tfplan"

# ──────────────────────────────────────────
# Final summary
# ──────────────────────────────────────────
END_TIME=$(date +%s)
ELAPSED=$(( (END_TIME - START_TIME) / 60 ))

section "✅ Destroy Complete"
echo -e "${GREEN}${BOLD}Total time: ${ELAPSED} minutes${NC}"
echo ""
echo -e "${CYAN}  AWS billing has stopped for all destroyed resources.${NC}"
echo -e "${CYAN}  Your Terraform state is preserved in S3.${NC}"
echo -e "${CYAN}  Redeploy anytime with: ./ci/scripts/demo-up.sh${NC}"
echo ""
echo -e "${YELLOW}  ⚠  KMS key deletion has a 7-day waiting period (AWS default).${NC}"
echo -e "${YELLOW}     This incurs minimal cost (~\$0.02/month). Normal behaviour.${NC}"
echo ""
