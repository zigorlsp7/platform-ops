# AWS EC2 + Compose Production Stack (Recommended for this repo)

This Terraform stack provisions shared platform infrastructure for compose-based runtime.

It uses:

- 1 EC2 instance (shared app + ops host)
- 1 Elastic IP
- VPC + public subnet + security group
- ECR repos for API/Web images
- S3 deploy bundle bucket
- IAM role for EC2 runtime
- IAM role for GitHub Actions OIDC deploy

Domain routing for specific applications is intentionally handled outside this module
(app repositories and their runtime env/config).

## Directory

- `versions.tf` providers/versions
- `variables.tf` inputs
- `main.tf` resources
- `outputs.tf` values to wire into GitHub
- `templates/user-data.sh.tftpl` EC2 bootstrap
- `environments/prod.tfvars.example` starter values

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
- It does **not** configure per-application DNS hostnames.

Use:

- `scripts/prod-deploy-remote.sh`
- `docs/deploy-aws-terraform.md`
- `docs/manual-aws-operations.md`

for operational setup and release automation.
