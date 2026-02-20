# ============================================================
# Makefile — Demo shortcuts (run inside WSL2)
# Usage: make <target>
# ============================================================

.PHONY: help up down status open-argocd open-grafana open-prometheus \
        nodes pods apps scale-down scale-up cost-alert

REGION     := ap-southeast-1
ENV        := dev
CLUSTER    := gitops-eks-demo-dev

## help — Show available commands
help:
	@echo ""
	@echo "GitOps EKS Demo — Available Commands"
	@echo "─────────────────────────────────────"
	@grep -E '^## ' Makefile | sed 's/## /  make /'
	@echo ""

## up — Deploy full demo (15 min)
up:
	@bash ci/scripts/demo-up.sh

## down — DESTROY everything and stop billing
down:
	@bash ci/scripts/demo-down.sh

## status — Show running resources and estimated cost
status:
	@bash ci/scripts/demo-status.sh

## open-argocd — Port-forward ArgoCD UI (open https://localhost:8080)
open-argocd:
	@echo "Opening ArgoCD → https://localhost:8080"
	@echo "Username: admin"
	@kubectl -n argocd get secret argocd-initial-admin-secret \
		-o jsonpath="{.data.password}" | base64 -d && echo " ← Password"
	@kubectl port-forward svc/argocd-server -n argocd 8080:443

## open-grafana — Port-forward Grafana (open http://localhost:3000)
open-grafana:
	@echo "Opening Grafana → http://localhost:3000 (admin/prom-operator)"
	@kubectl port-forward svc/prometheus-stack-grafana 3000:80 -n monitoring

## open-prometheus — Port-forward Prometheus UI
open-prometheus:
	@kubectl port-forward svc/prometheus-stack-prometheus 9090:9090 -n monitoring

## nodes — Show cluster nodes
nodes:
	@kubectl get nodes -o wide

## pods — Show all application pods
pods:
	@kubectl get pods -A -l 'app.kubernetes.io/name' --field-selector=status.phase=Running

## apps — Show ArgoCD applications
apps:
	@kubectl get applications -n argocd

## sync — Force sync all ArgoCD apps
sync:
	@argocd app sync --all --grpc-web 2>/dev/null || \
		kubectl annotate applications -n argocd --all argocd.argoproj.io/refresh=hard

## scale-down — Scale app nodes to 0 (saves ~60% cost when not testing)
scale-down:
	@echo "Scaling app node group to 0..."
	@aws eks update-nodegroup-config \
		--cluster-name $(CLUSTER) \
		--nodegroup-name $(CLUSTER)-application \
		--scaling-config minSize=0,maxSize=6,desiredSize=0 \
		--region $(REGION)
	@echo "Scaled down. System nodes still running (~\$$0.19/hr)"

## scale-up — Restore app nodes
scale-up:
	@echo "Scaling app node group back up..."
	@aws eks update-nodegroup-config \
		--cluster-name $(CLUSTER) \
		--nodegroup-name $(CLUSTER)-application \
		--scaling-config minSize=1,maxSize=6,desiredSize=2 \
		--region $(REGION)
	@echo "Scaling up — takes ~3 minutes"

## cost-alert — Set \$10 AWS budget alert (run once)
cost-alert:
	@ACCOUNT=$$(aws sts get-caller-identity --query Account --output text); \
	aws budgets create-budget \
		--account-id $$ACCOUNT \
		--budget '{"BudgetName":"gitops-eks-demo","BudgetLimit":{"Amount":"20","Unit":"USD"},"TimeUnit":"MONTHLY","BudgetType":"COST"}' \
		--notifications-with-subscribers '[{"Notification":{"NotificationType":"ACTUAL","ComparisonOperator":"GREATER_THAN","Threshold":10},"Subscribers":[{"SubscriptionType":"EMAIL","Address":"$(EMAIL)"}]}]' && \
	echo "Budget alert set for \$$10 → $(EMAIL)"

## install-tools — Install all required tools (WSL2/Ubuntu)
install-tools:
	@bash ci/scripts/install-tools-wsl.sh

## kubeconfig — Update kubectl config for the cluster
kubeconfig:
	@aws eks update-kubeconfig --region $(REGION) --name $(CLUSTER)
	@kubectl cluster-info

## tf-init — Initialise Terraform with correct backend (run once after extracting zip)
tf-init:
	@ACCOUNT=$$(aws sts get-caller-identity --query Account --output text); 	BUCKET="gitops-eks-demo-tfstate-$$ACCOUNT"; 	cd terraform/environments/dev && 	cat > backend.conf << EOF
bucket         = "$$BUCKET"
key            = "gitops-eks-demo/dev/terraform.tfstate"
region         = "$(REGION)"
encrypt        = true
dynamodb_table = "gitops-eks-demo-tfstate-lock"
EOF
	terraform init -backend-config=backend.conf -reconfigure
	@echo "Terraform initialised with bucket: gitops-eks-demo-tfstate-$$ACCOUNT"
