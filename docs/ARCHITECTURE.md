# Architecture Decision Record — GitOps on EKS

## Decision Summary

| Area | Decision | Alternatives Considered |
|---|---|---|
| GitOps Engine | ArgoCD | Flux v2, Spinnaker |
| IaC | Terraform | Pulumi, AWS CDK |
| Config Management | Kustomize | Helm, Jsonnet |
| Secret Management | External Secrets + AWS SM | Sealed Secrets, Vault |
| Ingress | AWS LBC + ALB | NGINX Ingress, Traefik |
| Monitoring | kube-prometheus-stack | Datadog, New Relic |
| Logging | Loki + Promtail | EFK (Elasticsearch + Fluentd) |
| Policy Enforcement | OPA Gatekeeper | Kyverno |
| Image Registry | Amazon ECR | Docker Hub, Harbor |

## Key Architectural Decisions

### 1. App of Apps Pattern (ArgoCD)
**Why**: Single entry point for all applications. Adding a new app means adding one YAML file and committing. No manual ArgoCD CLI needed. ArgoCD manages ArgoCD applications declaratively.

**Trade-off**: Slightly more complex initial setup. Worth it at scale.

### 2. Kustomize over Helm for Applications
**Why**: Applications are owned by us — we control the manifests. Kustomize patches are explicit and auditable. No templating language to learn.

**When to use Helm**: Third-party platform components (ArgoCD, Prometheus, cert-manager) where we're consuming upstream charts.

### 3. IRSA over Node IAM Roles
**Why**: Least-privilege per workload. A compromised pod cannot access AWS resources beyond its service account's permissions. Meets CIS EKS Benchmark.

### 4. Separate Terraform State per Environment
**Why**: Blast radius isolation. A `terraform destroy` in dev cannot affect prod state. Also enables different AWS accounts per environment (recommended for prod).

### 5. Private Node Groups + NAT Gateway
**Why**: Worker nodes have no public IPs. Inbound traffic only via load balancers. Follows AWS security best practices and is required for most enterprise/government compliance frameworks.

### 6. Sync Waves for Deployment Ordering
**Why**: Cert-manager must exist before anything that needs TLS certificates. External Secrets must exist before apps that reference secrets. Wave numbers encode this dependency without tight coupling.

## Security Posture

This platform implements defense-in-depth across multiple layers:

1. **Network Layer**: Private subnets, security groups, NetworkPolicies (default-deny)
2. **Identity Layer**: IRSA, OIDC, no static credentials, no node-level IAM
3. **Secrets Layer**: External Secrets — secrets never touch Git or etcd unencrypted
4. **Admission Control**: OPA Gatekeeper — org policies enforced at admission
5. **Runtime Layer**: Read-only root filesystem, non-root containers, seccompProfile
6. **Supply Chain**: Image scanning in CI (Trivy), SAST (Semgrep), IaC scanning (Checkov)
7. **Audit Layer**: EKS control plane logs, VPC Flow Logs, CloudTrail

## Runbook Index

| Scenario | Runbook |
|---|---|
| Pod crash loop | docs/runbooks/pod-crash-loop.md |
| ArgoCD out of sync | docs/runbooks/argocd-sync.md |
| High memory pressure | docs/runbooks/node-memory.md |
| Certificate expiry | docs/runbooks/certificate-renewal.md |
| Secret rotation | docs/runbooks/secret-rotation.md |

## Cost Estimates (Monthly, USD)

| Environment | EKS Control | Nodes | NAT GW | Data Transfer | Est. Total |
|---|---|---|---|---|---|
| Dev | $73 | ~$60 (2x t3.med) | $32 (1x) | ~$10 | **~$175** |
| Staging | $73 | ~$180 (3x t3.lg) | $96 (3x) | ~$20 | **~$370** |
| Prod | $73 | ~$600+ (3x m5.xl + spot) | $96 (3x) | ~$50 | **~$820+** |

*Significant savings available via Karpenter (consolidation) and Reserved Instances.*
