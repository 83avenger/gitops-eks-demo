# GitOps EKS Demo — Production-Ready Platform

A complete GitOps implementation on AWS EKS demonstrating enterprise-grade
infrastructure automation, security, and observability patterns.

## What This Builds

```
GitHub (Source of Truth)
  ├── Terraform IaC   → AWS EKS cluster + VPC + IAM (IRSA)
  ├── K8s Manifests   → Application + monitoring (Kustomize)
  └── ArgoCD Apps     → App-of-Apps GitOps pattern
         │ Continuous Sync
         ▼
AWS EKS Cluster
  ├── ArgoCD          → GitOps engine (HA, 2 replicas)
  ├── sample-app      → Demo app (dev/staging/prod overlays)
  ├── Prometheus + Grafana + Loki → Full observability
  ├── External Secrets → Zero secrets in Git (AWS SSM/SecretsManager)
  ├── OPA Gatekeeper  → Policy enforcement
  ├── KEDA            → Event-driven autoscaling
  └── Cluster Autoscaler → Node scaling
```

## Prerequisites

```bash
# Required tools
aws --version      # AWS CLI v2
terraform --version # >= 1.8.0
kubectl version    # >= 1.28
helm version       # >= 3.14
kustomize version  # >= 5.0
argocd version     # >= 2.11 (optional, for CLI operations)
```

## Quick Start

### Step 1 — Configure AWS credentials
```bash
aws configure
# Or use AWS SSO: aws sso login --profile your-profile
```

### Step 2 — Create Terraform state backend
```bash
aws s3 mb s3://your-terraform-state-bucket --region us-east-1
aws s3api put-bucket-versioning --bucket your-terraform-state-bucket \
  --versioning-configuration Status=Enabled
aws dynamodb create-table \
  --table-name terraform-state-lock \
  --attribute-definitions AttributeName=LockID,AttributeType=S \
  --key-schema AttributeName=LockID,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST \
  --region us-east-1
```

### Step 3 — Update configuration
```bash
# Edit terraform/environments/dev/main.tf
# Change: bucket = "your-terraform-state-bucket"
# Change: base_domain = "your-domain.com"
# Change: gitops_repo_url = "https://github.com/your-org/your-repo"

# Edit argocd/apps/*.yaml
# Change: repoURL to your repository URL
```

### Step 4 — Deploy infrastructure
```bash
cd terraform/environments/dev
terraform init
terraform plan -out=tfplan
terraform apply tfplan

# Note the outputs
terraform output kubeconfig_command
```

### Step 5 — Bootstrap ArgoCD
```bash
# Configure kubectl
aws eks update-kubeconfig --region us-east-1 --name gitops-eks-demo-dev

# Bootstrap ArgoCD and apply root App-of-Apps
./ci/scripts/bootstrap-argocd.sh gitops-eks-demo-dev us-east-1

# Access ArgoCD UI
kubectl port-forward svc/argocd-server -n argocd 8080:443
# Visit: https://localhost:8080
```

### Step 6 — Watch GitOps in action
```bash
# ArgoCD syncs everything automatically from Git
kubectl get applications -n argocd

# Watch sync status
watch kubectl get applications -n argocd -o wide

# Check sample-app in dev
kubectl get pods -n sample-app-dev
```

## Project Structure

```
gitops-eks-demo/
├── terraform/
│   ├── modules/
│   │   ├── vpc/        # VPC, subnets, NAT, flow logs
│   │   ├── eks/        # Cluster, node groups, KMS, IRSA
│   │   └── addons/     # ArgoCD, External Secrets, Gatekeeper, KEDA
│   └── environments/
│       ├── dev/        # SPOT nodes, 1 replica, debug logs
│       ├── staging/    # ON_DEMAND, 2 replicas, warn logs
│       └── prod/       # ON_DEMAND, 3+ replicas, WAF enabled
├── argocd/
│   ├── apps/           # App-of-Apps: root + child applications
│   ├── appsets/        # ApplicationSets for multi-env deployment
│   └── projects/       # RBAC: platform vs applications project
├── kubernetes/
│   ├── base/
│   │   ├── app/        # Core manifests: Deployment, Service, HPA, PDB,
│   │   │               # NetworkPolicy, ExternalSecret, Ingress
│   │   ├── monitoring/ # Prometheus stack, ServiceMonitor, Alert rules, Loki
│   │   └── security/   # OPA Gatekeeper ConstraintTemplates + Constraints
│   └── overlays/
│       ├── dev/        # Patches: 1 replica, SPOT-friendly, debug config
│       ├── staging/    # Patches: 2 replicas, staging secrets
│       └── prod/       # Patches: 3 replicas, WAF, pinned image tags
├── ci/
│   ├── github-actions/
│   │   ├── ci.yml      # Build → scan → push → update GitOps → promote
│   │   └── terraform.yml # Plan on PR, apply on merge, OIDC auth
│   └── scripts/
│       ├── bootstrap-argocd.sh
│       └── rollback.sh
└── monitoring/
    └── runbooks/       # High error rate, high latency, etc.
```

