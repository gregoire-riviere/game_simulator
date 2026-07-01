defmodule GameSimulator.TablesSaveTest do
  use ExUnit.Case, async: false

  alias GameSimulator.{Database, GameSaves, Tables}

  setup do
    previous_auth = Application.get_env(:game_simulator, :auth)
    data_directory = Path.join(System.tmp_dir!(), "game-simulator-tables-save-test-#{System.unique_integer([:positive])}")

    Application.put_env(:game_simulator, :auth,
      data_directory: data_directory,
      legacy_users_file: Path.join(data_directory, "users"),
      token_ttl_seconds: 86_400
    )

    :ok = Database.ensure!()

    on_exit(fn ->
      File.rm_rf(data_directory)
      Application.put_env(:game_simulator, :auth, previous_auth)
    end)

    :ok
  end

  test "start_new overwrites the unique save" do
    owner = "new-save-#{System.unique_integer([:positive])}"
    assert :ok = GameSaves.put(owner, "poker:cash_nl2", %{old: true})
    assert {:ok, _table} = Tables.start_new(owner)

    assert wait_until(fn ->
             case GameSaves.get(owner, "poker:cash_nl2") do
               {:ok, %{game_state: %{hand_number: 1}}} -> true
               _other -> false
             end
           end)

    assert :ok = Tables.stop(owner)
  end

  test "resume treats an unreadable save as missing" do
    owner = "bad-save-#{System.unique_integer([:positive])}"

    assert :ok =
             Database.with_connection(fn conn ->
               Database.run(
                 conn,
                 "INSERT INTO game_saves (username, game_key, payload, version, inserted_at, updated_at) VALUES (?, ?, ?, ?, ?, ?)",
                 [owner, "poker:cash_nl2", "not-a-term", 1, "2026-01-01T00:00:00Z", "2026-01-01T00:00:00Z"]
               )
             end)

    assert {:error, :not_found} = Tables.resume(owner)
    assert {:error, :not_found} = GameSaves.get(owner, "poker:cash_nl2")
  end

  def wait_until(fun), do: wait_until(fun, 20)

  def wait_until(fun, attempts) when attempts > 0 do
    if fun.() do
      true
    else
      Process.sleep(25)
      wait_until(fun, attempts - 1)
    end
  end

  def wait_until(_fun, 0), do: false
end
