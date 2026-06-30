defmodule GameSimulatorWeb.UsersTest do
  use ExUnit.Case, async: false

  alias GameSimulatorWeb.Users

  setup do
    previous_auth = Application.get_env(:game_simulator, :auth)
    data_directory = Path.join(System.tmp_dir!(), "game-simulator-users-test-#{System.unique_integer([:positive])}")

    Application.put_env(:game_simulator, :auth,
      data_directory: data_directory,
      legacy_users_file: Path.join(data_directory, "legacy-users"),
      token_ttl_seconds: 86_400
    )

    on_exit(fn ->
      File.rm_rf(data_directory)
      Application.put_env(:game_simulator, :auth, previous_auth)
    end)

    {:ok, data_directory: data_directory}
  end

  test "creates and authenticates a sqlite user" do
    assert :ok = Users.add("alice", "a-long-test-password", ["poker", "llm"])
    assert {:ok, "alice"} = Users.authenticate("alice", "a-long-test-password")
    assert {:error, :invalid_credentials} = Users.authenticate("alice", "wrong-password")

    assert {:ok, %{permissions: ["poker", "llm"]}} = Users.get("alice")
  end

  test "validates permissions against the allowlist" do
    assert {:error, :invalid_permissions} = Users.add("alice", "a-long-test-password", ["poker", "root"])
    assert {:error, :not_found} = Users.get("alice")
  end

  test "changes password with the current password" do
    assert :ok = Users.add("alice", "a-long-test-password", ["poker"])
    assert :ok = Users.change_password("alice", "a-long-test-password", "a-new-long-password")
    assert {:error, :invalid_credentials} = Users.authenticate("alice", "a-long-test-password")
    assert {:ok, "alice"} = Users.authenticate("alice", "a-new-long-password")
  end

  test "locks any user after five failed logins and unlocks from console" do
    assert :ok = Users.add("admin", "a-long-test-password", ["admin"])

    for _attempt <- 1..4 do
      assert {:error, :invalid_credentials} = Users.authenticate("admin", "wrong-password")
    end

    assert {:error, {:locked, locked_until}} = Users.authenticate("admin", "wrong-password")
    assert is_binary(locked_until)
    assert {:error, {:locked, ^locked_until}} = Users.authenticate("admin", "a-long-test-password")

    assert :ok = Users.unlock("admin")
    assert {:ok, "admin"} = Users.authenticate("admin", "a-long-test-password")
  end

  test "explains password change failures" do
    assert :ok = Users.add("alice", "a-long-test-password", ["poker"])
    assert {:error, :invalid_current_password} = Users.change_password("alice", "wrong-password", "a-new-long-password")
    assert {:error, :invalid_new_password} = Users.change_password("alice", "a-long-test-password", "short")
    assert {:error, :missing_current_password} = Users.change_password("alice", nil, "a-new-long-password")
    assert {:error, :missing_new_password} = Users.change_password("alice", "a-long-test-password", nil)
  end

  test "protects the last admin" do
    assert :ok = Users.add("admin", "a-long-test-password", ["admin"])

    assert {:error, :last_admin} = Users.update("admin", ["poker"])
    assert {:error, :last_admin} = Users.delete("admin")

    assert :ok = Users.add("second-admin", "a-long-test-password", ["admin"])
    assert :ok = Users.update("admin", ["poker"])
  end

  test "imports legacy users as admins once", %{data_directory: data_directory} do
    record = Users.password_record("a-long-test-password")
    legacy = Path.join(data_directory, "legacy-users")
    File.mkdir_p!(data_directory)
    File.write!(legacy, "legacy:#{record.iterations}:#{record.salt}:#{record.password_hash}\n")

    assert :ok = Users.ensure!()
    assert {:ok, %{permissions: ["admin"]}} = Users.get("legacy")
    assert {:ok, "legacy"} = Users.authenticate("legacy", "a-long-test-password")

    File.write!(legacy, "other:#{record.iterations}:#{record.salt}:#{record.password_hash}\n")
    assert :ok = Users.ensure!()
    assert {:error, :not_found} = Users.get("other")
  end
end
