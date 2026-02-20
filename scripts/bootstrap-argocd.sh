#!/usr/bin/env bash
# =============================================================================
# Bootstrap ArgoCD on EKS
# Usage: ./scripts/bootstrap-argocd.sh <environment>
# =============================================================================

set -euo pipefail

ENVIRONMENT=${1:-dev}
ARGOCD_VERSION="v2.9.3"
NAMESPACE="argocd"
CLUSTER_NAME="gitops-demo-${ENVIRONMENT}"
REGION="ap-southeast-1"

echo "════════════════════════════════════════════════════════"
echo "  Bootstrapping ArgoCD on EKS"
echo "  Environment : ${ENVIRONMENT}"
echo "  Cluster     : ${CLUSTER_NAME}"
echo "════════════════════════════════════════════════════════"

# ----------------------------------------------------------
# 0. Verify prerequisites
# ----------------------------------------------------------
for cmd in kubectl helm aws argocd; do
  if ! command -v $cmd &>/dev/null; then
    echo "ERROR: $cmd is required but not installed"
    exit 1
  fi
done

# Update kubeconfig
echo "▶ Updating kubeconfig..."
aws eks update-kubeconfig \
  --region "${REGION}" \
  --name "${CLUSTER_NAME}"

# Verify cluster connectivity
kubectl cluster-info || {
  echo "ERROR: Cannot connect to cluster ${CLUSTER_NAME}"
  exit 1
}

# ----------------------------------------------------------
# 1. Create ArgoCD namespace
# ----------------------------------------------------------
echo "▶ Creating argocd namespace..."
kubectl create namespace "${NAMESPACE}" --dry-run=client -o yaml | kubectl apply -f -

# Label for Pod Security Standards
kubectl label namespace "${NAMESPACE}" \
  pod-security.kubernetes.io/enforce=restricted \
  pod-security.kubernetes.io/warn=restricted \
  --overwrite

# ----------------------------------------------------------
# 2. Install ArgoCD via Helm
# ----------------------------------------------------------
echo "▶ Installing ArgoCD ${ARGOCD_VERSION}..."
helm repo add argo https://argoproj.github.io/argo-helm
helm repo update

helm upgrade --install argocd argo/argo-cd \
  --namespace "${NAMESPACE}" \
  --version "5.55.0" \
  --values - <<EOF
global:
  image:
    tag: "${ARGOCD_VERSION}"

server:
  replicas: 2
  env:
    - name: ARGOCD_SERVER_INSECURE
      value: "true"   # TLS terminated at ALB

  ingress:
    enabled: true
    ingressClassName: alb
    annotations:
      alb.ingress.kubernetes.io/scheme: internet-facing
      alb.ingress.kubernetes.io/target-type: ip
      alb.ingress.kubernetes.io/certificate-arn: "${CERTIFICATE_ARN:-}"
    hosts:
      - argocd-${ENVIRONMENT}.YOUR_DOMAIN.com
    https: true

  resources:
    requests:
      cpu: 100m
      memory: 128Mi
    limits:
      cpu: 500m
      memory: 512Mi

controller:
  replicas: 1
  resources:
    requests:
      cpu: 250m
      memory: 512Mi
    limits:
      cpu: 1000m
      memory: 2Gi

repoServer:
  replicas: 2
  resources:
    requests:
      cpu: 100m
      memory: 128Mi
    limits:
      cpu: 500m
      memory: 512Mi

applicationSet:
  replicas: 2

redis:
  resources:
    requests:
      cpu: 50m
      memory: 64Mi
    limits:
      cpu: 200m
      memory: 256Mi

configs:
  params:
    # Use Kustomize helm inflator
    server.insecure: true
  
  repositories:
    gitops-repo:
      url: https://github.com/YOUR_ORG/gitops-eks-demo.git
      name: gitops-eks-demo
      type: git

  # RBAC policy
  rbac:
    policy.csv: |
      p, role:readonly, applications, get, */*, allow
      p, role:readonly, certificates, get, *, allow
      p, role:readonly, clusters, get, *, allow
      p, role:readonly, repositories, get, *, allow
      p, role:developer, applications, *, dev/*, allow
      p, role:developer, applications, *, staging/*, allow
      g, dev-team, role:developer
      g, platform-team, role:admin
    policy.default: role:readonly

metrics:
  enabled: true
  serviceMonitor:
    enabled: true
    namespace: monitoring
    additionalLabels:
      release: kube-prometheus-stack
EOF

# ----------------------------------------------------------
# 3. Wait for ArgoCD to be ready
# ----------------------------------------------------------
echo "▶ Waiting for ArgoCD pods..."
kubectl rollout status deployment/argocd-server -n "${NAMESPACE}" --timeout=300s
kubectl rollout status deployment/argocd-repo-server -n "${NAMESPACE}" --timeout=300s

# ----------------------------------------------------------
# 4. Get initial admin password
# ----------------------------------------------------------
ADMIN_PASSWORD=$(kubectl get secret argocd-initial-admin-secret \
  -n "${NAMESPACE}" \
  -o jsonpath="{.data.password}" | base64 -d)

echo ""
echo "════════════════════════════════════════════════════════"
echo "  ArgoCD Bootstrap Complete!"
echo ""
echo "  URL:      https://argocd-${ENVIRONMENT}.YOUR_DOMAIN.com"
echo "  Username: admin"
echo "  Password: ${ADMIN_PASSWORD}"
echo ""
echo "  IMPORTANT: Change the admin password immediately!"
echo "  argocd account update-password"
echo ""
echo "  Next step:"
echo "  kubectl apply -f argocd/projects/projects.yaml"
echo "  kubectl apply -f argocd/apps/app-of-apps.yaml"
echo "════════════════════════════════════════════════════════"

# ----------------------------------------------------------
# 5. Apply ArgoCD Projects and App of Apps
# ----------------------------------------------------------
read -p "Apply ArgoCD projects and App of Apps now? [y/N] " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
  # Login to ArgoCD CLI
  argocd login "argocd-${ENVIRONMENT}.YOUR_DOMAIN.com" \
    --username admin \
    --password "${ADMIN_PASSWORD}" \
    --insecure

  kubectl apply -f argocd/projects/projects.yaml
  kubectl apply -f argocd/apps/app-of-apps.yaml

  echo "✅ ArgoCD App of Apps applied — sync will begin automatically"
fi
