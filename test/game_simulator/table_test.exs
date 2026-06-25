defmodule GameSimulator.TableTest do
  use ExUnit.Case, async: true

  test "keeps bot profiles and hole cards private" do
    {:ok, table} = GameSimulator.Table.start_link(owner: "alice")
    assert {:ok, state} = GameSimulator.Table.state(table, "alice")

    assert length(state.players) == 6
    assert length(Enum.find(state.players, &(&1.id == "hero")).cards) == 2
    assert Enum.all?(Enum.reject(state.players, &(&1.id == "hero")), &(&1.cards == :hidden))
    refute Map.has_key?(state, :profiles)
    assert {:error, :forbidden} = GameSimulator.Table.state(table, "mallory")
  end

  test "advances one bot action at a time" do
    {:ok, table} = GameSimulator.Table.start_link(owner: "alice")
    assert {:ok, initial} = GameSimulator.Table.state(table, "alice")
    refute initial.hero_turn

    assert {:ok, advanced} = GameSimulator.Table.advance_bot(table, "alice")
    assert length(advanced.recent_actions) == 1
    assert {:error, :forbidden} = GameSimulator.Table.advance_bot(table, "mallory")
  end

  test "does not start a new hand when the hero has no chips" do
    {:ok, table} = GameSimulator.Table.start_link(owner: "alice")
    state = :sys.get_state(table)

    :sys.replace_state(state.game, fn game ->
      put_in(game.players[state.human_id].stack, 0)
    end)

    assert {:error, :hero_busted} = GameSimulator.Table.next_hand(table, "alice")
  end

  test "keeps a busted bot profile when that bot did not play the last hand" do
    {:ok, table} = GameSimulator.Table.start_link(owner: "alice")
    state = :sys.get_state(table)
    busted_bot = {:bot, 1}

    :sys.replace_state(state.game, fn game ->
      players = Map.delete(game.players, busted_bot)

      hand = %{
        dealer: state.human_id,
        board: [],
        winners: [state.human_id],
        players: Map.new(players, fn {id, _player} -> {id, %{profit_loss: 0, result: :folded}} end)
      }

      %{game | history: [hand], phase: :waiting}
    end)

    updated = GameSimulator.Table.update_profiles(state, %{phase: :waiting})

    assert Map.fetch!(updated.profiles, busted_bot) == Map.fetch!(state.profiles, busted_bot)
  end

  test "supervised tables are temporary and do not restart as fresh tables after a crash" do
    owner = "crash-user-#{System.unique_integer([:positive])}"
    {:ok, table} = GameSimulator.Tables.start(owner)
    monitor = Process.monitor(table)

    Process.exit(table, :kill)

    assert_receive {:DOWN, ^monitor, :process, ^table, :killed}, 1_000
    assert :error = GameSimulator.Tables.table(owner)
  end
end
