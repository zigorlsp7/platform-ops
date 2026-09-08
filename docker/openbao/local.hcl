ui = true

listener "tcp" {
  address     = "0.0.0.0:8200"
  tls_disable = "true"

  telemetry {
    unauthenticated_metrics_access = true
  }
}

storage "raft" {
  path    = "/openbao/data"
  node_id = "platformops-openbao-prod-1"
}

api_addr = "http://openbao:8200"
cluster_addr = "http://openbao:8201"

telemetry {
  prometheus_retention_time = "24h"
  disable_hostname          = true
}
