import Config

config :vaultag,
  ets_table_options: [:set, :public, :named_table],
  vault: [
    host: "http://127.0.0.1:8200",
    auth: Vault.Auth.UserPass,
    credentials: %{username: "admin", password: "admin"}
  ]
