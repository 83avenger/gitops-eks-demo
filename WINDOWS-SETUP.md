# Windows 11 Home — Setup Guide for GitOps EKS Demo

Windows 11 Home doesn't include Hyper-V by default, but **WSL2 works perfectly**
and is the recommended way to run this project. All Linux scripts work natively inside WSL2.

---

## Step 1 — Install WSL2 (Windows Subsystem for Linux)

Open **PowerShell as Administrator** (right-click Start → Terminal (Admin)):

```powershell
# Install WSL2 with Ubuntu 22.04 — one command does everything
wsl --install -d Ubuntu-22.04

# Restart your PC when prompted
```

After restart, Ubuntu will open and ask you to create a username and password.
**Write this down** — you'll use it every time.

---

## Step 2 — Install Windows Terminal (Recommended)

Install from Microsoft Store: search **"Windows Terminal"** → Install.

This gives you a proper tabbed terminal. Pin it to taskbar.

Set default profile to Ubuntu:
- Open Windows Terminal → Settings (Ctrl+,)
- Default Profile → Ubuntu-22.04

---

## Step 3 — Run the Automated Tool Installer

Once inside Ubuntu (WSL2), run this one script that installs everything:

```bash
# Open Ubuntu from Start Menu or Windows Terminal, then:
curl -fsSL https://raw.githubusercontent.com/your-org/gitops-eks-demo/main/ci/scripts/install-tools-wsl.sh | bash

# Or if you have the project cloned:
bash ci/scripts/install-tools-wsl.sh
```

If you prefer to install manually, see Step 4 below.

---

## Step 4 — Manual Tool Installation (inside Ubuntu/WSL2)

```bash
# Update apt
sudo apt-get update && sudo apt-get upgrade -y

# ── AWS CLI v2 ──────────────────────────────────────────────
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
sudo apt-get install unzip -y
unzip awscliv2.zip
sudo ./aws/install
rm -rf aws awscliv2.zip
aws --version  # Should show aws-cli/2.x.x

# ── Terraform 1.8.x ─────────────────────────────────────────
wget -O- https://apt.releases.hashicorp.com/gpg | \
  sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] \
  https://apt.releases.hashicorp.com $(lsb_release -cs) main" | \
  sudo tee /etc/apt/sources.list.d/hashicorp.list
sudo apt-get update && sudo apt-get install terraform -y
terraform --version  # Should show Terraform v1.8.x

# ── kubectl ─────────────────────────────────────────────────
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
rm kubectl
kubectl version --client  # Should show v1.30.x

# ── Helm ────────────────────────────────────────────────────
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
helm version  # Should show v3.x.x

# ── Kustomize ───────────────────────────────────────────────
curl -s "https://raw.githubusercontent.com/kubernetes-sigs/kustomize/master/hack/install_kustomize.sh" | bash
sudo mv kustomize /usr/local/bin/
kustomize version  # Should show v5.x.x

# ── ArgoCD CLI (optional — nice for demo commands) ──────────
VERSION=$(curl --silent "https://api.github.com/repos/argoproj/argo-cd/releases/latest" | grep '"tag_name"' | sed 's/.*"tag_name": "\(.*\)".*/\1/')
curl -sSL -o argocd "https://github.com/argoproj/argo-cd/releases/download/${VERSION}/argocd-linux-amd64"
sudo install -m 555 argocd /usr/local/bin/argocd
rm argocd
argocd version --client  # Should show v2.x.x

# ── jq and other utilities ──────────────────────────────────
sudo apt-get install -y jq bc git curl wget unzip python3
```

---

## Step 5 — Configure AWS Credentials

```bash
aws configure
```

You will be prompted for:
```
AWS Access Key ID:     [paste your key]
AWS Secret Access Key: [paste your secret]
Default region name:   ap-southeast-1
Default output format: json
```

**Where to get AWS credentials:**
1. Log into AWS Console → IAM → Users → Your user → Security credentials
2. Create Access Key → Application running outside AWS
3. Copy both keys immediately (secret shown only once)

**Verify it works:**
```bash
aws sts get-caller-identity
# Should return your Account ID, UserID, and ARN
```

---

## Step 6 — Clone the Project

```bash
# In WSL2 Ubuntu terminal
cd ~
git clone https://github.com/your-org/gitops-eks-demo.git
cd gitops-eks-demo
```

**Important WSL2 file location tip:**
Your WSL2 files are accessible from Windows Explorer at:
```
\\wsl$\Ubuntu-22.04\home\your-username\
```
Bookmark this in Windows Explorer for easy access.

