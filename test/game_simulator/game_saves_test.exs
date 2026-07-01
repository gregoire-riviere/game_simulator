defmodule GameSimulator.GameSavesTest do
  use ExUnit.Case, async: false

  alias GameSimulator.{Database, GameSaves}

  setup do
    previous_auth = Application.get_env(:game_simulator, :auth)
    data_directory = Path.join(System.tmp_dir!(), "game-simulator-saves-test-#{System.unique_integer([:positive])}")

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

  test "stores and replaces one save per user and game key" do
    assert {:ok, false} = GameSaves.exists?("alice", "poker:cash_nl2")
    assert :ok = GameSaves.put("alice", "poker:cash_nl2", %{hand_number: 1})
    assert {:ok, true} = GameSaves.exists?("alice", "poker:cash_nl2")
    assert {:ok, %{hand_number: 1}} = GameSaves.get("alice", "poker:cash_nl2")

    assert :ok = GameSaves.put("alice", "poker:cash_nl2", %{hand_number: 2})
    assert {:ok, %{hand_number: 2}} = GameSaves.get("alice", "poker:cash_nl2")
  end

  test "separates users and game keys" do
    assert :ok = GameSaves.put("alice", "poker:cash_nl2", %{owner: "alice"})
    assert :ok = GameSaves.put("alice", "poker:other", %{game: "other"})
    assert :ok = GameSaves.put("bob", "poker:cash_nl2", %{owner: "bob"})

    assert {:ok, %{owner: "alice"}} = GameSaves.get("alice", "poker:cash_nl2")
    assert {:ok, %{game: "other"}} = GameSaves.get("alice", "poker:other")
    assert {:ok, %{owner: "bob"}} = GameSaves.get("bob", "poker:cash_nl2")
  end

  test "deletes only the requested save" do
    assert :ok = GameSaves.put("alice", "poker:cash_nl2", %{owner: "alice"})
    assert :ok = GameSaves.put("bob", "poker:cash_nl2", %{owner: "bob"})

    assert :ok = GameSaves.delete("alice", "poker:cash_nl2")
    assert {:error, :not_found} = GameSaves.get("alice", "poker:cash_nl2")
    assert {:ok, %{owner: "bob"}} = GameSaves.get("bob", "poker:cash_nl2")
  end

  test "does not report an unreadable save as resumable" do
    assert :ok =
             Database.with_connection(fn conn ->
               Database.run(
                 conn,
                 "INSERT INTO game_saves (username, game_key, payload, version, inserted_at, updated_at) VALUES (?, ?, ?, ?, ?, ?)",
                 ["alice", "poker:cash_nl2", "not-a-term", 1, "2026-01-01T00:00:00Z", "2026-01-01T00:00:00Z"]
               )
             end)

    assert {:ok, false} = GameSaves.exists?("alice", "poker:cash_nl2")
  end
end
