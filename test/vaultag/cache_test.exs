defmodule Vaultag.CacheTest do
  use ExUnit.Case, async: true

  alias Vaultag.Cache

  setup do
    table = Cache.init()
    {:ok, table: table}
  end

  describe "put/4" do
    test "puts the given data into the cache with the given TTL", %{table: t} do
      key = "key"
      data = %{some: "data"}
      Cache.put(t, key, data, 60)
      assert [{^key, ^data, _}] = :ets.lookup(t, key)
    end
  end

  describe "put/3" do
    test "determines the TTL from the given data and puts the data into the cache", %{
      table: t
    } do
      key = "key"
      data = %{"lease_duration" => 60}
      Cache.put(t, "key", data)
      assert [{^key, ^data, _}] = :ets.lookup(t, key)
    end
  end

  describe "get/2" do
    test "returns the data from the cache by the given key", %{table: t} do
      key = "key"
      data = %{"lease_duration" => 60}
      Cache.put(t, key, data)
      assert ^data = Cache.get(t, key)
    end

    test "returns `nil` when the data for the given key was not found", %{table: t} do
      assert nil == Cache.get(t, "key")
    end

    test "returns `nil` when the TTL for the cached data has been expired", %{table: t} do
      key = "key"
      Cache.put(t, key, %{"some" => "data"}, 1)
      assert nil != Cache.get(t, key)
      Process.sleep(1000)
      assert nil == Cache.get(t, key)
    end
  end

  describe "update/2" do
    test "updates the cached data and returns it", %{table: t} do
      key = "key"

      Cache.put(t, key, %{
        "lease_id" => "1",
        "data" => %{"foo" => "bar"},
        "request_id" => "1",
        "lease_duration" => 10
      })

      updated =
        Cache.update(t, %{
          "lease_id" => "1",
          "data" => nil,
          "request_id" => "2",
          "lease_duration" => 60
        })

      expected = %{
        "lease_id" => "1",
        "data" => %{"foo" => "bar"},
        "request_id" => "2",
        "lease_duration" => 60
      }

      assert expected == updated
      assert expected == Cache.get(t, key)
    end
  end

  describe "cleanup/0" do
    test "removes the outdated entries from the cache", %{table: t} do
      Cache.put(t, "key1", %{"foo" => "bar"}, -10)
      Cache.put(t, "key2", %{"foo" => "bar"}, -10)
      Cache.put(t, "key3", %{"foo" => "bar"}, 10)
      assert :ets.info(t)[:size] == 3
      Cache.cleanup(t)
      assert :ets.info(t)[:size] == 1
    end
  end

  describe "reset/1" do
    test "resets the cache", %{table: t} do
      Cache.put(t, "key1", %{"foo" => "bar"}, 10)
      Cache.put(t, "key2", %{"foo" => "bar"}, 10)
      Cache.put(t, "key3", %{"foo" => "bar"}, 10)
      assert :ets.info(t)[:size] == 3
      Cache.reset(t)
      assert :ets.info(t)[:size] == 0
    end
  end
end
