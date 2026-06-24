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
end
