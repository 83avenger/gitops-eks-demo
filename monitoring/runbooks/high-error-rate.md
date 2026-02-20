# Runbook: SampleAppHighErrorRate

## Alert
`SampleAppHighErrorRate` — HTTP 5xx error rate > 5% for 5 minutes.

## Impact
Users experiencing errors. SLO error budget burning.

## Diagnosis Steps

### 1. Check pod status
```bash
kubectl get pods -n sample-app-prod -l app.kubernetes.io/name=sample-app
kubectl describe pod <pod-name> -n sample-app-prod
```

### 2. Check recent error logs
```bash
kubectl logs -n sample-app-prod -l app.kubernetes.io/name=sample-app \
  --since=10m | grep -i error | tail -50
```

### 3. Check ArgoCD for recent deployments
```bash
argocd app history sample-app-prod
```

## Remediation

### Rollback a bad deployment
```bash
./ci/scripts/rollback.sh sample-app-prod
```

### Emergency kubectl rollback (last resort)
```bash
kubectl rollout undo deployment/sample-app -n sample-app-prod
kubectl rollout status deployment/sample-app -n sample-app-prod
```

## Post-Incident
- File blameless post-mortem within 48 hours
- Update runbook with new findings
