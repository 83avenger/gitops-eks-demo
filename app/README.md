# GitOps Demo Application

A simple FastAPI app purpose-built to demonstrate GitOps deployments visually.

## What It Shows on the Dashboard

- **Version** — changes when a new image is built by CI
- **Environment** — dev (red) / staging (yellow) / prod (green) — colour coded
- **Pod Name** — changes with every rolling update, proving new pods deployed
- **Node Name** — shows which EKS node it is running on
- **Uptime** — resets to 0 when pod is replaced

## Run Locally (before pushing to EKS)

```bash
bash ci/scripts/run-local.sh
# Open http://localhost:8080
```

## Trigger a Demo Deployment

```bash
bash ci/scripts/demo-deploy.sh
```

This pushes a git commit → GitHub Actions builds new image →
ArgoCD detects new manifest → EKS rolling update.
Total time ~5 minutes end-to-end.

## Endpoints

| URL | Purpose |
|-----|---------|
| `/` | Visual dashboard (auto-refreshes every 10s) |
| `/api/info` | JSON with version, pod, node info |
| `/healthz` | Liveness probe |
| `/ready` | Readiness probe |
| `/metrics` | Prometheus metrics |
