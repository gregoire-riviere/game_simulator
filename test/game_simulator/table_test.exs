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
end
