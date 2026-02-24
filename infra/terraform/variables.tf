variable "project" {
  type        = string
  description = "Project slug used for naming."
  default     = "platform-ops"
}

variable "environment" {
  type        = string
  description = "Environment name (dev/staging/prod)."
}

variable "aws_region" {
  type        = string
  description = "AWS region."
}

variable "vpc_cidr" {
  type        = string
  description = "VPC CIDR block."
  default     = "10.20.0.0/16"
}

variable "domain_name" {
  type        = string
  description = "Primary DNS name for the application."
}

variable "db_name" {
  type        = string
  description = "PostgreSQL database name."
  default     = "cv"
}

variable "db_username" {
  type        = string
  description = "PostgreSQL username."
  default     = "app"
}

variable "db_password" {
  type        = string
  description = "PostgreSQL password."
  sensitive   = true
}

variable "ecs_allowed_ingress_cidrs" {
  type        = list(string)
  description = "CIDR ranges allowed to reach ECS services."
  default     = ["10.20.0.0/16"]
}

variable "api_container_name" {
  type        = string
  description = "API container name in ECS task definition."
  default     = "api"
}

variable "web_container_name" {
  type        = string
  description = "Web container name in ECS task definition."
  default     = "web"
}

variable "api_container_port" {
  type        = number
  description = "API container port."
  default     = 3000
}

variable "web_container_port" {
  type        = number
  description = "Web container port."
  default     = 3001
}

variable "api_image_tag" {
  type        = string
  description = "Initial API image tag for ECS task definition."
  default     = "bootstrap"
}

variable "web_image_tag" {
  type        = string
  description = "Initial Web image tag for ECS task definition."
  default     = "bootstrap"
}

variable "ecs_desired_count" {
  type        = number
  description = "Desired ECS task count per service."
  default     = 1
}
