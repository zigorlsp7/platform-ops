variable "aws_region" {
  description = "AWS region for Terraform backend bucket."
  type        = string
}

variable "project" {
  description = "Project slug used in bucket naming."
  type        = string
  default     = "platform-ops"
}

variable "environment" {
  description = "Environment suffix for backend naming."
  type        = string
  default     = "prod"
}

variable "state_bucket_name" {
  description = "Optional fixed S3 bucket name. Leave empty to auto-generate."
  type        = string
  default     = ""
}

variable "tags" {
  description = "Extra tags for backend resources."
  type        = map(string)
  default     = {}
}
