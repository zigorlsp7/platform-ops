# Cloud First Deploy (platform-ops)

Use this runbook when you are building the production platform from scratch on AWS.
Complete this repo first. The application repos (`cv`, `gpool`, `notifications`) depend on the infrastructure, ingress, OpenBao instance, shared Redpanda broker, and shared observability services created here.
For full teardown later, use `docs/cloud-destroy.md`.

## 1. What You Are Building

When this runbook is complete, you will have:

- AWS infrastructure provisioned by Terraform
- a production EC2 host running the shared ops stack
- OpenBao, Tolgee, Redpanda, Grafana, Prometheus, Loki, Alertmanager, Jaeger, and the OTEL collector
- central public ingress for all platform domains
- the GitHub deployment wiring needed for this repo and the downstream app repos

## 2. Prerequisites

Run every command in this document from the `platform-ops` repo root unless stated otherwise.

Required locally:

- AWS CLI with SSO configured
- Terraform
- `jq`
- `gh`
- access to the target AWS account
- permission to manage GitHub repository settings and GitHub environments
- access to your DNS provider or Cloudflare account for the platform domains

Expected AWS profile and region in the examples:

- profile: `platform-ops`
- region: `eu-west-1`

If your names differ, change the commands accordingly.

## 3. Prepare Terraform Variables

There are two Terraform stages:

- `infra/terraform/bootstrap`
  - creates the Terraform state bucket and related bootstrap resources
- `infra/terraform/aws-compose`
  - creates the main runtime resources such as VPC, EC2, ECR, IAM roles, and deploy bucket

Create the variable files from their tracked examples if needed:

```bash
cp -n infra/terraform/bootstrap/environments/prod.tfvars.example infra/terraform/bootstrap/environments/prod.tfvars
cp -n infra/terraform/aws-compose/environments/prod.tfvars.example infra/terraform/aws-compose/environments/prod.tfvars
```

Before you run `terraform apply`, fill in the real GitHub OIDC values in `infra/terraform/aws-compose/environments/prod.tfvars`.

At minimum, verify:

- `github_repository = "zigorlsp7/platform-ops"`
- `github_environment = "production"`
- `cv_github_repository = "zigorlsp7/cv"`
- `cv_github_environment = "production"`
- `gpool_github_repository = "zigorlsp7/gpool"`
- `gpool_github_environment = "production"`

If these values are wrong, GitHub Actions will fail to assume the deploy role.

## 4. Apply Terraform

Authenticate to AWS:

```bash
aws sso login --profile platform-ops
aws sts get-caller-identity --profile platform-ops >/dev/null
```

Set the shell environment used by the commands below:

```bash
export AWS_PROFILE=platform-ops
export AWS_REGION=eu-west-1
```

Apply the bootstrap layer:

```bash
terraform -chdir=infra/terraform/bootstrap init
terraform -chdir=infra/terraform/bootstrap apply -var-file=environments/prod.tfvars
```

Apply the main infrastructure layer:

```bash
terraform -chdir=infra/terraform/aws-compose init
terraform -chdir=infra/terraform/aws-compose apply -var-file=environments/prod.tfvars
```

After apply, capture these outputs:

```bash
terraform -chdir=infra/terraform/aws-compose output -json github_actions_variables | jq .
terraform -chdir=infra/terraform/aws-compose output github_deploy_role_arn
terraform -chdir=infra/terraform/aws-compose output -json cv_github_actions_variables | jq .
terraform -chdir=infra/terraform/aws-compose output cv_github_deploy_role_arn
terraform -chdir=infra/terraform/aws-compose output -json gpool_github_actions_variables | jq .
terraform -chdir=infra/terraform/aws-compose output gpool_github_deploy_role_arn
```

Why these matter:

- `github_actions_variables` populates the GitHub `production` environment for `platform-ops`
- `github_deploy_role_arn` becomes a GitHub secret in `platform-ops`
- the `cv_*` and `gpool_*` outputs are needed later when you configure those repos

## 5. Configure GitHub

### 5.1 `platform-ops` Production Environment

In the `platform-ops` GitHub repository, create or update the `production` environment.

Required environment variables:

- `AWS_REGION`
  - AWS region used by the deploy workflow
- `AWS_DEPLOY_BUCKET`
  - S3 bucket where deploy bundles are uploaded
- `AWS_DEPLOY_INSTANCE_ID`
  - EC2 instance targeted by the SSM deploy command
- `AWS_SSM_OPS_PREFIX`
  - SSM path prefix used by the repo, for example `/platform-ops/prod/ops`

Required environment secret:

- `AWS_DEPLOY_ROLE_ARN`
  - IAM role assumed by GitHub Actions through OIDC

### 5.2 Release Please Token

`platform-ops` also needs a repository secret named `RELEASE_PLEASE_TOKEN`.
Without it, the Release Please workflow cannot create or update release PRs.

Create a GitHub token with repository write access, then save it:

```bash
read -rsp "RELEASE_PLEASE_TOKEN: " RELEASE_PLEASE_TOKEN && echo
gh secret set RELEASE_PLEASE_TOKEN \
  --repo zigorlsp7/platform-ops \
  --body "$RELEASE_PLEASE_TOKEN"
unset RELEASE_PLEASE_TOKEN
```

