#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────
# helm-debug.sh — Diagnose a failed Helm release
# Usage: bash ci/scripts/helm-debug.sh <release-name> [namespace]
# ─────────────────────────────────────────────────────────────
set -euo pipefail
RELEASE="${1:-aws-load-balancer-controller}"
NAMESPACE="${2:-kube-system}"

echo "=== Helm status ==="
helm status "$RELEASE" -n "$NAMESPACE" 2>/dev/null || echo "(release not found)"

echo ""
echo "=== Helm history ==="
helm history "$RELEASE" -n "$NAMESPACE" 2>/dev/null || echo "(no history)"

echo ""
echo "=== Pods in $NAMESPACE ==="
kubectl get pods -n "$NAMESPACE" | grep -i "$RELEASE" || echo "(no pods found)"

echo ""
echo "=== Pod events (last 20) ==="
kubectl get events -n "$NAMESPACE" --sort-by='.lastTimestamp' \
  | tail -20

echo ""
echo "=== Pod logs ==="
POD=$(kubectl get pods -n "$NAMESPACE" -l "app.kubernetes.io/name=$RELEASE" \
  -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
if [ -n "$POD" ]; then
  kubectl logs "$POD" -n "$NAMESPACE" --tail=50
else
  echo "(no pod found for $RELEASE)"
fi

echo ""
echo "=== To clean up and retry: ==="
echo "  helm uninstall $RELEASE -n $NAMESPACE"
echo "  terraform -chdir=terraform/environments/dev apply"
