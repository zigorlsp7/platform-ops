# Cloud Destroy (platform-ops)

Use this runbook when you want to tear down the AWS production platform and stop ongoing AWS cost.

This removes the shared infrastructure created by `platform-ops`.
That means production for `cv`, `gpool`, and `notifications` goes down too because those repos depend on the shared EC2 host, ingress, OpenBao instance, and observability stack.

## 1. What This Destroys

- the `infra/terraform/aws-compose` layer
  - VPC, subnet, route table, security group
  - shared EC2 instance and Elastic IP
  - deploy bucket
  - ECR repositories managed by this stack
  - IAM roles, policies, and instance profile managed by this stack
- the `infra/terraform/bootstrap` layer
  - Terraform state bucket used by the environment stack

This runbook does not assume a separate Terraform stack for `notifications`.
At the time of writing, `notifications` deploys onto the shared `platform-ops` host and may use a separately created ECR repository outside this Terraform.

## 2. Prerequisites

Run every command from the `platform-ops` repo root.

Required locally:

- AWS CLI with access to the target account
- Terraform
- `jq`
- Bash

Expected profile and region in the examples:

- profile: `platform-ops`
- region: `eu-west-1`

If your names differ, change the commands accordingly.

Important destroy order:

1. destroy `aws-compose` first
2. destroy `bootstrap` second

Do not destroy `bootstrap` first.
The `aws-compose` stack typically uses the bootstrap state bucket as its Terraform backend.

## 3. Authenticate

```bash
cd /Users/zlz104107/zigor-dev/platform-ops
export AWS_PROFILE=platform-ops
export AWS_REGION=eu-west-1

aws sso login --profile "$AWS_PROFILE"
aws sts get-caller-identity --profile "$AWS_PROFILE" >/dev/null
```

## 4. Empty Repositories And Buckets

Some resources in this stack will not destroy cleanly while they still contain data:

- ECR repositories must be empty because the Terraform resources use `force_delete = false`
- S3 versioned buckets must have objects and old versions removed first

Run:

```bash
set -euo pipefail

empty_ecr_repo() {
  local repo="$1"
  local batch
  local count
  local start
  local tmp

  if ! aws ecr describe-repositories \
    --repository-names "$repo" \
    --region "$AWS_REGION" >/dev/null 2>&1; then
    return 0
  fi

  tmp="$(mktemp)"
  aws ecr list-images \
    --repository-name "$repo" \
    --region "$AWS_REGION" \
    --query 'imageIds[*]' \
    --output json > "$tmp"

  count="$(jq 'length' "$tmp")"
  if [ "$count" -gt 0 ]; then
    for start in $(seq 0 100 $((count - 1))); do
      batch="$(mktemp)"
      jq ".[$start:$((start + 100))]" "$tmp" > "$batch"
      aws ecr batch-delete-image \
        --repository-name "$repo" \
        --region "$AWS_REGION" \
        --image-ids "file://$batch" >/dev/null
      rm -f "$batch"
    done
  fi

  rm -f "$tmp"
}

empty_versioned_bucket() {
  local bucket="$1"

  aws s3 rm "s3://$bucket" --recursive --region "$AWS_REGION" >/dev/null 2>&1 || true

  aws s3api list-object-versions \
    --bucket "$bucket" \
    --region "$AWS_REGION" \
    --query 'Versions[].[Key,VersionId]' \
    --output text |
  while read -r key version; do
    if [ -z "${key:-}" ] || [ "$key" = "None" ]; then
      continue
    fi
    aws s3api delete-object \
      --bucket "$bucket" \
      --key "$key" \
      --version-id "$version" \
      --region "$AWS_REGION" >/dev/null
  done

  aws s3api list-object-versions \
    --bucket "$bucket" \
    --region "$AWS_REGION" \
    --query 'DeleteMarkers[].[Key,VersionId]' \
    --output text |
  while read -r key version; do
    if [ -z "${key:-}" ] || [ "$key" = "None" ]; then
      continue
    fi
    aws s3api delete-object \
      --bucket "$bucket" \
      --key "$key" \
      --version-id "$version" \
      --region "$AWS_REGION" >/dev/null
  done
}

terraform -chdir=infra/terraform/aws-compose init
terraform -chdir=infra/terraform/bootstrap init

DEPLOY_BUCKET="$(terraform -chdir=infra/terraform/aws-compose output -raw deploy_bucket_name)"
TFSTATE_BUCKET="$(terraform -chdir=infra/terraform/bootstrap output -raw state_bucket_name)"

for repo_url in \
  "$(terraform -chdir=infra/terraform/aws-compose output -raw api_ecr_repository_url)" \
  "$(terraform -chdir=infra/terraform/aws-compose output -raw web_ecr_repository_url)" \
  "$(terraform -chdir=infra/terraform/aws-compose output -raw cv_api_ecr_repository_url)" \
  "$(terraform -chdir=infra/terraform/aws-compose output -raw cv_ui_ecr_repository_url)" \
  "$(terraform -chdir=infra/terraform/aws-compose output -raw gpool_api_ecr_repository_url)" \
  "$(terraform -chdir=infra/terraform/aws-compose output -raw gpool_web_ecr_repository_url)"
do
  empty_ecr_repo "${repo_url#*/}"
done

empty_versioned_bucket "$DEPLOY_BUCKET"
```

