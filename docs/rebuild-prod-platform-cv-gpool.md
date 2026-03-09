# Full Rebuild Guide (platform-ops + cv + gpool)

This is a destructive, from-scratch production rebuild checklist.

Target state:

1. Shared infra/ops stack from `platform-ops`.
2. App stack `cv` deployed from repo `cv`.
3. App stack `gpool` deployed from repo `gpool`.
4. `cv` and `gpool` both consume Tolgee and OpenBao from `platform-ops`.

## 0. Prerequisites

1. AWS account admin access (IAM, EC2, VPC, ECR, S3, SSM).
2. GitHub admin access for repositories:
- `platform-ops`
- `cv`
- `gpool`
3. Cloudflare zone admin access for your domains.
4. Google Cloud Console access for OAuth clients.
5. Local tools:
- `terraform >= 1.6`
- `aws` CLI v2
- `jq`
- `npm`

## 1. Rename and repository baseline

`cv-web` should already be renamed to `cv`. If not, do this first in GitHub:

1. Repo `cv-web` -> `Settings` -> `General` -> rename to `cv`.
2. Update local remote URL:

```bash
git -C /path/to/cv remote set-url origin git@github.com:<org>/cv.git
```

3. In `platform-ops` Terraform vars, use:
- `cv_github_repository = "<org>/cv"`
- `gpool_github_repository = "<org>/gpool"`

## 2. Destroy current AWS infrastructure (full reset)

From `platform-ops/infra/terraform/aws-compose`:

```bash
terraform init
terraform destroy -var-file=environments/prod.tfvars
```

If destroy fails because ECR repositories are not empty, purge images and retry:

```bash
for repo in cv/prod/api cv/prod/web gpool/prod/api gpool/prod/web; do
  digests="$(aws ecr list-images --repository-name "$repo" --query 'imageIds[*].imageDigest' --output text)"
  for digest in $digests; do
    aws ecr batch-delete-image --repository-name "$repo" --image-ids imageDigest="$digest" >/dev/null
  done
done
```

Then rerun `terraform destroy`.

Optional hard reset of Terraform backend (only if you really want to recreate state bucket/table too):

```bash
cd ../bootstrap
terraform init
terraform destroy -var-file=environments/prod.tfvars
```

## 3. Recreate platform-ops infrastructure

### 3.1 Bootstrap backend

```bash
cd /path/to/platform-ops/infra/terraform/bootstrap
cp environments/prod.tfvars.example environments/prod.tfvars
# edit values
terraform init
terraform apply -var-file=environments/prod.tfvars
terraform output backend_config_snippet
```

Apply backend snippet to `../aws-compose/versions.tf`.

### 3.2 Apply aws-compose stack

```bash
cd ../aws-compose
cp environments/prod.tfvars.example environments/prod.tfvars
# edit values
terraform init -reconfigure
terraform apply -var-file=environments/prod.tfvars
```

Ensure `environments/prod.tfvars` includes:

1. `cv_github_repository`, `cv_*` ECR/SSM vars.
2. `gpool_github_repository`, `gpool_*` ECR/SSM vars.

Capture outputs:

```bash
terraform output github_deploy_role_arn
terraform output -json github_actions_variables
terraform output cv_github_deploy_role_arn
terraform output -json cv_github_actions_variables
terraform output gpool_github_deploy_role_arn
terraform output -json gpool_github_actions_variables
terraform output instance_public_ip
```

## 4. GitHub environment setup

### 4.1 `platform-ops` repo -> Environment `production`

Secret:

1. `AWS_DEPLOY_ROLE_ARN` = `terraform output github_deploy_role_arn`

Variables from `terraform output -json github_actions_variables`:

1. `AWS_REGION`
2. `AWS_DEPLOY_BUCKET`
3. `AWS_DEPLOY_INSTANCE_ID`
4. `AWS_SSM_OPS_PREFIX`

### 4.2 `cv` repo -> Environment `production`

Secret:

1. `AWS_DEPLOY_ROLE_ARN` = `terraform output cv_github_deploy_role_arn`

Variables from `terraform output -json cv_github_actions_variables`:

1. `AWS_REGION`
2. `AWS_DEPLOY_BUCKET`
3. `AWS_DEPLOY_INSTANCE_ID`
4. `AWS_ECR_API_REPOSITORY_URI`
5. `AWS_ECR_WEB_REPOSITORY_URI`
6. `AWS_SSM_APP_PREFIX`

