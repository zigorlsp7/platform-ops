# AWS EC2 + Compose Production Stack (Recommended for this repo)

This Terraform stack provisions the minimum AWS infrastructure to deploy the current split compose setup:

- `docker/compose.app.prod.yml`
- `docker/compose.ops.prod.yml`

It uses:

- 1 EC2 instance (app + ops on same host)
- 1 Elastic IP
- VPC + public subnet + security group
- ECR repos for API/Web images
- S3 deploy bundle bucket
- IAM role for EC2 runtime
- IAM role for GitHub Actions OIDC deploy
- Optional Route53 records (`app`, `api`)

DNS can be handled in two ways:

1. Route53 authoritative:
- Set `create_route53_records=true` and provide `route53_zone_id`.
2. Cloudflare (or any external DNS) authoritative:
- Set `create_route53_records=false`.
- After apply, create external `A` records (`app`, `api`) pointing to `terraform output instance_public_ip`.

## Directory

- `versions.tf` providers/versions
- `variables.tf` inputs
- `main.tf` resources
- `outputs.tf` values to wire into GitHub
- `templates/user-data.sh.tftpl` EC2 bootstrap
- `environments/prod.tfvars.example` starter values
- `environments/prod.route53.tfvars.example` Route53-focused example
- `environments/prod.cloudflare.tfvars.example` Cloudflare-focused example

## 1. Initialize Terraform

```bash
cd infra/terraform/aws-compose
terraform init
```

## 2. Plan

```bash
cp environments/prod.tfvars.example environments/prod.tfvars
# edit environments/prod.tfvars
terraform plan -var-file=environments/prod.tfvars
```

## 3. Apply

```bash
terraform apply -var-file=environments/prod.tfvars
```

## 4. Capture outputs

```bash
terraform output
terraform output -json github_actions_variables
terraform output github_deploy_role_arn
```

Use those outputs to configure GitHub Environment `production` variables/secrets.

## 5. What Terraform does not do

- It does **not** create your OpenBao secrets.
- It does **not** populate SSM env parameters.
- It does **not** unseal OpenBao after reboot.

Use:

- `scripts/aws-ssm-sync-env.sh`
- `scripts/prod-deploy-remote.sh`
- `docs/deploy-aws-terraform.md`

for operational setup and release automation.
