variable "cluster_name" {
  type = string
}

variable "region" {
  type = string
}

variable "ebs_csi_role_arn" {
  type = string
}

variable "aws_lb_controller_role_arn" {
  type = string
}

variable "cluster_autoscaler_role_arn" {
  type = string
}

variable "external_secrets_role_arn" {
  type = string
}

variable "argocd_hostname" {
  type    = string
  default = "argocd.example.com"
}

variable "gitops_repo_url" {
  type = string
}

variable "tags" {
  type    = map(string)
  default = {}
}

variable "node_group_ids" {
  description = "Node group IDs to wait for before installing addons"
  type        = list(string)
  default     = []
}

variable "vpc_id" {
  description = "VPC ID — required by ALB controller to discover subnets"
  type        = string
}
