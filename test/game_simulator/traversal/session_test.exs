defmodule GameSimulator.Traversal.SessionTest do
  use ExUnit.Case, async: true
  alias GameSimulator.Traversal.{Session, Game}

  test "temporary sessions isolate users, reject illegal/stale moves, replace games atomically" do
    user = "traversal-test-#{System.unique_integer([:positive])}"
    other = "traversal-other-#{System.unique_integer([:positive])}"
    heights = List.duplicate(List.duplicate(0, 10), 10)
    {:ok, pid} = Session.server(user)
    {:ok, other_pid} = Session.server(other)
    on_exit(fn ->
      for p <- [pid, other_pid], Process.alive?(p), do: DynamicSupervisor.terminate_child(GameSimulator.TableSupervisor, p)
    end)
    assert {:error, :invalid_game} = Session.request(user, {:new, heights, "llm"})
    assert {:ok, %{game: nil}} = Session.request(other, :get)
    {:ok, initial} = Session.request(user, {:new, heights, "easy", "test-seed"})
    assert initial.seed == "test-seed"
    [move | _] = initial.legal
    params = %{"game_id" => initial.game_id, "revision" => initial.revision, "piece" => move.piece, "row" => move.row, "col" => move.col}
    assert {:error, :no_game} = Session.request(other, {:move, params})
    assert {:error, :illegal_move} = Session.request(user, {:move, %{params | "row" => 99}})
    assert {:ok, after_human} = Session.request(user, {:move, params})
    assert after_human.game.moves == 1
    assert {:error, :stale_game} = Session.request(user, {:move, params})
    # The bot message is processed before this call: one and only one legal reply.
    {:ok, after_bot} = Session.request(user, :get)
    assert after_bot.game.moves == 2
    assert after_bot.game.turn == 1
    assert after_bot.revision == 2
    assert Game.actions(after_bot.game) == after_bot.legal
    {:ok, replacement} = Session.request(user, {:new, heights, "hard"})
    refute replacement.game_id == initial.game_id
    assert replacement.game.moves == 0
    assert {:error, :stale_game} = Session.request(user, {:move, params})
  end

  test "queued bot cannot act after victory or on a replaced game" do
    user = "traversal-queue-#{System.unique_integer([:positive])}"
    {:ok, pid} = Session.server(user)
    on_exit(fn -> if Process.alive?(pid), do: DynamicSupervisor.terminate_child(GameSimulator.TableSupervisor, pid) end)
    heights = List.duplicate(List.duplicate(0, 10), 10)
    {:ok, state} = Session.request(user, {:new, heights, "easy"})
    send(pid, {:bot, "old-game", 0})
    send(pid, {:bot, state.game_id, 99})
    assert {:ok, %{revision: 0}} = Session.request(user, :get)
    :sys.replace_state(pid, fn current -> %{current | game: %{current.game | turn: 2, result: %{winner: 1, reason: "test"}}} end)
    send(pid, {:bot, state.game_id, 0})
    {:ok, final} = Session.request(user, :get)
    assert final.game.moves == 0
    assert final.game.result.winner == 1
  end
end
