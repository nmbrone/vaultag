defmodule Vaultag.Cache do
  @moduledoc false

  alias Vaultag.Logger
  import Vaultag.Config

  def init do
    :ets.new(config(:ets_table_name, :vaultag), config(:ets_table_options, [:set, :private]))
  end

  def put(table, key, %{"lease_duration" => ttl} = data) do
    put(table, key, data, ttl)
  end

  def put(table, key, data, ttl) do
    :ets.insert(table, {key, data, timestamp(ttl)})
  end

  def get(table, key) do
    now = timestamp()

    case :ets.lookup(table, key) do
      [{^key, data, expires_at}] when expires_at > now -> data
      # expired
      [{_, _, _}] -> nil
      # not in the cache
      [] -> nil
    end
  end

  def update(table, %{"lease_id" => lease_id, "data" => nil} = new_data) do
    case :ets.match_object(table, {:_, %{"lease_id" => lease_id}, :_}) do
      [{key, old_data, _}] ->
        new_data = Map.put(new_data, "data", Map.fetch!(old_data, "data"))
        put(table, key, new_data)
        new_data

      [] ->
        nil
    end
  end

  def update(_table, new_data) do
    Logger.warn("unexpected data for cache update: #{inspect(new_data)}")
    nil
  end

  def cleanup(table) do
    now = timestamp()
    :ets.select_delete(table, [{{:_, :_, :"$1"}, [{:>, now, :"$1"}], [true]}])
  end

  def key_for_request(path, opts) do
    :crypto.hash(:md5, inspect({path, opts})) |> Base.encode16()
  end

  defp timestamp() do
    DateTime.utc_now() |> DateTime.to_unix(:second)
  end

  defp timestamp(diff) do
    DateTime.utc_now() |> DateTime.add(diff, :second) |> DateTime.to_unix(:second)
  end
end
