# Vaultag

![CI](https://github.com/nmbrone/vaultag/workflows/CI/badge.svg)

A wrapper around Vault library [`libvault`](https://github.com/matthewoden/) which provides:

1. Management of token lifecycle (renew/re-auth).
2. Cache for secrets.

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

## Configuring

```elixir
# config/config.exs

config :vaultag, :vault,
  host: "http://my-vault-sever",
  auth: Vault.Auth.Kubernetes,
  engine: Vault.Engine.KVV1,
  credentials: %{"role" => "my-role", "jwt" => "my-jwt"}
```
