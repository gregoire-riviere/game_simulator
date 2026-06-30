defmodule GameSimulator.DatabaseTest do
  use ExUnit.Case, async: false

  alias GameSimulator.Database

  setup do
    previous_auth = Application.get_env(:game_simulator, :auth)
    data_directory = Path.join(System.tmp_dir!(), "game-simulator-db-test-#{System.unique_integer([:positive])}")

    Application.put_env(:game_simulator, :auth,
      data_directory: data_directory,
      legacy_users_file: Path.join(data_directory, "users"),
      token_ttl_seconds: 86_400
    )

    on_exit(fn ->
      File.rm_rf(data_directory)
      Application.put_env(:game_simulator, :auth, previous_auth)
    end)

    {:ok, data_directory: data_directory}
  end

  test "ensure! creates the sqlite database in the data directory", %{data_directory: data_directory} do
    assert :ok = Database.ensure!()

    assert File.regular?(Path.join(data_directory, "game_simulator.sqlite3"))
  end

  test "ensure! creates the users table" do
    assert :ok = Database.ensure!()

    assert {:ok, [["users"]]} =
             Database.with_connection(fn conn ->
               Database.query(conn, "SELECT name FROM sqlite_master WHERE type = 'table' AND name = ?", ["users"])
             end)
  end

  test "ensure! creates login lock columns" do
    assert :ok = Database.ensure!()

    assert {:ok, rows} =
             Database.with_connection(fn conn ->
               Database.query(conn, "PRAGMA table_info(users)")
             end)

    columns = Enum.map(rows, &Enum.at(&1, 1))
    assert "failed_login_count" in columns
    assert "locked_until" in columns
  end
end