Additional `cv` variables:

1. `NEXT_PUBLIC_API_BASE_URL`
2. `NEXT_PUBLIC_RUM_ENABLED`
3. `NEXT_PUBLIC_RUM_ENDPOINT` (optional)
4. `DEPLOY_HEALTHCHECK_URL` (optional)

### 4.3 `gpool` repo -> Environment `production`

Secret:

1. `AWS_DEPLOY_ROLE_ARN` = `terraform output gpool_github_deploy_role_arn`

Variables from `terraform output -json gpool_github_actions_variables`:

1. `AWS_REGION`
2. `AWS_DEPLOY_BUCKET`
3. `AWS_DEPLOY_INSTANCE_ID`
4. `AWS_ECR_API_REPOSITORY_URI`
5. `AWS_ECR_WEB_REPOSITORY_URI`
6. `AWS_SSM_APP_PREFIX`

Additional `gpool` variables:

1. `NEXT_PUBLIC_API_URL`
2. `DEPLOY_HEALTHCHECK_URL` (optional)

## 5. Cloudflare DNS

Use the EC2 Elastic IP (`terraform output instance_public_ip`) as origin.

Create A records:

1. `cv` web domain -> `<instance_public_ip>`
2. `cv` api domain -> `<instance_public_ip>`
3. `gpool` web domain -> `<instance_public_ip>`
4. `gpool` api domain -> `<instance_public_ip>`

Recommended rollout:

1. Start with Cloudflare proxy disabled (DNS only) for first certificate issuance.
2. After successful deploy and HTTPS validation, enable proxy if required.
3. If proxy is enabled, use Cloudflare SSL mode `Full (strict)`.

## 6. Deploy platform-ops and initialize shared services

### 6.1 Put ops secrets in SSM

Follow:

1. `platform-ops/docs/manual-aws-operations.md`

Required SSM keys under `AWS_SSM_OPS_PREFIX`:

1. `GRAFANA_ADMIN_PASSWORD`
2. `TOLGEE_INITIAL_PASSWORD`
3. `TOLGEE_JWT_SECRET`

### 6.2 Deploy ops stack

In GitHub Actions (`platform-ops`), run:

1. `Deploy AWS Ops (EC2 Compose)` with `ref=main`

### 6.3 Initialize OpenBao on the EC2 host (one-time)

Open SSM shell session to instance and run in deployed release dir:

```bash
cd /opt/platform-ops/releases/<release-tag>
docker compose --env-file docker/.env.ops.prod -f docker/compose.ops.prod.yml exec -T openbao \
  bao operator init -key-shares=1 -key-threshold=1
```

Unseal/login and enable KV v2 (if not enabled yet):

```bash
docker compose --env-file docker/.env.ops.prod -f docker/compose.ops.prod.yml exec -T openbao \
  bao operator unseal <UNSEAL_KEY>

docker compose --env-file docker/.env.ops.prod -f docker/compose.ops.prod.yml exec -T openbao \
  bao login <ROOT_TOKEN>

docker compose --env-file docker/.env.ops.prod -f docker/compose.ops.prod.yml exec -T openbao \
  bao secrets enable -path=kv kv-v2
```

Store root token + unseal key in your password manager.

## 7. OpenBao policies/tokens and app secrets

Create `cv` policy:

```bash
docker compose --env-file docker/.env.ops.prod -f docker/compose.ops.prod.yml exec -T openbao sh -lc 'cat > /tmp/cv-policy.hcl <<EOF
path "kv/data/cv" { capabilities = ["read"] }
path "kv/metadata/cv" { capabilities = ["read"] }
EOF
bao policy write cv-app /tmp/cv-policy.hcl'
```

Create `gpool` policy:

```bash
docker compose --env-file docker/.env.ops.prod -f docker/compose.ops.prod.yml exec -T openbao sh -lc 'cat > /tmp/gpool-policy.hcl <<EOF
path "kv/data/gpool" { capabilities = ["read"] }
path "kv/metadata/gpool" { capabilities = ["read"] }
EOF
bao policy write gpool-app /tmp/gpool-policy.hcl'
```

Create read tokens:

```bash
CV_OPENBAO_TOKEN="$(docker compose --env-file docker/.env.ops.prod -f docker/compose.ops.prod.yml exec -T openbao bao token create -policy=cv-app -field=token)"
GPOOL_OPENBAO_TOKEN="$(docker compose --env-file docker/.env.ops.prod -f docker/compose.ops.prod.yml exec -T openbao bao token create -policy=gpool-app -field=token)"
```

