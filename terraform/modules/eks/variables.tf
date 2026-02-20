variable "cluster_name" {
  type = string
}

variable "kubernetes_version" {
  type    = string
  default = "1.30"
}

variable "vpc_id" {
  type = string
}

variable "public_subnet_ids" {
  type = list(string)
}

variable "private_subnet_ids" {
  type = list(string)
}

variable "environment" {
  type = string
}

variable "endpoint_public_access" {
  type    = bool
  default = true
}

variable "public_access_cidrs" {
  type    = list(string)
  default = ["0.0.0.0/0"]
}

variable "system_node_instance_types" {
  type    = list(string)
  default = ["m5.large"]
}

variable "system_node_desired" {
  type    = number
  default = 2
}

variable "system_node_min" {
  type    = number
  default = 2
}

variable "system_node_max" {
  type    = number
  default = 4
}

variable "app_node_instance_types" {
  type    = list(string)
  default = ["m5.xlarge"]
}

variable "app_node_desired" {
  type    = number
  default = 2
}

variable "app_node_min" {
  type    = number
  default = 1
}

variable "app_node_max" {
  type    = number
  default = 10
}

variable "app_node_capacity_type" {
  type    = string
  default = "ON_DEMAND"
}

variable "irsa_roles" {
  type = map(object({
    namespace       = string
    service_account = string
  }))
  default = {
    "aws-load-balancer-controller" = {
      namespace       = "kube-system"
      service_account = "aws-load-balancer-controller"
    }
    "cluster-autoscaler" = {
      namespace       = "kube-system"
      service_account = "cluster-autoscaler"
    }
    "external-secrets" = {
      namespace       = "external-secrets"
      service_account = "external-secrets-sa"
    }
  }
}

variable "tags" {
  type    = map(string)
  default = {}
}