Verify it exists:

```bash
gh secret list --repo zigorlsp7/platform-ops
```

## 6. Create Required SSM Secrets

Create these SecureString parameters under `AWS_SSM_OPS_PREFIX`:

- `GRAFANA_ADMIN_PASSWORD`
- `TOLGEE_INITIAL_PASSWORD`
- `TOLGEE_JWT_SECRET`

Example:

```bash
aws ssm put-parameter --profile platform-ops --name /platform-ops/prod/ops/GRAFANA_ADMIN_PASSWORD --type SecureString --value 'change-me' --overwrite --region eu-west-1
aws ssm put-parameter --profile platform-ops --name /platform-ops/prod/ops/TOLGEE_INITIAL_PASSWORD --type SecureString --value 'change-me' --overwrite --region eu-west-1
aws ssm put-parameter --profile platform-ops --name /platform-ops/prod/ops/TOLGEE_JWT_SECRET --type SecureString --value 'change-me' --overwrite --region eu-west-1
```

Generate a strong Tolgee JWT secret:

```bash
openssl rand -hex 32
```

Keep these values out of git.
Tracked file `docker/.env.ops.prod` should only contain non-secret config.

## 7. Trigger The First Ops Deploy

The workflow is:

- `Deploy AWS Ops (EC2 Compose)` in `.github/workflows/deploy-ops.yml`

Recommended first run:

1. open GitHub Actions for `platform-ops`
2. run `Deploy AWS Ops (EC2 Compose)` manually
3. set `ref=main`
4. leave `release_tag` empty unless you intentionally want a custom value

What the workflow does:

- packages the tracked repository files
- uploads the bundle to S3
- runs the remote deploy script over SSM on the EC2 host

## 8. Initialize OpenBao In Production

After the ops stack is deployed, OpenBao exists but is still uninitialized.

Open the OpenBao UI when reachable, or use a private access method such as SSM if you do not expose it publicly.

Initialize it exactly once:

- `Key shares = 1`
- `Key threshold = 1`

Save:

- `Unseal Key 1`
- `Initial Root Token`

Then:

1. unseal OpenBao with `Unseal Key 1`
2. log in with token auth using `Initial Root Token`
3. enable `kv` v2 at path `kv` if it does not already exist

This is the production secret store used later by `cv`, `gpool`, and `notifications`.
The shared Redpanda broker deployed by `platform-ops` is also what those repos use for Kafka-based notifications.

## 9. Translation Promotion Model

For app repos that use Tolgee, production Tolgee should not be a manual editing source.

Use this model consistently:

- local Tolgee from `platform-ops` is the development authoring source
- downstream app repos pull local Tolgee into tracked `apps/ui/messages/*.json` snapshots
- those snapshot changes are committed to git for history
- each app repo promotes its committed snapshots into production Tolgee through a dedicated GitHub workflow

Operational rule:

- local Tolgee can be edited during development
- production Tolgee should be treated as a promoted runtime target
- do not maintain separate conflicting truths in git, local Tolgee, and prod Tolgee

The downstream app runbooks in `cv` and `gpool` document the repo-specific commands and GitHub settings for this promotion flow.

## 10. Configure DNS And Ingress

`platform-ops` owns the shared public ingress.
These domains come from `docker/.env.ops.prod`:

- `CV_WEB_DOMAIN`
- `CV_API_DOMAIN`
- `GPOOL_WEB_DOMAIN`
- `GPOOL_API_DOMAIN`
- `OPS_GRAFANA_DOMAIN`
- `OPS_TOLGEE_DOMAIN`
- `OPS_OPENBAO_DOMAIN`

Create DNS records pointing those hostnames at the production EC2 public IP or public DNS name.

If you use Cloudflare:

- create the matching records there
- wait for DNS propagation before validating public URLs

Security note:

- exposing OpenBao publicly is high risk
- prefer private access through SSM tunneling or another trusted admin path whenever possible

## 11. Validate The Production Ops Stack

From the EC2 instance or through an SSM shell:

```bash
curl -fsS http://127.0.0.1:8200/v1/sys/health
curl -fsS http://127.0.0.1:3000/api/health
curl -fsS http://127.0.0.1:8080/healthz || curl -fsS http://127.0.0.1:8080/api/healthz
sudo docker compose --env-file "$OPS_DIR/docker/.env.ops.prod" -f "$OPS_DIR/docker/compose.ops.prod.yml" ps redpanda
```

If DNS is already in place, also verify the public endpoints you decided to expose.

Expected result:

- OpenBao responds
- Grafana responds
- Tolgee responds
- Redpanda is running on the shared Docker network for downstream app repos
- the deploy workflow has finished successfully

## 12. Next Step

After `platform-ops` is deployed and OpenBao is initialized, continue with:

- `cv/docs/cloud-first-deploy.md`
- `gpool/docs/cloud-first-deploy.md`
- `notifications/docs/cloud-first-deploy.md`