Keep the same shell session open for sections 5 through 7.
Those steps reuse the exported environment variables and the `empty_versioned_bucket` helper above.

If `notifications` uses its own ECR repository outside `platform-ops` Terraform, delete it separately too.
Use the repository name from the `notifications` GitHub `production` environment variable `AWS_ECR_API_REPOSITORY_URI`.

Example:

```bash
aws ecr delete-repository \
  --repository-name <notifications-ecr-repository-name> \
  --force \
  --region "$AWS_REGION"
```

## 5. Destroy The Shared Runtime Layer

Destroy the shared AWS runtime resources first:

```bash
terraform -chdir=infra/terraform/aws-compose destroy -var-file=environments/prod.tfvars
```

This removes the billable runtime infrastructure created by the main Terraform stack.

## 6. Delete Remaining SSM Parameters

These parameters are not managed by Terraform.
Delete them separately for cleanup:

```bash
delete_ssm_path() {
  local path="$1"
  local names

  names="$(
    aws ssm get-parameters-by-path \
      --path "$path" \
      --recursive \
      --region "$AWS_REGION" \
      --query 'Parameters[].Name' \
      --output text 2>/dev/null || true
  )"

  if [ -z "$names" ] || [ "$names" = "None" ]; then
    return 0
  fi

  printf '%s\n' $names | xargs -n 10 aws ssm delete-parameters --region "$AWS_REGION" --names >/dev/null
}

delete_ssm_path /platform-ops/prod/ops
delete_ssm_path /cv/prod/app
delete_ssm_path /gpool/prod/app
delete_ssm_path /notifications/prod/app
```

These parameters are not usually the main source of cost, but removing them avoids leftover deploy configuration.

## 7. Destroy The Bootstrap Layer

After `aws-compose` is gone, empty the Terraform state bucket and destroy the bootstrap layer:

```bash
empty_versioned_bucket "$TFSTATE_BUCKET"

terraform -chdir=infra/terraform/bootstrap destroy -var-file=environments/prod.tfvars
```

At this point the Terraform backend bucket is gone too.

## 8. Verify Nothing Billable Is Left

Run these commands after the full destroy.

Expected result:

- every JSON query returns `[]`
- every `rg` command prints nothing

```bash
aws ec2 describe-instances \
  --filters Name=tag:Project,Values=platform-ops Name=tag:Environment,Values=prod Name=instance-state-name,Values=pending,running,stopping,stopped \
  --query 'Reservations[].Instances[].InstanceId' \
  --output json

aws ec2 describe-addresses \
  --filters Name=tag:Project,Values=platform-ops Name=tag:Environment,Values=prod \
  --query 'Addresses[].AllocationId' \
  --output json

aws ec2 describe-vpcs \
  --filters Name=tag:Project,Values=platform-ops Name=tag:Environment,Values=prod \
  --query 'Vpcs[].VpcId' \
  --output json

aws ec2 describe-subnets \
  --filters Name=tag:Project,Values=platform-ops Name=tag:Environment,Values=prod \
  --query 'Subnets[].SubnetId' \
  --output json

aws ec2 describe-security-groups \
  --filters Name=tag:Project,Values=platform-ops Name=tag:Environment,Values=prod \
  --query 'SecurityGroups[].GroupId' \
  --output json

aws ecr describe-repositories \
  --query 'repositories[].repositoryName' \
  --output text | tr '\t' '\n' | rg '^(platform-ops/prod|cv/prod|gpool/prod|notifications/)'

aws s3api list-buckets \
  --query 'Buckets[].Name' \
  --output text | tr '\t' '\n' | rg 'platform-ops|tfstate|deploy'

aws ssm get-parameters-by-path \
  --path /platform-ops/prod/ops \
  --recursive \
  --query 'Parameters[].Name' \
  --output json

aws ssm get-parameters-by-path \
  --path /cv/prod/app \
  --recursive \
  --query 'Parameters[].Name' \
  --output json

aws ssm get-parameters-by-path \
  --path /gpool/prod/app \
  --recursive \
  --query 'Parameters[].Name' \
  --output json

aws ssm get-parameters-by-path \
  --path /notifications/prod/app \
  --recursive \
  --query 'Parameters[].Name' \
  --output json

aws iam list-roles \
  --query 'Roles[].RoleName' \
  --output text | tr '\t' '\n' | rg '^(platform-ops-prod-|cv-prod-github-deploy$|gpool-prod-github-deploy$)'

aws iam list-instance-profiles \
  --query 'InstanceProfiles[].InstanceProfileName' \
  --output text | tr '\t' '\n' | rg '^platform-ops-prod-'

aws iam list-policies \
  --scope Local \
  --query 'Policies[].PolicyName' \
  --output text | tr '\t' '\n' | rg '^platform-ops-prod-'
```

Billing dashboards lag behind resource deletion.
Use the AWS resource checks above as the immediate source of truth.

## 9. Optional Non-Billable Cleanup

You may also want to remove:

- GitHub environment variables and secrets in `platform-ops`, `cv`, `gpool`, and `notifications`
- DNS records pointing at the old EC2 public IP or DNS name
- any local notes containing OpenBao unseal keys or root tokens if they are no longer needed
