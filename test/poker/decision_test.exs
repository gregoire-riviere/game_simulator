defmodule Poker.DecisionTest do
  use ExUnit.Case, async: true

  test "always returns an action accepted by the game engine" do
    {:ok, game} = Poker.Game.start_link(small_blind: 1, big_blind: 2)
    {:ok, _player} = Poker.Game.join(game, :one, 200, 1)
    {:ok, _player} = Poker.Game.join(game, :two, 200, 2)
    {:ok, _state} = Poker.Game.start_hand(game)
    {:ok, context} = Poker.Game.decision_context(game, :one)
    action = Poker.Decision.decide(Poker.Profile.new(1), context)

    assert {:ok, _state} = Poker.Game.act(game, :one, action)
  end

  test "normalizes hands and uses combo-weighted preflop ranges" do
    assert Poker.Decision.normalize_hand([{"A", "clubs"}, {"K", "clubs"}]) == "AKs"
    assert Poker.Decision.normalize_hand([{"10", "clubs"}, {"10", "hearts"}]) == "TT"
    assert Poker.Decision.in_top_percent?([{"A", "clubs"}, {"A", "hearts"}], 1)
    refute Poker.Decision.in_top_percent?([{"7", "clubs"}, {"2", "hearts"}], 10)
    assert Poker.Decision.effective_rate(24, :button) > Poker.Decision.effective_rate(24, :early)
  end

  test "sizes postflop bets from the pot instead of the remaining stack" do
    profile = Map.put(Poker.Profile.new(1), :weird_sizing_frequency, 0.0)
    context = %{pot: 100, current_bet: 0}

    assert Poker.Decision.sizing(%{min: 2, max: 1_000}, profile, context, :bet) <= 150
  end

  test "detects the main drawing situations" do
    assert Poker.Decision.draw_category([{"A", "hearts"}, {"K", "hearts"}], [{"7", "hearts"}, {"2", "hearts"}, {"9", "clubs"}]) == :flush_draw
    assert Poker.Decision.draw_category([{"8", "clubs"}, {"9", "hearts"}], [{"10", "spades"}, {"J", "diamonds"}, {"2", "clubs"}]) == :open_ended
    assert Poker.Decision.draw_category([{"8", "clubs"}, {"10", "hearts"}], [{"J", "spades"}, {"Q", "diamonds"}, {"3", "clubs"}]) == :gutshot
    assert Poker.Decision.draw_category([{"A", "hearts"}, {"K", "hearts"}], [{"Q", "hearts"}, {"J", "hearts"}, {"2", "clubs"}]) == :combo_draw
  end

  test "classifies made hands with hole-card relevance" do
    board = [{"A", "clubs"}, {"7", "diamonds"}, {"2", "spades"}]

    assert Poker.Decision.made_hand_category([{"K", "clubs"}, {"K", "hearts"}], board) == :underpair
    assert Poker.Decision.made_hand_category([{"A", "hearts"}, {"K", "hearts"}], board) == :top_pair_good_kicker
    assert Poker.Decision.made_hand_category([{"Q", "hearts"}, {"J", "hearts"}], [{"9", "clubs"}, {"9", "diamonds"}, {"2", "spades"}]) == :board_pair
    assert Poker.Decision.hand_strength_category(:board_pair) == :air
  end

  test "does not overvalue made hands mostly carried by the board" do
    assert Poker.Decision.made_hand_category([{"A", "clubs"}, {"K", "hearts"}], [{"9", "clubs"}, {"9", "diamonds"}, {"9", "spades"}]) == :board_trips

    assert Poker.Decision.made_hand_category(
             [{"A", "clubs"}, {"K", "hearts"}],
             [{"9", "clubs"}, {"9", "diamonds"}, {"9", "spades"}, {"2", "clubs"}, {"2", "diamonds"}]
           ) == :plays_board

    assert Poker.Decision.made_hand_category(
             [{"A", "clubs"}, {"K", "hearts"}],
             [{"9", "clubs"}, {"9", "diamonds"}, {"9", "spades"}, {"9", "hearts"}, {"2", "diamonds"}]
           ) == :board_quads

    assert Poker.Decision.made_hand_category(
             [{"A", "clubs"}, {"K", "hearts"}],
             [{"10", "clubs"}, {"J", "diamonds"}, {"Q", "spades"}, {"2", "clubs"}, {"3", "diamonds"}]
           ) == :straight

    assert Poker.Decision.made_hand_category(
             [{"7", "clubs"}, {"8", "hearts"}],
             [{"10", "clubs"}, {"J", "diamonds"}, {"Q", "spades"}, {"K", "clubs"}, {"A", "diamonds"}]
           ) == :plays_board

    assert Poker.Decision.hand_strength_category(:plays_board) == :air
    assert Poker.Decision.hand_strength_category(:board_quads) == :strong
  end

  test "preflop situation and call chance react to all-in pressure" do
    profile = %{Poker.Profile.new(1) | archetype: :tag, call_too_wide: false}
    cheap = %{pot_odds: 0.10, bet_size_ratio: 0.10, stack_pressure: 0.05}
    expensive = %{pot_odds: 0.45, bet_size_ratio: 1.50, stack_pressure: 1.00}

    assert Poker.Decision.preflop_call_chance(profile, cheap) > Poker.Decision.preflop_call_chance(profile, expensive)
    assert Poker.Decision.preflop_situation(%{to_call: 50, stack: 50, current_bet: 50, big_blind: 2}) == :facing_all_in
  end

  test "returns only legal postflop action types across weighted draws" do
    profile = Poker.Profile.new(1)

    context = %{
      phase: :flop,
      cards: [{"A", "hearts"}, {"K", "hearts"}],
      board: [{"Q", "hearts"}, {"J", "hearts"}, {"2", "clubs"}],
      pot: 12,
      current_bet: 0,
      to_call: 0,
      facing_cbet: false,
      actions: [:check, %{bet: %{min: 2, max: 100}}]
    }

    Enum.each(1..50, fn _attempt ->
      case Poker.Decision.decide(profile, context) do
        :check -> assert true
        {:bet, amount} -> assert amount in 2..18
      end
    end)
  end
end
