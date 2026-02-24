output "instance_id" {
  description = "EC2 instance ID hosting app+ops compose stacks."
  value       = aws_instance.app.id
}

output "instance_public_ip" {
  description = "Elastic IP attached to the EC2 instance."
  value       = aws_eip.app.public_ip
}

output "deploy_bucket_name" {
  description = "S3 bucket used by CI to upload release bundles."
  value       = aws_s3_bucket.deploy.id
}

output "api_ecr_repository_url" {
  description = "ECR repository URI for the API image."
  value       = aws_ecr_repository.api.repository_url
}

output "web_ecr_repository_url" {
  description = "ECR repository URI for the Web image."
  value       = aws_ecr_repository.web.repository_url
}

output "github_deploy_role_arn" {
  description = "IAM role ARN to configure in GitHub Actions for OIDC deploy."
  value       = aws_iam_role.github_deploy.arn
}

output "ssm_ops_parameter_prefix" {
  description = "SSM prefix expected by deploy script for ops env values."
  value       = var.ssm_ops_parameter_prefix
}

output "github_actions_variables" {
  description = "Copy these values into GitHub Environment variables (production)."
  value = {
    AWS_REGION                 = var.aws_region
    AWS_DEPLOY_BUCKET          = aws_s3_bucket.deploy.id
    AWS_DEPLOY_INSTANCE_ID     = aws_instance.app.id
    AWS_ECR_API_REPOSITORY_URI = aws_ecr_repository.api.repository_url
    AWS_ECR_WEB_REPOSITORY_URI = aws_ecr_repository.web.repository_url
    AWS_SSM_OPS_PREFIX         = var.ssm_ops_parameter_prefix
  }
}
