# Vaultag

![CI](https://github.com/nmbrone/vaultag/workflows/CI/badge.svg)

A wrapper around [`libvault`](https://github.com/matthewoden/) which provides additional functionality:

1. Management of token lifecycle (renew/re-auth/revoke).
2. Caching for secrets.
3. Management of lease renewals for secrets.

## Installation

If [available in Hex](https://hex.pm/docs/publish), the package can be installed
by adding `vaultag` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:vaultag, "~> 0.1.0"}
  ]
end
```

Documentation can be generated with [ExDoc](https://github.com/elixir-lang/ex_doc)
and published on [HexDocs](https://hexdocs.pm). Once published, the docs can
be found at [https://hexdocs.pm/vaultag](https://hexdocs.pm/vaultag).

## Configuration

```elixir
# config/config.exs

config :vaultag, :vault,
  host: "http://my-vault-sever",
  auth: Vault.Auth.Kubernetes,
  engine: Vault.Engine.KVV1,
  credentials: %{"role" => "my-role", "jwt" => "my-jwt"}
```

## Local testing

Before running the tests you will need to prepare local Vault dev server.

[Download](https://www.vaultproject.io/downloads) Vault binary and put it under `./bin/vault` path.

Then run the following commands in terminal:

```bash
./bin/vault server -dev -dev-root-token-id="root"
./test/support/vault/setup.sh
```

Then run `mix test` as usual.