Write app secrets:

```bash
docker compose --env-file docker/.env.ops.prod -f docker/compose.ops.prod.yml exec -T openbao \
  bao kv put kv/cv \
  AUTH_SESSION_SECRET="<cv-session-secret>" \
  TOLGEE_API_KEY="<cv-tolgee-api-key>" \
  GOOGLE_CLIENT_SECRET="<cv-google-client-secret>" \
  ADMIN_GOOGLE_EMAILS="<admin1@example.com,admin2@example.com>"

docker compose --env-file docker/.env.ops.prod -f docker/compose.ops.prod.yml exec -T openbao \
  bao kv put kv/gpool \
  TOLGEE_API_KEY="<gpool-tolgee-api-key>" \
  GOOGLE_CLIENT_SECRET="<gpool-google-client-secret>" \
  AUTH_SESSION_SECRET="<gpool-session-secret>" \
  SMTP_PASS="<gpool-smtp-pass>"
```

## 8. Google OAuth setup

Create one OAuth client per app in Google Cloud Console.

`cv` client:

1. Authorized JavaScript origin: `https://<cv-ui-domain>`
2. Authorized redirect URI: `https://<cv-ui-domain>/api/auth/google/callback`
3. Put `GOOGLE_CLIENT_ID` in `/cv/prod/app` (SSM).
4. Put `GOOGLE_CLIENT_SECRET` in `kv/cv` (OpenBao).

`gpool` client:

1. Authorized JavaScript origin: `https://<gpool-web-domain>`
2. Authorized redirect URI: `https://<gpool-api-domain>/api/auth/google/callback`
3. Put `GOOGLE_CLIENT_ID` in `/gpool/prod/app` (SSM).
4. Put `GOOGLE_CLIENT_SECRET` in `kv/gpool` (OpenBao).

## 9. Prepare and sync SSM app env

### 9.1 `cv` SSM sync

1. Edit `cv/docker/.env.app.prod` with production domains and values.
2. Set `OPENBAO_TOKEN` in that file to `$CV_OPENBAO_TOKEN`.
3. Sync to SSM:

```bash
cd /path/to/cv
./scripts/aws-ssm-sync-env.sh \
  --file docker/.env.app.prod \
  --prefix /cv/prod/app \
  --region <aws-region> \
  --secure-keys OPENBAO_TOKEN,DB_PASSWORD,POSTGRES_PASSWORD
```

### 9.2 `gpool` SSM sync

1. Edit `gpool/docker/.env.app.prod` with production domains and values.
2. Set `OPENBAO_TOKEN` in that file to `$GPOOL_OPENBAO_TOKEN`.
3. Keep only non-OpenBao app config in SSM. Runtime app secrets are read from `kv/gpool`.
4. Sync to SSM:

```bash
cd /path/to/gpool
./scripts/aws-ssm-sync-env.sh \
  --file docker/.env.app.prod \
  --prefix /gpool/prod/app \
  --region <aws-region> \
  --secure-keys POSTGRES_PASSWORD,DB_PASSWORD,OPENBAO_TOKEN
```

## 10. Deploy cv and gpool

Deploy `cv`:

1. Merge to `main` in `cv`.
2. Publish release (or run `Deploy AWS App (EC2 Compose)` manually with `release_tag`).
3. Confirm workflow success.

Deploy `gpool`:

1. Merge to `main` in `gpool`.
2. Publish release (or run `Deploy AWS App (EC2 Compose)` manually with `release_tag`).
3. Confirm workflow success.

## 11. Post-deploy verification

1. `platform-ops` services healthy in `/opt/platform-ops/releases/<tag>`.
2. `cv` app health:
- Web `https://<cv-ui-domain>/`
- API `https://<cv-api-domain>/v1/health/ready`
3. `gpool` app health:
- Web `https://<gpool-web-domain>/`
- API `https://<gpool-api-domain>/api/health`
4. Google login works in both apps.
5. Tolgee translations load in both apps.
6. OpenBao read path works for both apps (`kv/cv`, `kv/gpool`).

## 12. GitHub branch protections and release automation

In each repo (`platform-ops`, `cv`, `gpool`):

1. Enforce branch protection on `main`.
2. Require CI checks before merge.
3. Keep `Release Please` workflows enabled.
4. Keep production environment protection rules aligned with your release policy.
