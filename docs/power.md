# Power (platform-ops)

Production is a single EC2 host. Switching it off means stopping that instance and nothing else: the root volume, every Docker named volume on it, the Elastic IP, the instance id and the private IP all survive a stop. DNS keeps pointing at the same address and the GitHub deploy variables stay valid.

Compute is the only cost that stops. The volume, the public IPv4 address, the KMS key and the ECR images keep billing, roughly $13 a month at the time of writing. Every hour the host is off saves the t3.large hourly rate.

## Manual switch

The `Power` workflow in `.github/workflows/power.yml` takes one input, `action`, which is `status`, `on` or `off`.

From the GitHub UI: Actions, Power, Run workflow.

From a terminal:

```bash
gh workflow run Power --repo zigordev/platform-ops -f action=off
```

```bash
gh workflow run Power --repo zigordev/platform-ops -f action=on
```

`on` returns once the instance runs, the SSM agent answers and the public health endpoints answer 200. `off` returns once the instance is stopped. `status` prints the instance state and what the public endpoints currently answer.

The workflow shares the `deploy-aws-prod` concurrency group with the ops deploy, so it never stops the host in the middle of an ops deploy.

## Scheduled window

Two EventBridge Scheduler rules, defined in `infra/terraform/aws-compose/main.tf`, stop and start the host on a fixed window. They call EC2 directly, with no Lambda in between, and retry for up to an hour if the call fails.

The window lives in `infra/terraform/aws-compose/environments/prod.tfvars`:

```hcl
power_schedule_enabled  = true
power_schedule_timezone = "Europe/Madrid"
power_off_schedule      = "cron(0 1 * * ? *)"
power_on_schedule       = "cron(0 8 * * ? *)"
```

The cron fields are minutes, hours, day of month, month, day of week and year, and one of day of month or day of week must be `?`. The timezone is an IANA name, and daylight saving is handled by the scheduler. A weekday-only window:

```hcl
power_off_schedule = "cron(0 1 ? * MON-FRI *)"
power_on_schedule  = "cron(0 8 ? * MON-FRI *)"
```

Apply the change with:

```bash
terraform -chdir=infra/terraform/aws-compose apply -var-file=environments/prod.tfvars
```

Set `power_schedule_enabled = false` and apply again to pause the window without removing it. The manual switch and the schedule do not conflict: both act on the same instance state, and whichever runs later wins.

## What to expect when the host comes back

Docker starts on boot and every container carries `restart: unless-stopped`, so the whole estate restarts on its own. OpenBao unseals itself through KMS. Applications retry their dependencies for about ninety seconds and are restarted by Docker if they give up, so the first few minutes show containers restarting; that is normal. Expect three to five minutes until every public endpoint answers.

The `ServiceDown` alerts for the five trading-bot scrape jobs fire on every boot, exactly as they do after every ops deploy, because those targets do not exist yet. Prometheus, Loki and Jaeger show a gap for the off hours.

## While the host is off

- The public sites do not answer. Behind Cloudflare that is a 522 page; without it, a connection timeout.
- Every deploy fails at the SSM step, because the instance is not there to receive the command. Power the host on, then re-run the deploy. This applies to the ops deploy and to the four product deploys.
- The uptime probe reads the instance state before probing and skips a run while the host is stopped on purpose. A host that is stopped for any other reason, or terminated, opens the uptime issue as before. The probe also gives a freshly started host ten minutes before judging it. This needs the repository variables `AWS_PROBE_ROLE_ARN` (the `github_probe_role_arn` Terraform output) and `AWS_REGION`; without them the probe behaves as before and opens its issue while the host is off.

## Do not

- Do not `docker stop` containers before stopping the instance. A container stopped by hand does not come back on boot under `unless-stopped`. Let the OS shutdown stop them.
- Do not terminate the instance. Termination deletes the root volume and with it every database. API termination protection is on, so the console and the CLI refuse it until someone turns that off deliberately.
