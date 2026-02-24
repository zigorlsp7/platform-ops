output "state_bucket_name" {
  description = "S3 bucket name for Terraform state backend."
  value       = aws_s3_bucket.tfstate.id
}

output "backend_config_snippet" {
  description = "Paste this backend block in your environment stack."
  value = <<EOT
terraform {
  backend "s3" {
    bucket       = "${aws_s3_bucket.tfstate.id}"
    key          = "aws-compose/prod/terraform.tfstate"
    region       = "${var.aws_region}"
    use_lockfile = true
  }
}
EOT
}
