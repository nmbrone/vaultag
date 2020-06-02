defmodule Vaultag.Config do
  @otp_app :vaultag

  def config(key, default) do
    Keyword.get(config(), key, default)
  end

  def config do
    Application.get_all_env(@otp_app) || []
  end
end
