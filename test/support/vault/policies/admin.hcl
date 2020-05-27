path "kv/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}

path "database/creds/admin" {
  capabilities = ["read"]
}

path "rabbitmq/creds/admin" {
  capabilities = ["read"]
}
