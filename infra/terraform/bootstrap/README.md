# Terraform Backend Bootstrap (S3)

Use this once per AWS account/region to create an S3 bucket for Terraform remote state.

## 1. Initialize

```bash
cd infra/terraform/bootstrap
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

## 4. Copy backend snippet

```bash
terraform output backend_config_snippet
```

Then add that backend block to your environment stack before running `terraform init` there.
