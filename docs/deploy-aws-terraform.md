# AWS Production Deployment Guide (Terraform + GitHub Releases)

This guide matches the current architecture in this repo:

- App stack: `docker/compose.app.prod.yml`
- Ops stack: `docker/compose.ops.prod.yml`
- Runtime secret fetch: OpenBao (`scripts/openbao-run.mjs`)

It is designed for first-time setup and automated deployment after each GitHub Release.

Before editing env values, read `docs/env-management.md` for source-of-truth rules.

## 1. What Terraform provisions

Stack: `infra/terraform/aws-compose`

1. VPC + public subnet + internet gateway
2. Security group (80/443 public, optional SSH)
3. One EC2 host for app + ops compose
4. Elastic IP
5. ECR repos (api/web)
6. S3 deploy bundle bucket
7. IAM role for EC2 runtime (ECR pull, S3 read, SSM read)
8. IAM role for GitHub OIDC deploy (ECR push, S3 upload, SSM RunCommand)
9. Optional Route53 A records (`app`, `api`)

## 2. Prerequisites

Local tools:

1. Terraform >= 1.6
2. AWS CLI v2
3. `jq`

Accounts/access:

1. AWS account with IAM/VPC/EC2/ECR/S3 permissions
2. GitHub repo admin access (to configure environment vars/secrets)
3. Your DNS zone is either:
- Route53 authoritative, or
- Cloudflare (or another DNS provider) authoritative

## 3. Choose DNS mode before `terraform apply`

## Option A: Route53 authoritative DNS

Use when your domain is delegated to Route53 nameservers.

In tfvars:

```hcl
create_route53_records = true
route53_zone_id        = "Z..."
```

## Option B: Cloudflare authoritative DNS

Use when `dig NS yourdomain.com` returns Cloudflare nameservers.

In tfvars:

```hcl
create_route53_records = false
route53_zone_id        = ""
```

After Terraform apply, you will create DNS records in Cloudflare UI pointing to EC2 Elastic IP.

## 4. One-time Terraform backend bootstrap (state bucket)

```bash
cd infra/terraform/bootstrap
cp environments/prod.tfvars.example environments/prod.tfvars
# edit prod.tfvars
terraform init
terraform plan -var-file=environments/prod.tfvars
terraform apply -var-file=environments/prod.tfvars
terraform output backend_config_snippet
```

Copy the backend snippet into `infra/terraform/aws-compose/versions.tf`, then run:

```bash
cd ../aws-compose
terraform init -reconfigure
```

## 5. Provision AWS infrastructure

Use one of the ready examples:

1. Route53 mode:

```bash
cp environments/prod.route53.tfvars.example environments/prod.tfvars
```

2. Cloudflare mode:

```bash
cp environments/prod.cloudflare.tfvars.example environments/prod.tfvars
```

Edit `environments/prod.tfvars`, then apply:

```bash
terraform plan -var-file=environments/prod.tfvars
terraform apply -var-file=environments/prod.tfvars
```

Capture outputs:

```bash
terraform output
terraform output github_deploy_role_arn
terraform output -json github_actions_variables
terraform output instance_public_ip
```

## 6. Configure DNS records

## If using Route53 mode

Terraform created `app` and `api` A records already. Verify:

```bash
dig app.your-domain.com +short
dig api.your-domain.com +short
```

## If using Cloudflare mode

Create records manually in Cloudflare:

1. Cloudflare -> your zone -> `DNS` -> `Records` -> `Add record`
2. Add `A` record:
- Name: `app`
- IPv4: `<terraform output instance_public_ip>`
- Proxy status: `DNS only` (recommended for first deploy)
3. Add `A` record:
- Name: `api`
- IPv4: `<terraform output instance_public_ip>`
- Proxy status: `DNS only`

Verify:

```bash
dig app.your-domain.com +short
dig api.your-domain.com +short
```

## 7. Configure GitHub Environment (`production`)

Workflow: `.github/workflows/deploy.yml`

It runs on:

1. `release.published`
2. manual `workflow_dispatch`

Use Release Please tags (`vX.Y.Z`) for releases.
Do not create manual `cv-web-vX.Y.Z` tags for deployment, because they conflict with Release Please tag history.

Create environment:

1. Repo -> `Settings` -> `Environments`
2. Add environment `production`
3. Add required reviewers (recommended)

Add secret:

1. `AWS_DEPLOY_ROLE_ARN` = `terraform output github_deploy_role_arn`

Add variables from `terraform output -json github_actions_variables`:

1. `AWS_REGION`
2. `AWS_DEPLOY_BUCKET`
3. `AWS_DEPLOY_INSTANCE_ID`
4. `AWS_ECR_API_REPOSITORY_URI`
5. `AWS_ECR_WEB_REPOSITORY_URI`
6. `AWS_SSM_APP_PREFIX`
7. `AWS_SSM_OPS_PREFIX`
8. `DEPLOY_HEALTHCHECK_URL`

Also add these manual GitHub environment variables (used at web image build time):

