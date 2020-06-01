defmodule VaultagTest do
  use ExUnit.Case

  @moduletag :capture_log

  setup do
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
      assert {:ok, %{"keys" => _}} = Vaultag.list("kv")
    end
  end

  describe "read/2" do
    test "reads a value from the vault" do
      value = %{"foo" => "bar"}
      Vaultag.write("kv/my-secret", value)
      assert {:ok, ^value} = Vaultag.read("kv/my-secret")
      assert {:ok, %{"data" => ^value}} = Vaultag.read("kv/my-secret", full_response: true)
    end
  end

  describe "request/3" do
    test "make an HTTP request" do
      Vaultag.write("kv/my-secret", %{"foo" => "bar"})
      assert {:ok, %{"data" => %{"foo" => "bar"}}} = Vaultag.request(:get, "kv/my-secret")
    end
  end

  describe "delete/2" do
    test "deletes a value from the vault" do
      assert {:ok, _} = Vaultag.delete("kv/my-secret")
      assert {:error, ["Key not found"]} == Vaultag.list("kv")
    end
  end

  describe "read_dynamic/2" do
    test "caches the dynamic secret for a time of its lease duration" do
      {:ok, resp} = Vaultag.read_dynamic("rabbitmq/creds/admin")

      assert {:ok, ^resp} = Vaultag.read_dynamic("rabbitmq/creds/admin")

      assert {:ok, %{"data" => ^resp}} =
               Vaultag.read_dynamic("rabbitmq/creds/admin", full_response: true)
    end

    test "renews the lease when it is possible" do
      {:ok, resp1} = Vaultag.read_dynamic("rabbitmq/creds/admin", full_response: true)
      # lease ttl is 3s, see setup.sh
      Process.sleep(3500)
      {:ok, resp2} = Vaultag.read_dynamic("rabbitmq/creds/admin", full_response: true)
      assert resp2["data"] == resp1["data"]
      assert resp2["lease_id"] == resp1["lease_id"]
      assert resp2["request_id"] != resp1["request_id"]
    end

    test "invalidates the expired cached value" do
      {:ok, resp1} = Vaultag.read_dynamic("rabbitmq/creds/admin")
      # lease max_ttl is 5s, see setup.sh
      Process.sleep(5500)
      {:ok, resp2} = Vaultag.read_dynamic("rabbitmq/creds/admin")
      assert resp2 != resp1
      assert {:ok, ^resp2} = Vaultag.read_dynamic("rabbitmq/creds/admin")
    end
  end

  test "renews the auth token" do
    assert {:ok, _} = Vaultag.write("kv/my-secret", %{foo: "bar"})
    # token_ttl is 3s, see setup.sh
    Process.sleep(3500)
    assert {:ok, _} = Vaultag.read("kv/my-secret")
  end

  test "re-authenticates when the auth token expires" do
    assert {:ok, _} = Vaultag.write("kv/my-secret", %{foo: "bar"})
    # token_max_ttl is 8s, see setup.sh
    Process.sleep(8500)
    assert {:ok, _} = Vaultag.read("kv/my-secret")
  end
end
