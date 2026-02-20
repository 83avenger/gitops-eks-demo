################################################################################
# EKS Addons Module
################################################################################

# vpc-cni MUST be installed before any pod can get a network interface.
# Using resolve_conflicts = OVERWRITE and NO addon_version so AWS picks the
# correct default for the cluster version — avoids the CREATE timeout that
# occurs when specifying an incompatible or already-managed version.
resource "aws_eks_addon" "vpc_cni" {
  cluster_name             = var.cluster_name
  addon_name               = "vpc-cni"
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"
  tags                     = var.tags

  timeouts {
    create = "30m"
  }
}

resource "time_sleep" "wait_for_cluster_ready" {
  depends_on      = [aws_eks_addon.vpc_cni]
  create_duration = "30s"
}

################################################################################
# WAVE 1 — AWS Load Balancer Controller
################################################################################

resource "helm_release" "aws_load_balancer_controller" {
  name       = "aws-load-balancer-controller"
  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-load-balancer-controller"
  version    = "1.8.1"
  namespace  = "kube-system"
  wait       = true
  timeout    = 600

  values = [
    templatefile("${path.module}/values/aws-lb-controller.yaml", {
      cluster_name = var.cluster_name
      role_arn     = var.aws_lb_controller_role_arn
      vpc_id       = var.vpc_id
      region       = var.region
    })
  ]

  depends_on = [time_sleep.wait_for_cluster_ready]
}

resource "time_sleep" "wait_for_alb_webhook" {
  depends_on      = [helm_release.aws_load_balancer_controller]
  create_duration = "30s"
}

################################################################################
# WAVE 2 — Platform components (parallel)
################################################################################

resource "helm_release" "metrics_server" {
  name       = "metrics-server"
  repository = "https://kubernetes-sigs.github.io/metrics-server/"
  chart      = "metrics-server"
  version    = "3.12.1"
  namespace  = "kube-system"
  wait       = true
  timeout    = 300

  set {
    name  = "replicas"
    value = "2"
  }

  depends_on = [time_sleep.wait_for_alb_webhook]
}

resource "helm_release" "cluster_autoscaler" {
  name       = "cluster-autoscaler"
  repository = "https://kubernetes.github.io/autoscaler"
  chart      = "cluster-autoscaler"
  version    = "9.37.0"
  namespace  = "kube-system"
  wait       = true
  timeout    = 300

  values = [
    templatefile("${path.module}/values/cluster-autoscaler.yaml", {
      cluster_name = var.cluster_name
      region       = var.region
      role_arn     = var.cluster_autoscaler_role_arn
    })
  ]

  depends_on = [time_sleep.wait_for_alb_webhook]
}

resource "helm_release" "external_secrets" {
  name             = "external-secrets"
  repository       = "https://charts.external-secrets.io"
  chart            = "external-secrets"
  version          = "0.10.0"
  namespace        = "external-secrets"
  create_namespace = true
  wait             = true
  timeout          = 300

  values = [
    templatefile("${path.module}/values/external-secrets.yaml", {
      role_arn = var.external_secrets_role_arn
    })
  ]

  depends_on = [time_sleep.wait_for_alb_webhook]
}

resource "helm_release" "ebs_csi_driver" {
  name       = "aws-ebs-csi-driver"
  repository = "https://kubernetes-sigs.github.io/aws-ebs-csi-driver"
  chart      = "aws-ebs-csi-driver"
  version    = "2.32.0"
  namespace  = "kube-system"
  wait       = true
  timeout    = 300

  values = [
    templatefile("${path.module}/values/ebs-csi-driver.yaml", {
      role_arn = var.ebs_csi_role_arn
    })
  ]

  depends_on = [time_sleep.wait_for_alb_webhook]
}

resource "helm_release" "gatekeeper" {
  name             = "gatekeeper"
  repository       = "https://open-policy-agent.github.io/gatekeeper/charts"
  chart            = "gatekeeper"
  version          = "3.17.0"
  namespace        = "gatekeeper-system"
  create_namespace = true
  wait             = true
  timeout          = 300

  set {
    name  = "replicas"
    value = "2"
  }

  set {
    name  = "auditInterval"
    value = "30"
  }

  depends_on = [time_sleep.wait_for_alb_webhook]
}

resource "helm_release" "keda" {
  name             = "keda"
  repository       = "https://kedacore.github.io/charts"
  chart            = "keda"
  version          = "2.14.2"
  namespace        = "keda"
  create_namespace = true
  wait             = true
  timeout          = 300

  depends_on = [time_sleep.wait_for_alb_webhook]
}

################################################################################
# WAVE 3 — ArgoCD
################################################################################

resource "helm_release" "argocd" {
  name             = "argocd"
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-cd"
  version          = "7.3.11"
  namespace        = "argocd"
  create_namespace = true
  wait             = true
  timeout          = 600

  set {
    name  = "server.replicas"
    value = "2"
  }

  set {
    name  = "repoServer.replicas"
    value = "2"
  }

  set {
    name  = "applicationSet.replicas"
    value = "2"
  }

  set {
    name  = "redis-ha.enabled"
    value = "true"
  }

  set {
    name  = "configs.params.server.insecure"
    value = "true"
  }

  depends_on = [
    helm_release.metrics_server,
    helm_release.external_secrets,
    time_sleep.wait_for_alb_webhook,
  ]
}
