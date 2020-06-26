defmodule Vaultag do
  @moduledoc """
  Vault agent.

  A wrapper around `libvault` library.

  ## Configuration

    * `vault` - `libvault` options;
    * `ets_table_options` - options for ETS table;
    * `token_renewal_time_shift` - a time in seconds;

    * `:vault` - `libvault` configuration. See the options for `Vault.new/1`;
    * `:cache_cleanup_interval` - an interval in seconds after which the cache has to be cleaned up
      from the outdated entries. Defaults to `3600`;
    * `:token_renew` - a boolean which indicates whether to use the token renewal functionality.
      Defaults to `true`;
    * `:token_renewal_time_shift` - Defaults to `60` seconds;
    * `:lease_renewal_time_shift` - Defaults to `60` seconds;
  """
  use GenServer

  alias Vaultag.{Logger, Cache}

  import Vaultag.Config

  def start_link(opts) do
    GenServer.start_link(__MODULE__, :ok, Keyword.put_new(opts, :name, __MODULE__))
  end

  def read(path, opts \\ []) do
    maybe_call({:read, path, opts})
  end

  def list(path, opts \\ []) do
    maybe_call({:list, path, opts})
  end

  def write(path, value, opts \\ []) do
    maybe_call({:write, path, value, opts})
  end

  def delete(path, opts \\ []) do
    maybe_call({:delete, path, opts})
  end

  def request(method, path, opts \\ []) do
    maybe_call({:request, method, path, opts})
  end

  def get_vault do
    maybe_call(:get_vault)
  end

  def set_vault(vault) do
    maybe_call({:set_vault, vault})
  end

  @impl true
  def init(:ok) do
    if is_nil(config(:vault)) do
      Logger.info("not configured")
      :ignore
    else
      Process.flag(:trap_exit, true)
      :timer.send_interval(config(:cache_cleanup_interval, 3600) * 1000, self(), :cleanup_cache)
      send(self(), {:auth, 1})
      {:ok, %{table: Cache.init(), vault: Vault.new([])}}
    end
  end

  @impl true
  def handle_call({:read, path, opts}, _, state) do
    # we always gonna put full responses into the cache
    key = Cache.key_for_request(path, Keyword.drop(opts, [:full_response]))

    response =
      with {:cache, nil} <- {:cache, Cache.get(state.table, key)},
           {:ok, data} <- Vault.read(state.vault, path, Keyword.put(opts, :full_response, true)) do
        Cache.put(state.table, key, data)
        maybe_schedule_lease_renewal(data)
        {:ok, data}
      else
        {:cache, data} -> {:ok, data}
        resp -> resp
      end

    reply =
      case {response, Keyword.get(opts, :full_response, false)} do
        {{:ok, data}, false} -> {:ok, Map.fetch!(data, "data")}
        {{:ok, data}, true} -> {:ok, data}
        _ -> response
      end

    {:reply, reply, state}
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
  def handle_call(:get_vault, _, state) do
    {:reply, state.vault, state}
  end

  @impl true
  def handle_call({:set_vault, vault}, _, state) do
    {:reply, vault, %{state | vault: vault}}
  end

  @impl true
  def handle_info({:auth, attempt}, state) do
    case config(:vault, []) |> Vault.new() |> Vault.auth() do
      {:ok, vault} ->
        Logger.info("authenticated")
        maybe_schedule_token_renewal(vault)
        Cache.reset(state.table)
        {:noreply, %{state | vault: vault}}

      {:error, reason} ->
        Logger.error("authentication failed: #{inspect(reason)}, retrying in #{attempt}s")
        Process.send_after(self(), {:auth, attempt + 1}, attempt * 1000)
        {:noreply, state}
    end
  end

  @impl true
  def handle_info({:renew_token, attempt}, state) do
    case Vault.request(state.vault, :post, "/auth/token/renew-self") do
      {:ok, %{"auth" => %{"lease_duration" => lease_duration}, "warnings" => warnings}} ->
        Logger.info("token renewed")
        unless is_nil(warnings), do: Logger.warn("token renewal: #{inspect(warnings)}")
        vault = put_token_expires_at(state.vault, lease_duration)
        maybe_schedule_token_renewal(vault)
        {:noreply, %{state | vault: vault}}

      {:ok, %{"errors" => errors}} ->
        Logger.warn("token renewal failed: #{inspect(errors)}")
        {:noreply, state}

      request_error ->
        Logger.error("token renewal failed: #{inspect(request_error)}, retrying in #{attempt}s")
        Process.send_after(self(), {:renew_token, attempt + 1}, attempt * 1000)
        {:noreply, state}
    end
  end

  @impl true
  def handle_info({:renew_lease, lease_id, attempt}, state) do
    case Vault.request(state.vault, :put, "/sys/leases/renew", body: %{lease_id: lease_id}) do
      {:ok, %{"lease_id" => ^lease_id} = data} ->
        Cache.update(state.table, data)
        maybe_schedule_lease_renewal(data)
        Logger.info("lease ID #{inspect(lease_id)} renewed")

      {:ok, %{"errors" => errors}} ->
        Logger.warn("lease ID #{inspect(lease_id)} failed to renew: #{inspect(errors)}")

      request_error ->
        Logger.error(
          "lease ID #{inspect(lease_id)} failed to renew: " <>
            "#{inspect(request_error)}, retrying in #{attempt}s"
        )

        Process.send_after(self(), {:renew_lease, lease_id, attempt + 1}, attempt * 1000)
    end

    {:noreply, state}
  end

  @impl true
  def handle_info(:cleanup_cache, state) do
    count = Cache.cleanup(state.table)
    Logger.debug("cache cleanup: #{count} entries removed")
    {:noreply, state}
  end

  @impl true
  def terminate(_reason, %{vault: vault}) do
    unless is_nil(vault), do: Vault.request(vault, :post, "/auth/token/revoke-self")
    :ok
  end

  defp maybe_call(message) do
    case GenServer.whereis(__MODULE__) do
      nil -> {:error, :disabled}
      pid -> GenServer.call(pid, message)
    end
  end

  defp maybe_schedule_token_renewal(vault) do
    if config(:token_renewal, true) do
      ttl = NaiveDateTime.diff(vault.token_expires_at, NaiveDateTime.utc_now())
      shift = config(:token_renewal_time_shift, 60)
      delay = ttl - shift

      # FIXME: the token with TTL less than 2 x :token_renewal_time_shift cannot be renewed
      if delay > shift do
        Logger.debug("token renewal scheduled in #{delay}s")
        Process.send_after(self(), {:renew_token, 1}, delay * 1000)
      else
        Logger.debug("re-authentication scheduled in #{ttl}s")
        Process.send_after(self(), {:auth, 1}, ttl * 1000)
      end
    else
      Logger.debug("token renewal disabled")
    end
  end

  defp maybe_schedule_lease_renewal(%{
         "renewable" => true,
         "lease_id" => lease_id,
         "lease_duration" => lease_duration,
         "warnings" => warnings
       }) do
    shift = config(:lease_renewal_time_shift, 60)
    delay = lease_duration - shift

    # FIXME: the lease with the duration less than 2 x :lease_renewal_time_shift cannot be renewed
    if delay > shift do
      Logger.debug("lease ID #{inspect(lease_id)} renewal scheduled in #{delay}s")

      unless is_nil(warnings),
        do: Logger.warn("lease ID #{inspect(lease_id)} renewal: #{inspect(warnings)}")

      Process.send_after(self(), {:renew_lease, lease_id, 1}, delay * 1000)
    end
  end

  defp maybe_schedule_lease_renewal(_), do: :ok

  defp put_token_expires_at(vault, ttl) do
    # https://github.com/matthewoden/libvault/blob/360eb7b2a19fda665c4e05a0aead1f52d3be80fd/lib/vault.ex#L368
    %{vault | token_expires_at: NaiveDateTime.utc_now() |> NaiveDateTime.add(ttl, :second)}
  end
end
