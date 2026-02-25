# Terraform Layout

Active Terraform modules in this repository:

1. `infra/terraform/bootstrap`
- Creates backend primitives (for example, S3 state bucket) for Terraform state management.

2. `infra/terraform/aws-compose`
- Provisions AWS infrastructure for the compose-based runtime model used by `platform-ops`.

For current production use, `aws-compose` is the primary infrastructure module.
