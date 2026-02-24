# Platform Ops Deployment Guide (Terraform + GitHub Actions)

This guide is intentionally scoped to `platform-ops` only.

It covers:

1. Terraform infrastructure provisioning.
2. SSM configuration for ops runtime env.
3. GitHub Actions setup for production ops deployment.

For day-to-day local/prod execution steps, use `docs/ops-runbook.md`.

## 1. What Terraform stack provisions

Stack: `infra/terraform/aws-compose`

1. VPC + subnet + internet gateway.
2. Security group (80/443 public, optional SSH).
3. EC2 host for compose-based runtime.
4. Elastic IP.
5. ECR repositories (optional, for app pipelines that share this infra).
6. S3 deploy bundle bucket.
7. IAM role for EC2 runtime.
8. IAM role for GitHub OIDC deploy.

Per-application DNS hostnames are managed outside this shared module.

## 2. Prerequisites

1. Terraform >= 1.6.
2. AWS CLI v2.
3. `jq`.
4. AWS account permissions for IAM/VPC/EC2/ECR/S3/SSM.
5. GitHub admin access for `platform-ops` repository settings.

## 3. Backend bootstrap (one-time)

```bash
cd infra/terraform/bootstrap
cp environments/prod.tfvars.example environments/prod.tfvars
# edit values
terraform init
terraform plan -var-file=environments/prod.tfvars
terraform apply -var-file=environments/prod.tfvars
terraform output backend_config_snippet
```

Apply backend snippet to `infra/terraform/aws-compose/versions.tf`, then:

```bash
cd ../aws-compose
terraform init -reconfigure
```

## 4. Provision infrastructure

```bash
cp environments/prod.tfvars.example environments/prod.tfvars
# edit environments/prod.tfvars
terraform plan -var-file=environments/prod.tfvars
terraform apply -var-file=environments/prod.tfvars
```

Capture outputs:

```bash
terraform output
terraform output github_deploy_role_arn
terraform output -json github_actions_variables
```

## 5. Configure GitHub Environment (`production`)

In repository `platform-ops`:

1. Settings -> Environments -> `production`.
2. Add secret:
- `AWS_DEPLOY_ROLE_ARN` (`terraform output github_deploy_role_arn`).
3. Add variables from `terraform output -json github_actions_variables`:
- `AWS_REGION`
- `AWS_DEPLOY_BUCKET`
- `AWS_DEPLOY_INSTANCE_ID`
- `AWS_SSM_OPS_PREFIX`

## 6. Configure production ops env values in SSM

Template file: `docker/.env.ops.prod`

Upload:

```bash
./scripts/aws-ssm-sync-env.sh \
  --file docker/.env.ops.prod \
  --prefix /platform-ops/prod/ops \
  --region <your-region> \
  --secure-keys GRAFANA_ADMIN_PASSWORD
```

## 7. Deploy ops stack via GitHub Actions

Workflow: `.github/workflows/deploy-ops.yml`

Manual trigger inputs:

1. `ref` (usually `main`).
2. Optional `release_tag`.

The workflow will:

1. Package repository bundle.
2. Upload to S3.
3. Execute remote deploy through SSM.

## 8. Post-deploy verification

1. Confirm workflow final status is success.
2. From SSM session on target host:

```bash
cd /opt/platform-ops/releases/<release-tag>
docker compose --env-file docker/.env.ops.prod -f docker/compose.ops.prod.yml ps
```

3. Validate endpoints using the checks in `docs/ops-runbook.md`.
