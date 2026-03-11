# Cloud First Deploy (platform-ops)

Use this runbook to deploy `platform-ops` to AWS for the first time.

## 0. Create Infra From Scratch (Terraform)

Use this once on a clean AWS account/environment to create the required infra.

```bash
set -euo pipefail

PROFILE="platform-ops"
REGION="eu-west-1"
BASE="/Users/zlz104107/zigor-dev/platform-ops/infra/terraform"
BOOT_DIR="$BASE/bootstrap"
AWS_DIR="$BASE/aws-compose"

aws sso login --profile "$PROFILE"
aws sts get-caller-identity --profile "$PROFILE" >/dev/null

export AWS_PROFILE="$PROFILE"
export AWS_REGION="$REGION"

# 1) Bootstrap (Terraform state bucket)
[ -f "$BOOT_DIR/environments/prod.tfvars" ] || cp "$BOOT_DIR/environments/prod.tfvars.example" "$BOOT_DIR/environments/prod.tfvars"
# edit environments/prod.tfvars before apply
terraform -chdir="$BOOT_DIR" init
terraform -chdir="$BOOT_DIR" apply -var-file=environments/prod.tfvars -auto-approve

# 2) Main infra (VPC, EC2, ECR, S3 deploy bucket, IAM roles)
[ -f "$AWS_DIR/environments/prod.tfvars" ] || cp "$AWS_DIR/environments/prod.tfvars.example" "$AWS_DIR/environments/prod.tfvars"
# edit environments/prod.tfvars before apply
terraform -chdir="$AWS_DIR" init
terraform -chdir="$AWS_DIR" apply -var-file=environments/prod.tfvars -auto-approve

# 3) Outputs needed for GitHub production environments
terraform -chdir="$AWS_DIR" output -json github_actions_variables | jq .
terraform -chdir="$AWS_DIR" output github_deploy_role_arn
terraform -chdir="$AWS_DIR" output -json cv_github_actions_variables | jq .
terraform -chdir="$AWS_DIR" output cv_github_deploy_role_arn
terraform -chdir="$AWS_DIR" output -json gpool_github_actions_variables | jq .
terraform -chdir="$AWS_DIR" output gpool_github_deploy_role_arn
```

## 1. AWS Prerequisites

- AWS account access through profile `platform-ops`.
- AWS CLI configured with SSO for that profile.
- Terraform installed locally.
- `environments/prod.tfvars` completed for:
  - `infra/terraform/bootstrap`
  - `infra/terraform/aws-compose`

## 2. GitHub `production` Environment Configuration

In the `platform-ops` GitHub repository, create/update environment `production`.

Required environment variables:

- `AWS_REGION`
- `AWS_DEPLOY_BUCKET`
- `AWS_DEPLOY_INSTANCE_ID`
- `AWS_SSM_OPS_PREFIX` (example: `/platform-ops/prod/ops`)

Required environment secrets:

- `AWS_DEPLOY_ROLE_ARN`

## 3. Create Required SSM SecureString Parameters

Create these SecureString parameters under `AWS_SSM_OPS_PREFIX`:

- `GRAFANA_ADMIN_PASSWORD`
- `TOLGEE_INITIAL_PASSWORD`
- `TOLGEE_JWT_SECRET`

Example (replace values and region):

```bash
aws ssm put-parameter --profile platform-ops --name /platform-ops/prod/ops/GRAFANA_ADMIN_PASSWORD --type SecureString --value 'change-me' --overwrite --region eu-west-1
aws ssm put-parameter --profile platform-ops --name /platform-ops/prod/ops/TOLGEE_INITIAL_PASSWORD --type SecureString --value 'change-me' --overwrite --region eu-west-1
aws ssm put-parameter --profile platform-ops --name /platform-ops/prod/ops/TOLGEE_JWT_SECRET --type SecureString --value 'change-me' --overwrite --region eu-west-1
```

Generate a strong Tolgee JWT secret:

```bash
openssl rand -hex 32
```

Note:

- `GRAFANA_ADMIN_USER` and `TOLGEE_INITIAL_USERNAME` are non-secret values and come from tracked file `docker/.env.ops.prod`.

## 4. Trigger First Ops Deploy

Workflow:

- `Deploy AWS Ops (EC2 Compose)` (`.github/workflows/deploy-ops.yml`)

Recommended first run:

1. Open GitHub Actions in `platform-ops`.
2. Run workflow manually (`workflow_dispatch`).
3. Set `ref=main`.
4. Optional `release_tag` (if empty, workflow generates one).

## 5. Initialize OpenBao on Prod (First Time Only)

`cv` and `gpool` deploys require OpenBao to be initialized, unsealed, and `kv` enabled.

Do this directly in the OpenBao UI (same approach as local):

1. Open OpenBao UI.
2. Initialize with:
- `Key shares = 1`
- `Key threshold = 1`
3. Save:
- `Unseal Key 1`
- `Initial Root Token`
4. Unseal using `Unseal Key 1`.
5. Log in with token auth using `Initial Root Token`.
6. Ensure `kv` (v2) is enabled at path `kv`.

If `kv` is already present, keep it as-is.

## 6. Validate Ops Stack

From the instance:

```bash
curl -sS http://127.0.0.1:8200/v1/sys/health
curl -fsS http://127.0.0.1:3000/api/health
curl -fsS http://127.0.0.1:8080/healthz || curl -fsS http://127.0.0.1:8080/api/healthz
```

## 7. Next Step

After this is complete, deploy apps using:

- `cv/docs/cloud-first-deploy.md`
- `gpool/docs/cloud-first-deploy.md`
