defmodule Mix.Tasks.User.ResetPasswordTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  alias GameSimulatorWeb.Users
  alias Mix.Tasks.User.ResetPassword

  setup do
    previous_auth = Application.get_env(:game_simulator, :auth)
    data_directory = Path.join(System.tmp_dir!(), "game-simulator-password-task-test-#{System.unique_integer([:positive])}")

    Application.put_env(:game_simulator, :auth,
      data_directory: data_directory,
      legacy_users_file: Path.join(data_directory, "legacy-users"),
      token_ttl_seconds: 86_400
    )

    on_exit(fn ->
      File.rm_rf(data_directory)
      Application.put_env(:game_simulator, :auth, previous_auth)
    end)

    :ok
  end

  test "resets an existing user's password" do
    assert :ok = Users.add("alice", "a-long-test-password", ["poker"])
    assert :ok = ResetPassword.reset("alice", "a-new-long-password", "a-new-long-password")
    assert {:ok, "alice"} = Users.authenticate("alice", "a-new-long-password")
  end

  test "rejects a different confirmation" do
    assert {:error, :confirmation_mismatch} = ResetPassword.reset("alice", "a-new-long-password", "another-long-password")
  end

  test "reads a visible password when requested" do
    warning =
      capture_io(:stderr, fn ->
        capture_io("a-visible-password\n", fn ->
          assert ResetPassword.read_visible_password() == "a-visible-password"
        end)
      end)

    assert warning =~ "saisie masquée indisponible"
  end
end
