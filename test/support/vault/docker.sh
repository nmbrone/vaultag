#!/usr/bin/env bash

docker run --rm -d \
  -p 8200:8200 \
  -v $(pwd)/test/support/vault:/vault/setup \
  -e VAULT_DEV_ROOT_TOKEN_ID=root \
  --name=dev-vault \
  --cap-add=IPC_LOCK \
  vault

sleep 5s
docker exec dev-vault cp /home/vault/.vault-token /root/.vault-token
docker exec dev-vault sh /vault/setup/setup.sh
