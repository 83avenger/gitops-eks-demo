#!/usr/bin/env bash
# Bootstrap ArgoCD — run once after cluster creation
# Usage: ./ci/scripts/bootstrap-argocd.sh [cluster-name] [region]

set -euo pipefail

CLUSTER_NAME=${1:-"gitops-eks-demo-dev"}
REGION=${2:-"ap-southeast-1"}
ARGOCD_VERSION="2.11.4"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
log() { echo -e "${GREEN}[$(date +'%H:%M:%S')] $1${NC}"; }
warn() { echo -e "${YELLOW}[$(date +'%H:%M:%S')] WARNING: $1${NC}"; }
error() { echo -e "${RED}[$(date +'%H:%M:%S')] ERROR: $1${NC}"; exit 1; }

# Prerequisites check
for cmd in kubectl helm aws kustomize; do
  command -v $cmd &>/dev/null || error "$cmd not found. Install it first."
done

log "Configuring kubectl for cluster: ${CLUSTER_NAME}"
aws eks update-kubeconfig --region "${REGION}" --name "${CLUSTER_NAME}"

log "Verifying cluster connectivity..."
kubectl cluster-info || error "Cannot connect to cluster"

# Install ArgoCD
log "Installing ArgoCD ${ARGOCD_VERSION}..."
kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
helm repo add argo https://argoproj.github.io/argo-helm
helm repo update

helm upgrade --install argocd argo/argo-cd \
  --version "${ARGOCD_VERSION}" \
  --namespace argocd \
  --set server.replicas=2 \
  --set repoServer.replicas=2 \
  --set applicationSet.replicas=2 \
  --set configs.params."server\.insecure"=true \
  --wait \
  --timeout 10m

log "Waiting for ArgoCD to be ready..."
kubectl rollout status deployment/argocd-server -n argocd --timeout=5m

# Create ArgoCD Projects
log "Creating ArgoCD Projects..."
kubectl apply -f argocd/projects/platform.yaml

# Apply root App-of-Apps
log "Applying root application..."
kubectl apply -f argocd/apps/root-app.yaml

# Get initial admin password
INITIAL_PASSWORD=$(kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d 2>/dev/null || echo "")

log "======================================="
log "ArgoCD Bootstrap Complete!"
log "======================================="
log "Access ArgoCD UI:"
log "  kubectl port-forward svc/argocd-server -n argocd 8080:443"
log "  URL: https://localhost:8080"
log "  Username: admin"
if [ -n "${INITIAL_PASSWORD}" ]; then
  log "  Password: ${INITIAL_PASSWORD}"
else
  warn "Could not retrieve initial password — check argocd-initial-admin-secret"
fi
log ""
log "ArgoCD will now sync all applications from Git."
log "Monitor sync status:"
log "  kubectl get applications -n argocd"
