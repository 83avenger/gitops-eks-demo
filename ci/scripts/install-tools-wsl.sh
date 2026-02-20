#!/usr/bin/env bash
# ============================================================
# install-tools-wsl.sh — One-shot tool installer for WSL2/Ubuntu
# Run this once after setting up WSL2 on Windows 11
# Usage: bash ci/scripts/install-tools-wsl.sh
# ============================================================
set -euo pipefail

GREEN='\033[0;32m'; CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'
log() { echo -e "${GREEN}[$(date +'%H:%M:%S')] ✓ $1${NC}"; }
info() { echo -e "${CYAN}[$(date +'%H:%M:%S')] → $1${NC}"; }

echo -e "\n${BOLD}${CYAN}Installing DevOps tools for WSL2/Ubuntu${NC}\n"

# Update system
info "Updating apt..."
sudo apt-get update -qq && sudo apt-get upgrade -y -qq

# Install base utilities
info "Installing base utilities..."
sudo apt-get install -y -qq curl wget unzip jq bc git python3 apt-transport-https \
  ca-certificates gnupg lsb-release software-properties-common

# ── AWS CLI v2 ──────────────────────────────────────────────
info "Installing AWS CLI v2..."
if ! command -v aws &>/dev/null; then
  curl -s "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "/tmp/awscliv2.zip"
  unzip -q /tmp/awscliv2.zip -d /tmp/awscli
  sudo /tmp/awscli/aws/install
  rm -rf /tmp/awscliv2.zip /tmp/awscli
  log "AWS CLI installed: $(aws --version 2>&1 | head -1)"
else
  log "AWS CLI already installed: $(aws --version 2>&1 | head -1)"
fi

# ── Terraform ───────────────────────────────────────────────
info "Installing Terraform..."
if ! command -v terraform &>/dev/null; then
  wget -qO- https://apt.releases.hashicorp.com/gpg | \
    sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
  echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] \
    https://apt.releases.hashicorp.com $(lsb_release -cs) main" | \
    sudo tee /etc/apt/sources.list.d/hashicorp.list > /dev/null
  sudo apt-get update -qq && sudo apt-get install -y -qq terraform
  log "Terraform installed: $(terraform version | head -1)"
else
  log "Terraform already installed: $(terraform version | head -1)"
fi

# ── kubectl ─────────────────────────────────────────────────
info "Installing kubectl..."
if ! command -v kubectl &>/dev/null; then
  KUBECTL_VERSION=$(curl -L -s https://dl.k8s.io/release/stable.txt)
  curl -sLO "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl"
  sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
  rm kubectl
  log "kubectl installed: $(kubectl version --client --short 2>/dev/null || kubectl version --client)"
else
  log "kubectl already installed"
fi

# ── Helm ────────────────────────────────────────────────────
info "Installing Helm..."
if ! command -v helm &>/dev/null; then
  curl -s https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash > /dev/null 2>&1
  log "Helm installed: $(helm version --short)"
else
  log "Helm already installed: $(helm version --short)"
fi

# ── Kustomize ───────────────────────────────────────────────
info "Installing Kustomize..."
if ! command -v kustomize &>/dev/null; then
  KUSTOMIZE_VERSION=$(curl -s https://api.github.com/repos/kubernetes-sigs/kustomize/releases/latest \
    | python3 -c "import sys,json; v=json.load(sys.stdin)['tag_name']; print(v.replace('kustomize/',''))")
  curl -sLO "https://github.com/kubernetes-sigs/kustomize/releases/download/kustomize%2F${KUSTOMIZE_VERSION}/kustomize_${KUSTOMIZE_VERSION}_linux_amd64.tar.gz"
  tar xzf "kustomize_${KUSTOMIZE_VERSION}_linux_amd64.tar.gz"
  sudo mv kustomize /usr/local/bin/
  rm -f "kustomize_${KUSTOMIZE_VERSION}_linux_amd64.tar.gz"
  log "Kustomize installed: $(kustomize version)"
else
  log "Kustomize already installed: $(kustomize version)"
fi

# ── ArgoCD CLI ──────────────────────────────────────────────
info "Installing ArgoCD CLI..."
if ! command -v argocd &>/dev/null; then
  ARGOCD_VERSION=$(curl -s https://api.github.com/repos/argoproj/argo-cd/releases/latest \
    | python3 -c "import sys,json; print(json.load(sys.stdin)['tag_name'])")
  curl -sLo argocd \
    "https://github.com/argoproj/argo-cd/releases/download/${ARGOCD_VERSION}/argocd-linux-amd64"
  sudo install -m 555 argocd /usr/local/bin/argocd
  rm argocd
  log "ArgoCD CLI installed: $(argocd version --client --short 2>/dev/null | head -1)"
else
  log "ArgoCD CLI already installed"
fi

# ── Verify all tools ────────────────────────────────────────
echo ""
echo -e "${BOLD}${CYAN}══ Installation Summary ══${NC}"
for cmd in aws terraform kubectl helm kustomize argocd; do
  if command -v $cmd &>/dev/null; then
    echo -e "${GREEN}  ✓ $cmd${NC}"
  else
    echo -e "${RED}  ✗ $cmd — FAILED${NC}"
  fi
done

echo ""
echo -e "${CYAN}Next step: Configure AWS credentials${NC}"
echo -e "${CYAN}  aws configure${NC}"
echo -e "${CYAN}  (Region: ap-southeast-1)${NC}"
echo ""
