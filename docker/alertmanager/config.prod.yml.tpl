# Alertmanager, rendered at deploy time.
#
# This is a TEMPLATE, not a config. Alertmanager does not expand environment
# variables in its configuration file — the previous version of this file was
# full of `${SLACK_WEBHOOK_URL}`-style placeholders and nothing ever substituted
# them, so every receiver would have failed on its first delivery. The estate
# believed it had three working alert channels and had none.
#
# `scripts/render-alertmanager-config.sh` renders it at deploy time, on the
# host, reading the SMTP credentials from SSM the same way Grafana's and
# Tolgee's are read. SSM rather than OpenBao because OpenBao is a service inside
# this stack: it cannot be the source of the config that starts the stack.
#
# The rendered file is gitignored. It contains an SMTP password, so it must
# never exist inside the repository.
#
# One receiver, by choice. PagerDuty and a Slack workspace are an on-call
# rotation's tools; this is a solo estate, and an alert that arrives in three
# places is an alert that gets muted in three places.

global:
  resolve_timeout: 5m
  smtp_smarthost: '${SMTP_SMARTHOST}'
  smtp_from: '${SMTP_FROM}'
  smtp_auth_username: '${SMTP_AUTH_USERNAME}'
  smtp_auth_password: '${SMTP_AUTH_PASSWORD}'
  smtp_require_tls: true

route:
  receiver: email-page
  # Grouped by alert name and service, so a broker outage that trips four
  # services arrives as one mail per alert rather than four separate ones.
  group_by: ['alertname', 'job']
  group_wait: 30s
  group_interval: 5m
  repeat_interval: 4h
  routes:
    # `page` — broken now. Notify quickly and repeat until it resolves.
    - matchers:
        - severity="page"
      receiver: email-page
      group_wait: 30s
      repeat_interval: 1h

    # `ticket` — real, but it can wait. Batched, and repeated once a day rather
    # than once an hour, because the failure mode of a ticket alert is being
    # ignored rather than being missed.
    - matchers:
        - severity="ticket"
      receiver: email-ticket
      group_wait: 5m
      group_interval: 30m
      repeat_interval: 24h

receivers:
  - name: email-page
    email_configs:
      - to: '${ALERT_EMAIL_TO}'
        send_resolved: true
        headers:
          subject: '[FIRING] {{ .CommonLabels.alertname }} — {{ .CommonLabels.job }}'
        html: |
          {{ range .Alerts }}
          <h3>{{ .Annotations.summary }}</h3>
          <p>{{ .Annotations.description }}</p>
          <p><b>Service:</b> {{ .Labels.job }}<br>
             <b>Severity:</b> {{ .Labels.severity }}<br>
             <b>Since:</b> {{ .StartsAt }}</p>
          <p><a href="{{ .Annotations.runbook_url }}">Runbook</a></p>
          <hr>
          {{ end }}

  - name: email-ticket
    email_configs:
      - to: '${ALERT_EMAIL_TO}'
        send_resolved: true
        headers:
          subject: '[{{ .Status | toUpper }}] {{ .CommonLabels.alertname }}'
        html: |
          {{ range .Alerts }}
          <h3>{{ .Annotations.summary }}</h3>
          <p>{{ .Annotations.description }}</p>
          <p><b>Service:</b> {{ .Labels.job }}<br>
             <b>Since:</b> {{ .StartsAt }}</p>
          <p><a href="{{ .Annotations.runbook_url }}">Runbook</a></p>
          <hr>
          {{ end }}
