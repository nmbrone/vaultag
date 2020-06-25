#!/usr/bin/env bash

export VAULT_ADDR="http://127.0.0.1:8200"


# AUTH
vault policy write admin "$(dirname $0)/policies/admin.hcl"
vault auth enable userpass
vault write auth/userpass/users/admin \
  password="admin" \
  token_policies="default,admin" \
  token_ttl=3s \
  token_max_ttl=8s
vault auth enable approle
vault write auth/approle/role/admin \
  bind_secret_id=true \
  token_policies="default,admin" \
  token_ttl=1m \
  token_max_ttl=30m


# KV
vault secrets enable -version=1 kv
vault kv put kv/my-secret foo=bar


# DATABASE
#vault secrets enable database
#vault write database/config/b4c_redeem_test \
#  plugin_name=postgresql-database-plugin \
#  allowed_roles="admin" \
#  connection_url="postgresql://{{username}}:{{password}}@localhost:5432/?sslmode=disable" \
#  username="postgres" \
#  password="postgres"
#vault write database/roles/admin \
#  db_name=b4c_redeem_test \
#  creation_statements="CREATE ROLE \"{{name}}\" WITH LOGIN PASSWORD '{{password}}' VALID UNTIL '{{expiration}}'; GRANT SELECT ON ALL TABLES IN SCHEMA public TO \"{{name}}\";" \
#  default_ttl=2h \
#  max_ttl=48h


# RABBITMQ
vault secrets enable rabbitmq
vault write rabbitmq/config/connection \
  connection_uri=${RABBITMQ_URL:-"http://localhost:15672"} \
  username=${RABBITMQ_USER:-"guest"} \
  password=${RABBITMQ_PASSWORD:-"guest"} \
  verify_connection=true
vault write rabbitmq/config/lease ttl=3s max_ttl=5s
vault write rabbitmq/roles/admin vhosts='{"/":{"write": ".*", "read": ".*", "configure": ".*"}}' tags="vault"
