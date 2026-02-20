################################################################################
# Dev Environment — EKS GitOps Platform
################################################################################

terraform {
  required_version = ">= 1.8.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.13"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.30"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
    time = {
      source  = "hashicorp/time"
      version = "~> 0.11"
    }
  }

  # Backend configured dynamically by demo-up.sh using -backend-config flag.
  # Do NOT hardcode credentials here. Run: bash ci/scripts/demo-up.sh
  backend "s3" {}
}

provider "aws" {
  region = var.region

  default_tags {
    tags = local.common_tags
  }
}

provider "helm" {
  kubernetes {
    host                   = module.eks.cluster_endpoint
    cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
    exec {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      args        = ["eks", "get-token", "--cluster-name", module.eks.cluster_name, "--region", var.region]
    }
  }
}

provider "kubernetes" {
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args        = ["eks", "get-token", "--cluster-name", module.eks.cluster_name, "--region", var.region]
  }
}

locals {
  environment  = "dev"
  cluster_name = "${var.project}-${local.environment}"

  common_tags = {
    Project     = var.project
    Environment = local.environment
    ManagedBy   = "terraform"
    Owner       = var.owner
  }
}

################################################################################
# Networking
################################################################################

module "vpc" {
  source = "../../modules/vpc"

  name         = local.cluster_name
  cluster_name = local.cluster_name
  vpc_cidr     = "10.10.0.0/16"
  az_count     = 3
  enable_flow_logs = true
  tags         = local.common_tags
}

################################################################################
# EKS Cluster
################################################################################

module "eks" {
  source = "../../modules/eks"

  cluster_name           = local.cluster_name
  kubernetes_version     = "1.30"
  vpc_id                 = module.vpc.vpc_id
  public_subnet_ids      = module.vpc.public_subnet_ids
  private_subnet_ids     = module.vpc.private_subnet_ids
  environment            = local.environment
  endpoint_public_access = true
  public_access_cidrs    = ["0.0.0.0/0"]  # Restrict to VPN CIDR in prod

  # Dev: smaller, spot instances to save cost
  system_node_instance_types = ["m5.large"]
  system_node_desired        = 2
  system_node_min            = 2
  system_node_max            = 4

  app_node_instance_types  = ["m5.xlarge", "m5a.xlarge"]
  app_node_desired         = 2
  app_node_min             = 1
  app_node_max             = 6
  app_node_capacity_type   = "SPOT"  # Use spot for dev cost savings

  tags = local.common_tags
}

################################################################################
# Wait for node groups to fully join the cluster before installing addons
# Prevents vpc-cni/coredns timeout errors
################################################################################

resource "time_sleep" "wait_for_nodes" {
  depends_on      = [module.eks]
  create_duration = "60s"
}

################################################################################
# Platform Addons
################################################################################

module "addons" {
  source = "../../modules/addons"

  cluster_name                = module.eks.cluster_name
  region                      = var.region
  ebs_csi_role_arn            = module.eks.node_group_role_arn
  aws_lb_controller_role_arn  = module.eks.aws_lb_controller_role_arn
  cluster_autoscaler_role_arn = module.eks.cluster_autoscaler_role_arn
  external_secrets_role_arn   = module.eks.external_secrets_role_arn
  argocd_hostname             = "argocd.dev.${var.base_domain}"
  vpc_id                      = module.vpc.vpc_id
  gitops_repo_url             = var.gitops_repo_url
  tags                        = local.common_tags

  depends_on = [module.eks, time_sleep.wait_for_nodes]
}
