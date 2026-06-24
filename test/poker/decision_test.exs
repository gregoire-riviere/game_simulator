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
end
