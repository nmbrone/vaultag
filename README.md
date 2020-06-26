# Vaultag - Vault Agent

![CI](https://github.com/nmbrone/vaultag/workflows/CI/badge.svg)

A GenServer which wraps excellent [`libvault`](https://github.com/matthewoden/libvault) library 
to provide the following additional functionality:

1. Management of token lifecycle (renew/re-auth/revoke).
2. Caching for secrets.
3. Management of lease renewals for secrets.

## Installation

The package can be installed by adding `vaultag` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:vaultag, github: "nmbrone/vaultag", branch: "master"}
  ]
end
```

## Usage

Intended to be used as a part of your application supervision tree.

```elixir
defmodule MyApp.Application do
  use Application

  def start(_type, _args) do
    children = [Vaultag]
    opts = [strategy: :one_for_one, name: MyApp.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
```

#### Options

- `:vault` (default `[]`) - a config for [`libvault`](https://github.com/matthewoden/libvault) 
library. If omitted `Vaultag` is considered disabled;
- `:cache_cleanup_interval` (default `3600`) -  the interval in seconds for cleaning up outdated 
cache entries;
- `:token_renew` (default `true`) - a boolean which indicates whether to use the token renewal 
feature; 
- `:token_renewal_time_shift` (default `60`) - seconds prior to the token TTL end when the renewal 
attempt should be made;
- `:lease_renewal_time_shift` (default `60`) - seconds prior to the lease duration end when the 
renewal attempt should be made;

```elixir
config :vaultag,
  cache_cleanup_interval: 3600,
  token_renew: true,
  token_renewal_time_shift: 60,
  lease_renewal_time_shift: 60,
  vault: [
    host: "http://my-vault-sever",
    auth: Vault.Auth.Kubernetes,
    engine: Vault.Engine.KVV1,
    credentials: %{"role" => "my-role", "jwt" => "my-jwt"}
  ]
```

## API

Wrappers for `libvault` API:

- `Vaultag.read(path, opts \\ [])` - same as `Vault.read/3`;
- `Vaultag.list(path, opts \\ [])` - same as `Vault.list/3`;
- `Vaultag.write(path, value, opts \\ [])` - same as `Vault.write/4`;
- `Vaultag.delete(path, opts \\ [])` - same as `Vault.delete/3`;
- `Vaultag.request(method, path, opts \\ [])` - same as `Vault.request/4`;

All the functions above will return `{:error, :disabled}` in case Vaultag is not configured or not 
started, which means they are safe to use in the environments where the vault server might be not 
available.

Additional functions:

- `Vaultag.get_vault()` - gets the cached `%Vault{}` structure;
- `Vaultag.set_vault(vault)` - sets the specified `%Vault{}` structure for future usage;

## Using with `libvault`

```elixir
Vaultag.get_vault()
|> Vault.set_engine(Vault.Engine.KVV2)
|> Vaultag.set_vault()


Vault.request(Vaultag.get_vault(), :post, "path/to/call", [ body: %{ "foo" => "bar"}])
```

## Limitations

Currently `:token_renewal_time_shift` must be less than half of the token TTL, which means that if 
the TTL is set to 60 seconds then `:token_renewal_time_shift` has to be set to less than 30 seconds.

The same limitation applies to `:lease_renewal_time_shift`.

## Testing locally

Before running the tests you will need to prepare local the Vault server.

[Download](https://www.vaultproject.io/downloads) Vault binary and put it under `./bin/vault` path.

Then run the following commands in a terminal:

```bash
./bin/vault server -dev -dev-root-token-id="root"
./test/support/vault/setup.sh
```

Then run `mix test` as usual.
