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
    expires_at = NaiveDateTime.add(NaiveDateTime.utc_now(), ttl, :second)
    :ets.insert(table, {key, data, expires_at})
  end

  def get(table, key) do
    with [{^key, data, expires_at}] <- :ets.lookup(table, key),
         :gt <- NaiveDateTime.compare(expires_at, NaiveDateTime.utc_now()) do
      data
    else
      # not in the cache
      [] ->
        nil

      # expired
      _ ->
        :ets.delete(table, key)
        nil
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

  def key_for_request(path, opts) do
    :crypto.hash(:md5, inspect({path, opts})) |> Base.encode16()
  end
end
