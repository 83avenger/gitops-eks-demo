#!/usr/bin/env bash
# ============================================================
# demo-up.sh — Spin up the full GitOps EKS demo
# Run this the morning before an interview (~15 min total)
# Usage: ./ci/scripts/demo-up.sh
# ============================================================
set -euo pipefail

REGION="ap-southeast-1"
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

START_TIME=$(date +%s)

section "GitOps EKS Demo — Spin Up"
echo -e "${CYAN}Region:      ${REGION}${NC}"
echo -e "${CYAN}Environment: ${ENV}${NC}"
echo -e "${CYAN}Started:     $(date)${NC}\n"

# ──────────────────────────────────────────
# Prerequisites check
# ──────────────────────────────────────────
section "Step 1/5 — Checking Prerequisites"

MISSING=()
for cmd in aws terraform kubectl helm kustomize; do
  if command -v $cmd &>/dev/null; then
    log "$cmd found: $(${cmd} version --short 2>/dev/null | head -1 || ${cmd} version 2>/dev/null | head -1 || echo 'ok')"
  else
    MISSING+=("$cmd")
    warn "$cmd NOT FOUND"
  fi
done

[ ${#MISSING[@]} -gt 0 ] && error "Missing tools: ${MISSING[*]}. Run WSL setup first."

info "Checking AWS credentials..."
AWS_IDENTITY=$(aws sts get-caller-identity --output json 2>/dev/null) || \
  error "AWS credentials not configured. Run: aws configure"

AWS_ACCOUNT=$(echo "$AWS_IDENTITY" | python3 -c "import sys,json; print(json.load(sys.stdin)['Account'])")
AWS_USER=$(echo "$AWS_IDENTITY" | python3 -c "import sys,json; print(json.load(sys.stdin)['Arn'])")
log "AWS Account: ${AWS_ACCOUNT}"
log "AWS Identity: ${AWS_USER}"

# ──────────────────────────────────────────
# Terraform State Backend
# ──────────────────────────────────────────
section "Step 2/5 — Terraform State Backend"

STATE_BUCKET="gitops-eks-demo-tfstate-${AWS_ACCOUNT}"
LOCK_TABLE="gitops-eks-demo-tfstate-lock"

# Create S3 bucket if it doesn't exist
if aws s3 ls "s3://${STATE_BUCKET}" &>/dev/null; then
  log "State bucket already exists: ${STATE_BUCKET}"
else
  info "Creating state bucket: ${STATE_BUCKET}"
  aws s3 mb "s3://${STATE_BUCKET}" --region "${REGION}"
  aws s3api put-bucket-versioning \
    --bucket "${STATE_BUCKET}" \
    --versioning-configuration Status=Enabled \
    --region "${REGION}"
  aws s3api put-bucket-encryption \
    --bucket "${STATE_BUCKET}" \
    --server-side-encryption-configuration \
    '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}' \
    --region "${REGION}"
  log "State bucket created and configured"
fi

# Create DynamoDB lock table if it doesn't exist
if aws dynamodb describe-table --table-name "${LOCK_TABLE}" --region "${REGION}" &>/dev/null; then
  log "Lock table already exists: ${LOCK_TABLE}"
else
  info "Creating DynamoDB lock table..."
  aws dynamodb create-table \
    --table-name "${LOCK_TABLE}" \
    --attribute-definitions AttributeName=LockID,AttributeType=S \
    --key-schema AttributeName=LockID,KeyType=HASH \
    --billing-mode PAY_PER_REQUEST \
    --region "${REGION}" > /dev/null
  log "Lock table created"
fi

# Patch backend config with real bucket name
cd "${ROOT_DIR}/${TF_DIR}"
sed -i "s|bucket.*=.*\".*\"|bucket         = \"${STATE_BUCKET}\"|" main.tf
sed -i "s|dynamodb_table.*=.*\".*\"|dynamodb_table = \"${LOCK_TABLE}\"|" main.tf

# ──────────────────────────────────────────
# Terraform Deploy
# ──────────────────────────────────────────
section "Step 3/5 — Deploying Infrastructure (EKS + VPC + Addons)"
info "This takes 10-15 minutes. Go make a coffee ☕"

# Generate backend.conf dynamically — uses real bucket name and correct region
cat > backend.conf << BACKENDEOF
bucket         = "${STATE_BUCKET}"
key            = "gitops-eks-demo/dev/terraform.tfstate"
region         = "${REGION}"
encrypt        = true
dynamodb_table = "${LOCK_TABLE}"
BACKENDEOF

log "Generated backend.conf for region ${REGION}, bucket ${STATE_BUCKET}"

info "Initialising Terraform..."
terraform init -upgrade -backend-config=backend.conf -reconfigure

terraform validate
terraform plan -out=tfplan -input=false

info "Applying Terraform (EKS cluster deployment)..."
terraform apply -auto-approve tfplan

CLUSTER_NAME=$(terraform output -raw cluster_name)
KUBECONFIG_CMD=$(terraform output -raw kubeconfig_command)

log "Cluster deployed: ${CLUSTER_NAME}"

# ──────────────────────────────────────────
# Configure kubectl
# ──────────────────────────────────────────
section "Step 4/5 — Configuring kubectl"

info "Updating kubeconfig..."
aws eks update-kubeconfig \
  --region "${REGION}" \
  --name "${CLUSTER_NAME}"

info "Waiting for nodes to be Ready..."
kubectl wait --for=condition=Ready nodes \
  --all --timeout=300s || warn "Some nodes not ready yet — continuing"

log "Cluster nodes:"
kubectl get nodes -o wide

# ──────────────────────────────────────────
# Bootstrap ArgoCD
# ──────────────────────────────────────────
section "Step 5/5 — Bootstrapping ArgoCD (GitOps Engine)"

cd "${ROOT_DIR}"
bash ci/scripts/bootstrap-argocd.sh "${CLUSTER_NAME}" "${REGION}"

# ──────────────────────────────────────────
# Summary
# ──────────────────────────────────────────
END_TIME=$(date +%s)
ELAPSED=$(( (END_TIME - START_TIME) / 60 ))

section "🚀 Demo Ready!"
echo -e "${GREEN}${BOLD}Total time: ${ELAPSED} minutes${NC}\n"

ARGOCD_PASS=$(kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" 2>/dev/null | base64 -d || echo "check secret manually")

echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${CYAN}  ARGOCD UI (run in separate terminal):${NC}"
echo -e "${CYAN}  kubectl port-forward svc/argocd-server -n argocd 8080:443${NC}"
echo -e "${CYAN}  Open: https://localhost:8080${NC}"
echo -e "${CYAN}  User: admin${NC}"
echo -e "${CYAN}  Pass: ${ARGOCD_PASS}${NC}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "${CYAN}  GRAFANA (run in separate terminal):${NC}"
echo -e "${CYAN}  kubectl port-forward svc/prometheus-stack-grafana 3000:80 -n monitoring${NC}"
echo -e "${CYAN}  Open: http://localhost:3000 (admin/prom-operator)${NC}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "${YELLOW}  ⚠  COST REMINDER: This cluster costs ~\$0.42/hour${NC}"
echo -e "${YELLOW}  Run ./ci/scripts/demo-down.sh when finished!${NC}"
echo ""

# Save cluster info for destroy script
cat > "${ROOT_DIR}/.demo-state" << EOF
CLUSTER_NAME=${CLUSTER_NAME}
REGION=${REGION}
STATE_BUCKET=${STATE_BUCKET}
LOCK_TABLE=${LOCK_TABLE}
DEPLOY_TIME=$(date)
EOF

log "Demo state saved to .demo-state"