## CI/CD Flow

```
Developer pushes code
        │
        ▼
GitHub Actions CI
  1. Trivy SAST scan (filesystem)
  2. Semgrep security scan
  3. Build container image
  4. Trivy scan (container image) — fails on HIGH/CRITICAL CVEs
  5. Sign image with Cosign (SLSA provenance)
  6. kustomize edit set image → commit to Git
        │
        ▼ (ArgoCD detects Git change)
ArgoCD auto-syncs dev/staging
        │
        ▼ (Manual approval gate — GitHub Environments)
ArgoCD syncs prod
        │
        ▼
Slack notification
```

## Security Architecture

| Layer | Implementation |
|---|---|
| Cluster secrets encryption | KMS envelope encryption |
| Node metadata protection | IMDSv2 required, hop limit = 1 |
| IAM permissions | IRSA — zero node-level permissions |
| Secrets management | External Secrets + AWS SecretsManager |
| Network isolation | Default-deny NetworkPolicies |
| Pod security | Restricted PSS + non-root + read-only FS |
| Policy enforcement | OPA Gatekeeper constraints |
| Image security | Trivy scanning + Cosign signing |
| Control plane logging | All EKS log types → CloudWatch |
| VPC security | Flow logs + private node subnets |
| Container registry | GHCR with OIDC — no long-lived credentials |

## Operational Commands

```bash
# Check all application sync status
kubectl get applications -n argocd

# Force sync an application
argocd app sync sample-app-dev

# View application diff (what ArgoCD would change)
argocd app diff sample-app-prod

# Emergency rollback
./ci/scripts/rollback.sh sample-app-prod

# Check Gatekeeper violations
kubectl get k8srequiredresources.constraints.gatekeeper.sh
kubectl describe k8srequiredresources require-resource-limits

# Port-forward Grafana
kubectl port-forward svc/prometheus-stack-grafana 3000:80 -n monitoring

# View alerts
kubectl get prometheusrules -n monitoring
```

## Cost Optimisation (Dev environment)

- EKS node groups: **SPOT instances** (m5.xlarge + m5a.xlarge)
- Cluster Autoscaler: scales to zero non-system nodes at night
- Loki instead of ELK: ~80% storage cost reduction
- ALB group.name: shares one ALB across all dev apps

---

## Windows 11 Home Setup

See [WINDOWS-SETUP.md](./WINDOWS-SETUP.md) for full guide.

**Quick start on Windows:**
```powershell
# PowerShell (Admin) — install WSL2
wsl --install -d Ubuntu-22.04
# Restart PC, then open Ubuntu terminal:
```
```bash
# Inside WSL2 Ubuntu — install all tools
bash ci/scripts/install-tools-wsl.sh
aws configure   # region: ap-southeast-1
```

---

## Cost Reference (ap-southeast-1 Singapore)

| Scenario | Cost |
|---|---|
| Full cluster running | ~$0.42/hr (~$10/day) |
| Interview morning (4 hrs) | ~$1.70 |
| App nodes scaled to 0 | ~$0.19/hr (system + NAT only) |
| Cluster destroyed | $0.00 |
| **Monthly if left running** | **~$300 — always destroy!** |

```bash
make up       # Deploy (~15 min)
make status   # Check cost meter
make down     # Destroy (stop billing)
```