1. `NEXT_PUBLIC_API_BASE_URL` (example `https://api.your-domain.com`)
2. `NEXT_PUBLIC_RUM_ENABLED` (`true` or `false`)
3. `NEXT_PUBLIC_RUM_ENDPOINT` (optional, example `https://api.your-domain.com/v1/rum/events`)

## 8. Put production env values into SSM Parameter Store

The deploy script renders these on the EC2 host at runtime:

1. `docker/.env.app.prod`
2. `docker/.env.ops.prod`

Treat repo `docker/.env.*.prod` files as templates and keep production source-of-truth in SSM/OpenBao.
Use `npm run env:doctor -- --mode prod` before syncing to SSM.

Minimal `docker/.env.app.prod` keys:

1. `WEB_DOMAIN`
2. `API_DOMAIN`
3. `NEXT_PUBLIC_API_BASE_URL`
4. `NEXT_PUBLIC_RUM_ENDPOINT`
5. `CORS_ORIGINS`
6. `DB_HOST=postgres`
7. `DB_PORT=5432`
8. `DB_USER`
9. `DB_PASSWORD`
10. `DB_NAME`
11. `POSTGRES_USER`
12. `POSTGRES_PASSWORD`
13. `POSTGRES_DB`
14. `OPENBAO_ADDR=http://openbao:8200`
15. `OPENBAO_TOKEN` (read-only app token)
16. `OPENBAO_KV_MOUNT`
17. `OPENBAO_SECRET_PATH`
18. `CV_SHARED_NETWORK=cv_shared`

Canonical values:

1. `OPENBAO_KV_MOUNT=kv`
2. `OPENBAO_SECRET_PATH=cv-web/app`

Minimal `docker/.env.ops.prod` keys:

1. `CV_SHARED_NETWORK=cv_shared`
2. `GRAFANA_ADMIN_USER`
3. `GRAFANA_ADMIN_PASSWORD`

Upload to SSM:

```bash
./scripts/aws-ssm-sync-env.sh \
  --file docker/.env.app.prod \
  --prefix /cv-web/prod/app \
  --region <your-region> \
  --secure-keys OPENBAO_TOKEN,DB_PASSWORD,POSTGRES_PASSWORD

./scripts/aws-ssm-sync-env.sh \
  --file docker/.env.ops.prod \
  --prefix /cv-web/prod/ops \
  --region <your-region> \
  --secure-keys GRAFANA_ADMIN_PASSWORD
```

## 9. One-time OpenBao bootstrap on EC2

Connect via Session Manager:

1. AWS Console -> EC2 -> instance -> `Connect` -> `Session Manager`

On host (after first release bundle exists):

```bash
cd /opt/cv-web/releases/<release-tag>
docker compose --env-file docker/.env.ops.prod -f docker/compose.ops.prod.yml up -d
```

Initialize/unseal once:

```bash
docker compose --env-file docker/.env.ops.prod -f docker/compose.ops.prod.yml exec openbao bao operator init -key-shares=1 -key-threshold=1
docker compose --env-file docker/.env.ops.prod -f docker/compose.ops.prod.yml exec openbao bao operator unseal <unseal-key>
```

Enable KV v2 mount (once):

```bash
docker compose --env-file docker/.env.ops.prod -f docker/compose.ops.prod.yml exec openbao bao secrets enable -path=kv kv-v2
```

Write app secrets used by containers:

```bash
docker compose --env-file docker/.env.ops.prod -f docker/compose.ops.prod.yml exec openbao \
  bao kv put kv/cv-web/app \
  ADMIN_API_TOKEN='<value>' \
  AUTH_SESSION_SECRET='<value>' \
  TOLGEE_API_KEY='<value>' \
  GOOGLE_CLIENT_SECRET='<value-if-used>'
```

Create app read-only policy/token, then update SSM `OPENBAO_TOKEN`.

## 10. Deploy flow after release

When you publish a GitHub Release:

1. Workflow builds api/web production images.
2. Pushes images to ECR with release tag.
3. Uploads deploy bundle to S3.
4. Executes remote deploy on EC2 via SSM.
5. Host script reads env from SSM, starts ops + app compose, runs migrations, checks health.

Manual rollback/redeploy:

1. `Actions` -> `Deploy AWS (EC2 Compose)` -> `Run workflow`
2. Set `release_tag` to a previous known-good tag.

## 11. Common failure cases

1. SSM command denied
Cause: GitHub deploy role missing SSM permissions or wrong instance id.
Fix: verify Terraform outputs and GitHub env vars.

2. OpenBao health fails during deploy
Cause: OpenBao sealed/uninitialized.
Fix: unseal OpenBao and confirm KV mount/path exists.

3. App cannot fetch secrets
Cause: invalid `OPENBAO_TOKEN` in SSM app prefix.
Fix: issue new read token and update SSM parameter.

4. Domain not reachable (Cloudflare mode)
Cause: missing/incorrect Cloudflare A records.
Fix: set `app`/`api` A records to `instance_public_ip` and verify with `dig`.

5. Domain not reachable (Route53 mode)
Cause: domain not delegated to Route53 or wrong hosted zone id.
Fix: validate NS delegation and `route53_zone_id`.
