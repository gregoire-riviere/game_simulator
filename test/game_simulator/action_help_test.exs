defmodule GameSimulator.ActionHelpTest do
  use ExUnit.Case, async: true

  test "explains checking when the human player has nothing to call" do
    {:ok, table} = GameSimulator.Table.start_link(owner: "alice")
    set_betting_state(table, current_bet: 0, hero_street: 0, hero_stack: 200)

    assert {:ok, state} = GameSimulator.Table.state(table, "alice")

    assert state.action_help == %{
             message: "Vous pouvez checker pour rester dans le coup sans miser.",
             dismissible: true
           }
  end

  test "shows the exact amount needed to call and keeps help hidden after dismissal" do
    {:ok, table} = GameSimulator.Table.start_link(owner: "alice")
    set_betting_state(table, current_bet: 10, hero_street: 2, hero_stack: 198)

    assert {:ok, state} = GameSimulator.Table.state(table, "alice")
    assert state.action_help.message == "Suivre coûte 8 jetons."

    assert {:ok, dismissed} = GameSimulator.Table.dismiss_action_help(table, "alice")
    assert dismissed.action_help == nil
    assert {:ok, restored} = GameSimulator.Table.state(table, "alice")
    assert restored.action_help == nil
  end

  def set_betting_state(table, options) do
    table_state = :sys.get_state(table)
    hero = table_state.human_id
    villain = {:bot, 1}
    current_bet = Keyword.fetch!(options, :current_bet)
    hero_street = Keyword.fetch!(options, :hero_street)
    hero_stack = Keyword.fetch!(options, :hero_stack)

    :sys.replace_state(table_state.game, fn game ->
      %{
        game
        | phase: :flop,
          players: %{
            hero => %{id: hero, seat: 6, stack: hero_stack},
            villain => %{id: villain, seat: 1, stack: 200 - current_bet}
          },
          hole_cards: %{
            hero => [{"A", "spades"}, {"K", "spades"}],
            villain => [{"2", "clubs"}, {"7", "diamonds"}]
          },
          hand_players: MapSet.new([hero, villain]),
          folded: MapSet.new(),
          all_in: MapSet.new(),
          pending: MapSet.new([hero]),
          street_contributions: %{hero => hero_street, villain => current_bet},
          hand_contributions: %{hero => hero_street, villain => current_bet},
          current_bet: current_bet,
          min_raise: 2,
          active_player: hero,
          dealer: villain
      }
    end)
  end
end
