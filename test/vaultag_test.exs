defmodule VaultagTest do
  use ExUnit.Case

  @moduletag :capture_log

  setup_all do
    start_supervised!(Vaultag, [])
    :ok
  end

  describe "write/3" do
    test "writes a value to the vault" do
      value = %{"foo" => "bar"}
      assert {:ok, %{"value" => ^value}} = Vaultag.write("kv/my-secret", value)
    end
  end

  describe "list/2" do
    test "lists the secrets" do
      assert {:ok, %{"keys" => ["my-secret"]}} == Vaultag.list("kv")
    end
  end

  describe "read/2" do
    test "reads a value from the vault" do
      value = %{"foo" => "bar"}
      assert {:ok, ^value} = Vaultag.read("kv/my-secret")
      assert {:ok, %{"data" => ^value}} = Vaultag.read("kv/my-secret", full_response: true)
    end

    test "caches the previously read value" do
      path = "kv/my-secret"
      res = {:ok, %{"foo" => "bar"}}
      key = {path, []}
      Vaultag.read(path, cache: true)
      assert [{key, ^res}] = :ets.lookup(:vaultag, key)
    end
  end

  describe "request/3" do
    test "make an HTTP request" do
      assert {:ok, %{"data" => %{"foo" => "bar"}}} = Vaultag.request(:get, "kv/my-secret")
    end
  end

  describe "delete/2" do
    test "deletes a value from the vault" do
      assert {:ok, _} = Vaultag.delete("kv/my-secret")
      assert {:error, ["Key not found"]} == Vaultag.list("kv")
    end
  end

  test "renews the auth token" do
    assert {:ok, _} = Vaultag.write("kv/my-secret", %{foo: "bar"})
    # wait until the token expires, it has 5s TTL
    Process.sleep(5000)
    assert {:ok, _} = Vaultag.read("kv/my-secret")
  end
end
