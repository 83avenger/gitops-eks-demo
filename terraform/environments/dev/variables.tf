variable "region" {
  type    = string
  default = "ap-southeast-1"
}

variable "project" {
  type    = string
  default = "gitops-eks-demo"
}

variable "owner" {
  type    = string
  default = "platform-team"
}

variable "base_domain" {
  type    = string
  default = "example.com"
}

variable "gitops_repo_url" {
  type    = string
  default = "https://github.com/your-org/gitops-eks-demo"
}
