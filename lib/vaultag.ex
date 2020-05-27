defmodule Vaultag do
  @moduledoc """
  Vault agent.

  A wrapper around `libvault` library.

  ## Configuration

    * `vault` - `libvault` options;
    * `ets_table_options` - options for ETS table;
    * `token_renew` - a boolean which indicates whether to use the token renewal;
    * `token_renew_time_shift` - a time in seconds;
  """
  use GenServer
  alias Vaultag.Logger

  @otp_app :vaultag

  def start_link(opts) do
    GenServer.start_link(__MODULE__, :ok, Keyword.put_new(opts, :name, __MODULE__))
  end

  def read(path, opts \\ []) do
    case Keyword.pop(opts, :cache) do
      {true, opts} -> GenServer.call(__MODULE__, {:cache, path, opts})
      {_not, opts} -> GenServer.call(__MODULE__, {:read, path, opts})
    end
  end

  def list(path, opts \\ []) do
    GenServer.call(__MODULE__, {:list, path, opts})
  end

  def write(path, value, opts \\ []) do
    GenServer.call(__MODULE__, {:write, path, value, opts})
  end

  def delete(path, opts \\ []) do
    GenServer.call(__MODULE__, {:delete, path, opts})
  end

  def request(method, path, opts \\ []) do
    GenServer.call(__MODULE__, {:request, method, path, opts})
  end

  def get_client do
    GenServer.call(__MODULE__, :get_client)
  end

  def set_client(vault) do
    GenServer.call(__MODULE__, {:set_client, vault})
  end

  @impl true
  def init(:ok) do
    Process.flag(:trap_exit, true)
    t = :ets.new(config(:ets_table_name, @otp_app), config(:ets_table_options, [:set, :private]))
    send(self(), :auth)
    {:ok, %{table: t, vault: nil}}
  end

  @impl true
  def handle_call({:cache, path, opts}, _, state) do
    {:reply, get_cache_or_read(state, path, opts), state}
  end

  @impl true
  def handle_call({:read, path, opts}, _, state) do
    {:reply, Vault.read(state.vault, path, opts), state}
  end

  @impl true
  def handle_call({:list, path, opts}, _, state) do
    {:reply, Vault.list(state.vault, path, opts), state}
  end

  @impl true
  def handle_call({:write, path, value, opts}, _, state) do
    {:reply, Vault.write(state.vault, path, value, opts), state}
  end

  @impl true
  def handle_call({:delete, path, opts}, _, state) do
    {:reply, Vault.delete(state.vault, path, opts), state}
  end

  @impl true
  def handle_call({:request, method, path, opts}, _, state) do
    {:reply, Vault.request(state.vault, method, path, opts), state}
  end

  @impl true
  def handle_call(:get_client, _, state) do
    {:reply, state.vault, state}
  end

  @impl true
  def handle_call({:set_client, vault}, _, state) do
    {:reply, vault, %{state | vault: vault}}
  end

  @impl true
  def handle_info(:auth, state) do
    case config(:vault, []) |> Vault.new() |> Vault.auth() do
      {:ok, vault} ->
        Logger.info("authenticated")
        maybe_schedule_token_renewal(vault)
        {:noreply, %{state | vault: vault}}

      # TODO: how should we handle the auth error?
      {:error, reason} ->
        Logger.error("authentication failed: #{inspect(reason)}, retrying in 5s")
        Process.send_after(self(), :auth, 5000)
        {:noreply, state}
    end
  end

  @impl true
  def handle_info(:do_token_renewal, state) do
    case Vault.request(state.vault, :post, "/auth/token/renew-self") do
      {:ok, %{"auth" => %{"lease_duration" => lease_duration}}} ->
        Logger.info("token renewed")
        vault = put_token_expires_at(state.vault, lease_duration)
        maybe_schedule_token_renewal(vault)
        {:noreply, %{state | vault: vault}}

      {:ok, %{"errors" => ["permission denied"]}} ->
        Logger.warn("token renewal failed: token already expired")
        send(self(), :auth)
        {:noreply, state}

      other ->
        Logger.error("token renewal failed: #{inspect(other)}")
        Process.send_after(self(), :schedule_token_renewal, 1000)
        {:noreply, state}
    end
  end

  @impl true
  def terminate(_reason, %{vault: vault}) do
    unless is_nil(vault), do: Vault.request(vault, :post, "/auth/token/revoke-self")
    :ok
  end

  defp maybe_schedule_token_renewal(vault) do
    if config(:token_renew, true) do
      ttl = NaiveDateTime.diff(vault.token_expires_at, NaiveDateTime.utc_now())
      delay = ttl - config(:token_renew_time_shift, 60)
      # the threshold here is used to avoid sending too many requests to the server when the token
      # is about to reach its `token_max_ttl` which also means the tokens with `token_ttl` less than
      # the threshold cannot be renewed in this way
      delay = Enum.max([delay, config(:token_renew_threshold, 2)])
      Logger.debug("token renewal scheduled in #{delay}s")
      Process.send_after(self(), :do_token_renewal, delay * 1000)
    else
      Logger.debug("token renewal disabled")
    end
  end

  defp get_cache_or_read(state, path, opts) do
    key = {path, opts}

    case :ets.lookup(state.table, key) do
      [{_key, res}] ->
        res

      [] ->
        res = Vault.read(state.vault, path, opts)
        # cache only success responses
        if match?({:ok, _}, res), do: :ets.insert(state.table, {key, res})
        res
    end
  end

  defp put_token_expires_at(vault, ttl) do
    # https://github.com/matthewoden/libvault/blob/360eb7b2a19fda665c4e05a0aead1f52d3be80fd/lib/vault.ex#L368
    %{vault | token_expires_at: NaiveDateTime.utc_now() |> NaiveDateTime.add(ttl, :second)}
  end

  defp config(key, default) do
    Keyword.get(config(), key, default)
  end

  defp config do
    Application.get_all_env(@otp_app) || []
  end
end
