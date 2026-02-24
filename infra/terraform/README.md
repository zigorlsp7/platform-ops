# Terraform Layout

This repository currently has two Terraform tracks:

1. `infra/terraform/aws-compose` (recommended)
- Provisions AWS infrastructure for this repo's current production model: one EC2 host running split compose stacks.
- Works with `.github/workflows/deploy.yml` release deployment flow.

2. `infra/terraform` root files (legacy ECS skeleton)
- Kept for reference from earlier architecture exploration.

If you are deploying the current app as-is, use `aws-compose`.

Also available:

- `infra/terraform/bootstrap` for creating an S3 backend bucket for Terraform state.
