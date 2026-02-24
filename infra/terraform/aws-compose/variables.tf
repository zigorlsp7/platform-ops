variable "project" {
  description = "Project slug used for naming."
  type        = string
  default     = "cv-web"
}

variable "environment" {
  description = "Environment name."
  type        = string
  default     = "prod"
}

variable "aws_region" {
  description = "AWS region where resources are created."
  type        = string
}

variable "ami_id" {
  description = "Optional custom AMI ID. Leave empty to use latest Amazon Linux 2023 x86_64."
  type        = string
  default     = ""
}

variable "instance_type" {
  description = "EC2 instance type for running the compose stacks."
  type        = string
  default     = "t3.large"
}

variable "root_volume_size_gb" {
  description = "Root EBS volume size in GiB."
  type        = number
  default     = 80
}

variable "deploy_base_dir" {
  description = "Directory on EC2 where deployment bundles are extracted."
  type        = string
  default     = "/opt/cv-web"
}

variable "key_name" {
  description = "Optional EC2 key pair name for SSH access."
  type        = string
  default     = ""
}

variable "enable_ssh" {
  description = "Whether to open inbound SSH (22/tcp)."
  type        = bool
  default     = false
}

variable "ssh_ingress_cidrs" {
  description = "CIDR ranges allowed to connect over SSH when enable_ssh=true."
  type        = list(string)
  default     = []

  validation {
    condition     = var.enable_ssh ? length(var.ssh_ingress_cidrs) > 0 : true
    error_message = "When enable_ssh=true, provide at least one CIDR in ssh_ingress_cidrs."
  }
}

variable "vpc_cidr" {
  description = "VPC CIDR block."
  type        = string
  default     = "10.50.0.0/16"
}

variable "public_subnet_cidr" {
  description = "Public subnet CIDR block."
  type        = string
  default     = "10.50.1.0/24"
}

variable "route53_zone_id" {
  description = "Route53 hosted zone ID where app/api records are created (only when create_route53_records=true)."
  type        = string
  default     = ""
}

variable "create_route53_records" {
  description = "Whether to create Route53 A records for app_domain and api_domain."
  type        = bool
  default     = true

  validation {
    condition     = var.create_route53_records ? var.route53_zone_id != "" : true
    error_message = "route53_zone_id is required when create_route53_records=true."
  }
}

variable "app_domain" {
  description = "Public web domain (used for Route53 output and app env)."
  type        = string
}

variable "api_domain" {
  description = "Public API domain (used for Route53 output and app env)."
  type        = string
}

variable "deploy_bucket_name" {
  description = "Optional pre-defined S3 bucket name for deploy bundles. Leave empty to auto-generate."
  type        = string
  default     = ""
}

variable "ecr_api_repository_name" {
  description = "Optional ECR repository name for API image."
  type        = string
  default     = ""
}

variable "ecr_web_repository_name" {
  description = "Optional ECR repository name for Web image."
  type        = string
  default     = ""
}

variable "ssm_app_parameter_prefix" {
  description = "SSM path prefix for app env values, e.g. /cv-web/prod/app."
  type        = string
  default     = "/cv-web/prod/app"

  validation {
    condition     = startswith(var.ssm_app_parameter_prefix, "/")
    error_message = "ssm_app_parameter_prefix must start with '/'."
  }
}

variable "ssm_ops_parameter_prefix" {
  description = "SSM path prefix for ops env values, e.g. /cv-web/prod/ops."
  type        = string
  default     = "/cv-web/prod/ops"

  validation {
    condition     = startswith(var.ssm_ops_parameter_prefix, "/")
    error_message = "ssm_ops_parameter_prefix must start with '/'."
  }
}

variable "create_github_oidc_provider" {
  description = "Whether Terraform should create the GitHub OIDC provider. Set false if it already exists in the account."
  type        = bool
  default     = false
}

variable "github_oidc_provider_arn" {
  description = "Existing GitHub OIDC provider ARN (required when create_github_oidc_provider=false)."
  type        = string
  default     = ""

  validation {
    condition     = var.create_github_oidc_provider ? true : var.github_oidc_provider_arn != ""
    error_message = "github_oidc_provider_arn is required when create_github_oidc_provider=false."
  }
}

variable "github_oidc_thumbprints" {
  description = "Thumbprints used when create_github_oidc_provider=true."
  type        = list(string)
  default     = ["6938fd4d98bab03faadb97b34396831e3780aea1"]
}

variable "github_repository" {
  description = "GitHub repository in ORG/REPO format allowed to assume the deploy role."
  type        = string
}

variable "github_environment" {
  description = "GitHub Environment name used by the deploy workflow trust policy."
  type        = string
  default     = "production"
}

variable "tags" {
  description = "Extra tags applied to resources."
  type        = map(string)
  default     = {}
}
