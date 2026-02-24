resource "random_id" "suffix" {
  byte_length = 3
}

locals {
  bucket_name = var.state_bucket_name != "" ? var.state_bucket_name : "${var.project}-${var.environment}-tfstate-${random_id.suffix.hex}"
  tags = merge(
    {
      Project     = var.project
      Environment = var.environment
      ManagedBy   = "terraform"
    },
    var.tags,
  )
}

resource "aws_s3_bucket" "tfstate" {
  bucket = local.bucket_name
  tags   = merge(local.tags, { Name = "${var.project}-${var.environment}-tfstate" })
}

resource "aws_s3_bucket_versioning" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}
