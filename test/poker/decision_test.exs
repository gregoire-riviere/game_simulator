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
    assert Poker.Decision.made_hand_category([{"A", "hearts"}, {"8", "clubs"}], [{"K", "clubs"}, {"7", "diamonds"}, {"2", "spades"}]) == :ace_high
    assert Poker.Decision.hand_strength_category(:ace_high) == :ace_high
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

  test "does not fold QQ+ or AK against a four bet" do
    profile = %{Poker.Profile.new(1) | archetype: :tag, three_bet: 0}

    context = %{
      phase: :preflop,
      cards: [{"A", "hearts"}, {"K", "clubs"}],
      position: :button,
      to_call: 36,
      stack: 200,
      effective_stack: 200,
      current_bet: 38,
      preflop_raise_count: 3,
      big_blind: 2,
      pot: 80,
      pot_odds: 0.35,
      bet_size_ratio: 0.0,
      stack_pressure: 0.26,
      actions: [:call, :fold, %{raise_to: %{min: 90, max: 200}}, :all_in]
    }

    Enum.each(1..30, fn _attempt ->
      refute Poker.Decision.preflop(profile, context) == :fold
    end)
  end

  test "river sanity guard discourages expensive weak calls and raises" do
    profile = %{Poker.Profile.new(1) | archetype: :tag}
    probabilities = %{raise: 0.10, call: 0.45, fold: 0.45}
    context = %{phase: :river, to_call: 30, bet_size_ratio: 1.0}

    guarded = Poker.Decision.apply_river_sanity_guard(probabilities, profile, :air, :none, context)

    assert guarded.raise < probabilities.raise
    assert guarded.call < probabilities.call
    assert guarded.fold > probabilities.fold
  end

  test "late street price guard folds weak hands more against large bets" do
    probabilities = %{raise: 0.10, call: 0.45, fold: 0.45}
    context = %{phase: :turn, to_call: 30, bet_size_ratio: 0.66}

    guarded = Poker.Decision.apply_late_street_price_guard(probabilities, :medium, context)

    assert guarded.raise < probabilities.raise
    assert guarded.call < probabilities.call
    assert guarded.fold > probabilities.fold
  end

  test "river air bluff frequency depends on profile" do
    probabilities = %{bet: 0.10, check: 0.90}
    context = %{phase: :river, to_call: 0, pot: 60}
    tag = %{Poker.Profile.new(1) | archetype: :tag}
    spewy = %{Poker.Profile.new(1) | archetype: :spewy_aggro}

    tag_guarded = Poker.Decision.apply_river_sanity_guard(probabilities, tag, :air, :none, context)
    spewy_guarded = Poker.Decision.apply_river_sanity_guard(probabilities, spewy, :air, :none, context)

    assert tag_guarded.bet < spewy_guarded.bet
    assert tag_guarded.bet < probabilities.bet
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
