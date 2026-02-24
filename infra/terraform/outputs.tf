output "vpc_id" {
  value = aws_vpc.main.id
}

output "ecs_cluster_name" {
  value = aws_ecs_cluster.main.name
}

output "ecs_api_service_name" {
  value = aws_ecs_service.api.name
}

output "ecs_web_service_name" {
  value = aws_ecs_service.web.name
}

output "api_ecr_repository_url" {
  value = aws_ecr_repository.api.repository_url
}

output "web_ecr_repository_url" {
  value = aws_ecr_repository.web.repository_url
}

output "rds_endpoint" {
  value = aws_db_instance.postgres.address
}

output "db_secret_arn" {
  value = aws_secretsmanager_secret.db_credentials.arn
}
