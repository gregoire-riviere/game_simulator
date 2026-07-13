defmodule Belote.GameTest do
  use ExUnit.Case, async: true

  alias Belote.Game

  test "classic deal gives eight cards to every player after a take" do
    state = Game.new(:classic, 1000)
    suit = elem(state.turned_card, 0)
    {:ok, state} = Game.act(state, state.turn, {:take, suit})

    assert state.phase == :playing
    assert Enum.all?(state.hands, fn {_seat, cards} -> length(cards) == 8 end)
    assert Enum.count(Enum.flat_map(state.hands, fn {_seat, cards} -> cards end)) == 32
  end

  test "a player must follow suit when possible" do
    state = %{
      Game.new(:classic, 1000)
      | phase: :playing,
        trump: :hearts,
        turn: 2,
        trick: [%{seat: 1, card: {:clubs, :ace}}],
        hands: %{1 => [], 2 => [{:clubs, :seven}, {:hearts, :jack}], 3 => [], 4 => []}
    }

    assert Game.legal_actions(state, 2) == [{:play, {:clubs, :seven}}]
  end

  test "a player cuts when void in the lead suit and opponents win" do
    state = %{
      Game.new(:classic, 1000)
      | phase: :playing,
        trump: :hearts,
        turn: 2,
        trick: [%{seat: 1, card: {:clubs, :ace}}],
        hands: %{1 => [], 2 => [{:hearts, :seven}, {:spades, :ace}], 3 => [], 4 => []}
    }

    assert Game.legal_actions(state, 2) == [{:play, {:hearts, :seven}}]
  end

  test "trump jack beats trump nine" do
    assert Game.beats?({:hearts, :jack}, {:hearts, :nine}, :clubs, :hearts)
    refute Game.beats?({:hearts, :nine}, {:hearts, :jack}, :clubs, :hearts)
  end

  test "coinche adds the contract and multiplier when the taker succeeds" do
    state = %{
      Game.new(:coinche, 1000)
      | contract: %{team: 0, amount: 100, multiplier: 2, taker: 4, suit: :hearts},
        deal_points: %{0 => 102, 1 => 60},
        tricks: %{0 => [], 1 => []}
    }

    assert Game.score_deal(state) == %{0 => 404, 1 => 120}
  end

  test "public card text accepts the absence of a turned card after a take" do
    assert Belote.Table.card_text(nil) == nil
  end

  test "a completed deal records its match winner without requiring prior state" do
    state = %{
      Game.new(:classic, 501)
      | contract: %{team: 0, amount: 82, multiplier: 1, taker: 4},
        deal_points: %{0 => 162, 1 => 0},
        tricks: %{0 => [], 1 => []}
    }

    {:ok, result} = Game.finish_deal(Map.delete(state, :match_winner))

    assert result.phase == :deal_finished
    assert result.match_winner == nil
  end

  test "a completed deal can finish the match" do
    state = %{
      Game.new(:classic, 501)
      | scores: %{0 => 400, 1 => 0},
        contract: %{team: 0, amount: 82, multiplier: 1, taker: 4},
        deal_points: %{0 => 162, 1 => 0},
        tricks: %{0 => [], 1 => []}
    }

    {:ok, result} = Game.finish_deal(state)

    assert result.phase == :match_finished
    assert result.match_winner == 0
  end

  test "a completed deal keeps its taker, winner and scored points" do
    state = %{
      Game.new(:classic, 1000)
      | contract: %{team: 0, amount: 82, multiplier: 1, taker: 4},
        trump: :hearts,
        deal_points: %{0 => 100, 1 => 62},
        tricks: %{0 => [], 1 => []}
    }

    {:ok, result} = Game.finish_deal(state)

    assert [%{taker: 4, trump: :hearts, winner_team: 0, scores: %{0 => 100, 1 => 62}}] = result.deal_history
  end

  test "public cards are sorted heart, spade, diamond, club then natural rank" do
    cards = [{:hearts, :seven}, {:clubs, :king}, {:clubs, :ace}, {:diamonds, :ten}]

    assert Belote.Table.sort_cards(cards) == [{:hearts, :seven}, {:diamonds, :ten}, {:clubs, :king}, {:clubs, :ace}]
  end

  test "first and second auction passes have distinct public statuses" do
    game = %{Game.new(:classic, 1000) | phase: :classic_second, history: [%{seat: 1, action: :pass, phase: :classic_first}, %{seat: 2, action: :pass, phase: :classic_second}]}

    assert Belote.Table.pass_status(game, 1) == :folded
    assert Belote.Table.pass_status(game, 2) == :second_round
  end

  test "bot keeps its expensive cards when its partner already wins the trick" do
    state = %{
      Game.new(:classic, 1000)
      | phase: :playing,
        trump: :hearts,
        turn: 3,
        trick: [%{seat: 1, card: {:clubs, :ace}}],
        hands: %{1 => [], 2 => [], 3 => [{:diamonds, :seven}, {:hearts, :jack}, {:spades, :ace}], 4 => []}
    }

    assert Belote.Decision.decide(state, 3) == {:play, {:diamonds, :seven}}
  end

  test "bot uses the cheapest card that can win a trick" do
    state = %{
      Game.new(:classic, 1000)
      | phase: :playing,
        trump: :hearts,
        turn: 2,
        trick: [%{seat: 1, card: {:clubs, :queen}}],
        hands: %{1 => [], 2 => [{:clubs, :king}, {:clubs, :ace}], 3 => [], 4 => []}
    }

    assert Belote.Decision.decide(state, 2) == {:play, {:clubs, :king}}
  end

  test "bot cashes an ace when leading without a trump draw" do
    state = %{
      Game.new(:classic, 1000)
      | phase: :playing,
        trump: :hearts,
        contract: %{team: 1, amount: 82, multiplier: 1, taker: 1},
        turn: 1,
        trick: [],
        hands: %{1 => [{:clubs, :seven}, {:diamonds, :ace}, {:hearts, :jack}], 2 => [], 3 => [], 4 => []}
    }

    assert Belote.Decision.decide(state, 1) == {:play, {:diamonds, :ace}}
  end
end
