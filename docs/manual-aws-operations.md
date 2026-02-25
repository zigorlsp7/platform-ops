# Manual AWS Operations (No Helper Scripts)

This document replaces removed helper scripts for:

- syncing required ops secrets to SSM
- opening SSM port-forward tunnels to private ops UIs

## 1. Get deployment values

From Terraform outputs:

```bash
cd <path-to-platform-ops>

VARS_JSON="$(terraform -chdir=infra/terraform/aws-compose output -json github_actions_variables)"
AWS_REGION="$(printf '%s' "$VARS_JSON" | jq -r '.AWS_REGION')"
INSTANCE_ID="$(printf '%s' "$VARS_JSON" | jq -r '.AWS_DEPLOY_INSTANCE_ID')"
OPS_SSM_PREFIX="$(printf '%s' "$VARS_JSON" | jq -r '.AWS_SSM_OPS_PREFIX')"

echo "AWS_REGION=$AWS_REGION"
echo "INSTANCE_ID=$INSTANCE_ID"
echo "OPS_SSM_PREFIX=$OPS_SSM_PREFIX"
```

If you do not use local Terraform state, use values from GitHub Environment `production`:

- `AWS_REGION`
- `AWS_DEPLOY_INSTANCE_ID`
- `AWS_SSM_OPS_PREFIX`

## 2. Put required ops secrets in SSM

Required secrets:

- `GRAFANA_ADMIN_PASSWORD`
- `TOLGEE_INITIAL_PASSWORD`
- `TOLGEE_JWT_SECRET`

Commands:

```bash
aws ssm put-parameter \
  --region "$AWS_REGION" \
  --name "$OPS_SSM_PREFIX/GRAFANA_ADMIN_PASSWORD" \
  --type SecureString \
  --overwrite \
  --value '<grafana-admin-password>'

aws ssm put-parameter \
  --region "$AWS_REGION" \
  --name "$OPS_SSM_PREFIX/TOLGEE_INITIAL_PASSWORD" \
  --type SecureString \
  --overwrite \
  --value '<tolgee-initial-password>'

aws ssm put-parameter \
  --region "$AWS_REGION" \
  --name "$OPS_SSM_PREFIX/TOLGEE_JWT_SECRET" \
  --type SecureString \
  --overwrite \
  --value '<tolgee-jwt-secret>'
```

Verify names exist:

```bash
aws ssm get-parameters-by-path \
  --region "$AWS_REGION" \
  --path "$OPS_SSM_PREFIX" \
  --recursive \
  --query 'Parameters[].Name' \
  --output text | tr '\t' '\n' | sort
```

## 3. Open SSM port-forward tunnels manually

Run each command in a separate terminal.

OpenBao (`http://127.0.0.1:18200`):

```bash
aws ssm start-session \
  --target "$INSTANCE_ID" \
  --region "$AWS_REGION" \
  --document-name AWS-StartPortForwardingSession \
  --parameters '{"portNumber":["8200"],"localPortNumber":["18200"]}'
```

Grafana (`http://127.0.0.1:13000`):

```bash
aws ssm start-session \
  --target "$INSTANCE_ID" \
  --region "$AWS_REGION" \
  --document-name AWS-StartPortForwardingSession \
  --parameters '{"portNumber":["3000"],"localPortNumber":["13000"]}'
```

Tolgee (`http://127.0.0.1:18080`):

```bash
aws ssm start-session \
  --target "$INSTANCE_ID" \
  --region "$AWS_REGION" \
  --document-name AWS-StartPortForwardingSession \
  --parameters '{"portNumber":["8080"],"localPortNumber":["18080"]}'
```
