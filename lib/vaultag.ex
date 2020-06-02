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
  alias Vaultag.{Logger, Cache}
  import Vaultag.Config

  def start_link(opts) do
    GenServer.start_link(__MODULE__, :ok, Keyword.put_new(opts, :name, __MODULE__))
  end

  def read(path, opts \\ []) do
    GenServer.call(__MODULE__, {:read, path, opts})
  end

  def read_dynamic(path, opts \\ []) do
    GenServer.call(__MODULE__, {:read_dynamic, path, opts})
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
    send(self(), {:auth, 1})
    {:ok, %{table: Cache.init(), vault: nil}}
  end

  @impl true
  def handle_call({:read, path, opts}, _, state) do
    {:reply, Vault.read(state.vault, path, opts), state}
  end

  @impl true
  def handle_call({:read_dynamic, path, opts}, _, state) do
    # we always gonna put full responses into the cache
    key = Cache.key_for_request(path, Keyword.drop(opts, [:full_response]))

    # TODO: refactor
    response =
      case Cache.get(state.table, key) do
        nil ->
          case Vault.read(state.vault, path, Keyword.put(opts, :full_response, true)) do
            {:ok, data} ->
              Cache.put(state.table, key, data)
              maybe_schedule_lease_renewal(data)
              {:ok, data}

            resp ->
              resp
          end

        cached ->
          {:ok, cached}
      end

    reply =
      case {response, Keyword.get(opts, :full_response, false)} do
        {{:ok, data}, true} -> {:ok, data}
        {{:ok, %{"data" => data}}, false} -> {:ok, data}
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
  def handle_call(:get_client, _, state) do
    {:reply, state.vault, state}
  end

  @impl true
  def handle_call({:set_client, vault}, _, state) do
    {:reply, vault, %{state | vault: vault}}
  end

  @impl true
  def handle_info({:auth, attempt}, state) do
    case config(:vault, []) |> Vault.new() |> Vault.auth() do
      {:ok, vault} ->
        Logger.info("authenticated")
        maybe_schedule_token_renewal(vault)
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
        Logger.warn("token renewal failed: #{inspect(errors)}, re-authenticating...")
        send(self(), {:auth, 1})
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
        # update cached data
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
      Process.send_after(self(), {:renew_token, 1}, delay * 1000)
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
    delay = lease_duration - config(:lease_renew_time_shift, 60)
    # the threshold here is used to avoid sending too many requests to the server when the lease
    # is about to reach its `max_ttl` which also means the leases with `ttl` less than
    # the threshold cannot be renewed in this way
    delay = Enum.max([delay, config(:lease_renew_threshold, 2)])
    Logger.debug("lease ID #{inspect(lease_id)} renewal scheduled in #{delay}s")

    unless is_nil(warnings),
      do: Logger.warn("lease ID #{inspect(lease_id)} renewal: #{inspect(warnings)}")

    Process.send_after(self(), {:renew_lease, lease_id, 1}, delay * 1000)
  end

  defp maybe_schedule_lease_renewal(%{"lease_id" => lease_id}) do
    Logger.debug("not renewable lease ID #{inspect(lease_id)}")
  end

  defp put_token_expires_at(vault, ttl) do
    # https://github.com/matthewoden/libvault/blob/360eb7b2a19fda665c4e05a0aead1f52d3be80fd/lib/vault.ex#L368
    %{vault | token_expires_at: NaiveDateTime.utc_now() |> NaiveDateTime.add(ttl, :second)}
  end
end
