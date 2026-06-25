defmodule Poker.GameTest do
  use ExUnit.Case, async: true

  test "reports the expected player and validates their action" do
    {:ok, game} = Poker.Game.start_link(small_blind: 1, big_blind: 2)
    assert {:ok, _player} = Poker.Game.join(game, :alice, 100, 1)
    assert {:ok, _player} = Poker.Game.join(game, :bob, 100, 2)
    assert {:ok, _state} = Poker.Game.start_hand(game)

    assert {:ok, %{player_id: :alice, actions: actions}} = Poker.Game.next_action(game)
    assert :call in actions
    assert {:error, :not_your_turn} = Poker.Game.act(game, :bob, :check)
    assert {:ok, state} = Poker.Game.act(game, :alice, :call)
    assert state.active_player == :bob
    assert {:ok, %{player_id: :bob, actions: actions}} = Poker.Game.next_action(game)
    assert :check in actions
  end

  test "starts in explicit elimination mode" do
    {:ok, game} = Poker.Game.start_link(small_blind: 1, big_blind: 2)

    assert Poker.Game.internal_state(game).mode == :elimination
  end

  test "tops up short stacks before a cash nl2 hand" do
    {:ok, game} = Poker.Game.start_link(small_blind: 1, big_blind: 2, mode: :cash_nl2, min_stack: 80, top_up_to: 200)
    assert {:ok, _player} = Poker.Game.join(game, :alice, 20, 1)
    assert {:ok, _player} = Poker.Game.join(game, :bob, 200, 2)
    assert {:ok, snapshot} = Poker.Game.start_hand(game)

    assert snapshot.mode == :cash_nl2
    assert snapshot.top_ups == %{alice: 180}
    assert Poker.Game.internal_state(game).hand_starting_stacks.alice == 200
  end

  test "hides opponent hole cards and awards a folded pot" do
    {:ok, game} = Poker.Game.start_link(small_blind: 1, big_blind: 2)
    {:ok, _player} = Poker.Game.join(game, :alice, 100, 1)
    {:ok, _player} = Poker.Game.join(game, :bob, 100, 2)
    {:ok, _state} = Poker.Game.start_hand(game)

    assert {:ok, snapshot} = Poker.Game.public_state(game, :alice)
    assert length(snapshot.players.alice.cards) == 2
    assert snapshot.players.bob.cards == :hidden
    assert {:ok, _state} = Poker.Game.act(game, :alice, :fold)

    state = Poker.Game.internal_state(game)
    assert state.phase == :waiting
    assert state.players.bob.stack == 101
    assert state.players.alice.stack == 99

    assert {:ok, [hand]} = Poker.Game.history(game, 2)
    assert hand.winners == [:bob]
    assert %{profit_loss: -1, result: :folded, contribution: 1, payout: 0, final_stack: 99} = hand.players.alice
    assert %{profit_loss: 1, result: :won_by_fold, contribution: 2, payout: 3, final_stack: 101} = hand.players.bob
    assert length(hand.players.alice.cards) == 2
    assert Enum.map(hand.actions, & &1.action) == ["small_blind", "big_blind", "fold"]
    assert {:error, :invalid_history_count} = Poker.Game.history(game, 0)
  end

  test "queues a new player for the following hand" do
    {:ok, game} = Poker.Game.start_link(small_blind: 1, big_blind: 2)
    {:ok, _player} = Poker.Game.join(game, :alice, 100, 1)
    {:ok, _player} = Poker.Game.join(game, :bob, 100, 2)
    {:ok, _state} = Poker.Game.start_hand(game)
    assert {:ok, _player} = Poker.Game.join(game, :charlie, 100, 3)

    snapshot = Poker.Game.internal_state(game)
    assert not Map.has_key?(snapshot.hole_cards, :charlie)
  end

  test "assigns a free random seat when none is specified" do
    {:ok, game} = Poker.Game.start_link(small_blind: 1, big_blind: 2)
    assert {:ok, %{seat: seat}} = Poker.Game.join(game, :alice, 100)
    assert seat in 1..9

    assert {:ok, %{seat: other_seat}} = Poker.Game.join(game, :bob, 100)
    assert other_seat != seat
  end

  test "posts blinds to the players left of the dealer on a full table" do
    {:ok, game} = Poker.Game.start_link(small_blind: 1, big_blind: 2)
    {:ok, _player} = Poker.Game.join(game, :alice, 100, 1)
    {:ok, _player} = Poker.Game.join(game, :bob, 100, 2)
    {:ok, _player} = Poker.Game.join(game, :charlie, 100, 3)
    {:ok, _state} = Poker.Game.start_hand(game)

    state = Poker.Game.internal_state(game)
    assert state.dealer == :alice
    assert state.street_contributions == %{alice: 0, bob: 1, charlie: 2}
    assert state.active_player == :alice
  end

  test "identifies a continuation bet in the decision context" do
    {:ok, game} = Poker.Game.start_link(small_blind: 1, big_blind: 2)
    {:ok, _player} = Poker.Game.join(game, :alice, 100, 1)
    {:ok, _player} = Poker.Game.join(game, :bob, 100, 2)
    {:ok, _state} = Poker.Game.start_hand(game)

    assert {:ok, _state} = Poker.Game.act(game, :alice, {:raise_to, 6})
    assert {:ok, _state} = Poker.Game.act(game, :bob, :call)
    assert {:ok, _state} = Poker.Game.act(game, :bob, :check)
    assert {:ok, _state} = Poker.Game.act(game, :alice, {:bet, 2})
    assert {:ok, context} = Poker.Game.decision_context(game, :bob)
    assert context.facing_cbet
  end
end
