import Config

config :vaultag,
  token_renewal_time_shift: 1,
  lease_renewal_time_shift: 1,
  ets_table_options: [:set, :public, :named_table],
  vault: [
    host: "http://127.0.0.1:8200",
    auth: Vault.Auth.UserPass,
    credentials: %{username: "admin", password: "admin"}
  ]