---

## Step 7 — Deploy the Demo

```bash
# From the project root in WSL2
chmod +x ci/scripts/*.sh

# Spin everything up (~15 minutes)
./ci/scripts/demo-up.sh
```

---

## Daily Workflow (After Initial Setup)

```bash
# Open Windows Terminal → Ubuntu tab

# Morning of interview — spin up
cd ~/gitops-eks-demo
./ci/scripts/demo-up.sh

# Check what's running
./ci/scripts/demo-status.sh

# Open ArgoCD UI (keep this terminal open, open browser)
kubectl port-forward svc/argocd-server -n argocd 8080:443
# Browser: https://localhost:8080

# Open Grafana (in a new terminal tab)
kubectl port-forward svc/prometheus-stack-grafana 3000:80 -n monitoring
# Browser: http://localhost:3000

# After interview — ALWAYS destroy to stop billing
./ci/scripts/demo-down.sh
```

---

## Accessing UIs from Windows Browser

When you run `kubectl port-forward` inside WSL2, it's accessible from your
**Windows browser** at the same localhost address:

| Service | Command | Browser URL |
|---|---|---|
| ArgoCD | `kubectl port-forward svc/argocd-server -n argocd 8080:443` | https://localhost:8080 |
| Grafana | `kubectl port-forward svc/prometheus-stack-grafana 3000:80 -n monitoring` | http://localhost:3000 |
| Prometheus | `kubectl port-forward svc/prometheus-stack-prometheus 9090:9090 -n monitoring` | http://localhost:9090 |

This works because WSL2 automatically bridges network to Windows.

---

## VS Code Integration (Recommended for Interview Demos)

Install VS Code on Windows, then install the **WSL extension**:
1. Open VS Code → Extensions → search "WSL" → Install "WSL" by Microsoft
2. In WSL2 terminal: `code .` opens VS Code connected to WSL2

Install these VS Code extensions for the best demo experience:
- **Kubernetes** (Microsoft) — browse cluster resources visually
- **HashiCorp Terraform** — syntax highlighting and validation
- **YAML** (Red Hat) — Kubernetes manifest support
- **GitLens** — shows Git history in editor

---

## Common Windows-Specific Issues

**Issue: `chmod +x` doesn't work**
```bash
# Scripts must be run from WSL2, not Windows CMD/PowerShell
# Always use Ubuntu terminal for all commands
```

**Issue: Line ending errors (CRLF)**
```bash
# If you edit files in Windows Notepad and see errors
sudo apt-get install dos2unix
dos2unix ci/scripts/*.sh
```

**Issue: Port-forward not accessible in browser**
```bash
# Check WSL2 is binding to 0.0.0.0 not 127.0.0.1
kubectl port-forward --address 0.0.0.0 svc/argocd-server -n argocd 8080:443
```

**Issue: AWS CLI "Unable to locate credentials"**
```bash
# Credentials are stored per WSL2 user, not shared with Windows
aws configure  # Run this inside WSL2 terminal
```

**Issue: `terraform init` fails with TLS error**
```bash
# Usually a proxy or antivirus issue on corporate networks
# Try disabling VPN if connected
export HTTPS_PROXY=""
export HTTP_PROXY=""
terraform init
```

---

## Cost Reminders (Important!)

Set a **Windows alarm** or phone reminder when you spin up:

```bash
# Creates a reminder file on your Windows Desktop
cmd.exe /c "echo DESTROY EKS CLUSTER: cd ~/gitops-eks-demo && ./ci/scripts/demo-down.sh > %USERPROFILE%\Desktop\DESTROY-EKS-REMINDER.txt"
```

**Budget alert in AWS (do this once):**
```bash
aws budgets create-budget \
  --account-id $(aws sts get-caller-identity --query Account --output text) \
  --budget '{
    "BudgetName": "gitops-eks-demo-alert",
    "BudgetLimit": {"Amount": "20", "Unit": "USD"},
    "TimeUnit": "MONTHLY",
    "BudgetType": "COST"
  }' \
  --notifications-with-subscribers '[{
    "Notification": {
      "NotificationType": "ACTUAL",
      "ComparisonOperator": "GREATER_THAN",
      "Threshold": 10
    },
    "Subscribers": [{
      "SubscriptionType": "EMAIL",
      "Address": "your-email@gmail.com"
    }]
  }]'
```

This emails you when AWS spend exceeds $10 in a month — a safety net.
