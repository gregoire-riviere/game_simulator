defmodule Poker.GameActionsTest do
  use ExUnit.Case, async: true

  test "has no action while the table is waiting between hands" do
    {:ok, game} = two_player_game()

    assert {:error, :no_action_required} = Poker.Game.next_action(game)
    assert {:error, :not_your_turn} = Poker.Game.act(game, :hero, :check)
  end

  test "lets the active player fold only when facing a bet" do
    {:ok, game} = game_with_hero_to_act(current_bet: 10, hero_street: 2, hero_stack: 98)

    assert_next_actions(game, [:fold, :call, :all_in, {:raise_to, 12, 100}])
    assert {:ok, _snapshot} = Poker.Game.act(game, :hero, :fold)

    state = Poker.Game.internal_state(game)
    assert state.phase == :waiting
    assert state.players.villain.stack == 102
  end

  test "lets the active player call exactly the amount to match" do
    {:ok, game} = game_with_hero_to_act(current_bet: 10, hero_street: 2, hero_stack: 98)

    assert_next_actions(game, [:fold, :call, :all_in, {:raise_to, 12, 100}])
    assert {:ok, _snapshot} = Poker.Game.act(game, :hero, :call)

    state = Poker.Game.internal_state(game)
    assert state.players.hero.stack == 90
    assert state.hand_contributions.hero == 10
  end

  test "turns a short call into a legal all-in call without offering a raise" do
    {:ok, game} = game_with_hero_to_act(current_bet: 10, hero_street: 2, hero_stack: 5)

    assert_next_actions(game, [:fold, :call, :all_in])
    assert {:ok, _snapshot} = Poker.Game.act(game, :hero, :call)

    state = Poker.Game.internal_state(game)
    assert state.players.hero.stack == 0
    assert MapSet.member?(state.all_in, :hero)
    assert state.hand_contributions.hero == 7
  end

  test "lets the active player check when there is nothing to call" do
    {:ok, game} = game_with_hero_to_act(current_bet: 0, hero_street: 0, hero_stack: 100, phase: :flop)

    assert_next_actions(game, [:check, :all_in, {:bet, 2, 100}])
    refute_next_actions(game, [:fold, :call, {:raise_to, 2, 100}])
    assert {:ok, _snapshot} = Poker.Game.act(game, :hero, :check)

    state = Poker.Game.internal_state(game)
    assert state.phase == :turn
    assert state.active_player == :villain
  end

  test "lets the active player make the minimum legal bet" do
    {:ok, game} = game_with_hero_to_act(current_bet: 0, hero_street: 0, hero_stack: 100, phase: :flop)

    assert_next_actions(game, [:check, :all_in, {:bet, 2, 100}])
    assert {:ok, _snapshot} = Poker.Game.act(game, :hero, {:bet, 2})

    state = Poker.Game.internal_state(game)
    assert state.current_bet == 2
    assert state.street_contributions.hero == 2
    assert state.players.hero.stack == 98
    assert state.active_player == :villain
  end

  test "lets the active player raise to the minimum legal total" do
    {:ok, game} = game_with_hero_to_act(current_bet: 10, hero_street: 2, hero_stack: 98)

    assert_next_actions(game, [:fold, :call, :all_in, {:raise_to, 12, 100}])
    assert {:ok, _snapshot} = Poker.Game.act(game, :hero, {:raise_to, 12})

    state = Poker.Game.internal_state(game)
    assert state.current_bet == 12
    assert state.street_contributions.hero == 12
    assert state.players.hero.stack == 88
    assert state.active_player == :villain
  end

  test "lets all-in act as a call when it cannot raise the current bet" do
    {:ok, game} = game_with_hero_to_act(current_bet: 10, hero_street: 2, hero_stack: 5)

    assert_next_actions(game, [:fold, :call, :all_in])
    assert {:ok, _snapshot} = Poker.Game.act(game, :hero, :all_in)

    state = Poker.Game.internal_state(game)
    assert state.players.hero.stack == 0
    assert state.hand_contributions.hero == 7
    assert MapSet.member?(state.all_in, :hero)
  end

  test "lets all-in act as a raise when it goes above the current bet" do
    {:ok, game} = game_with_hero_to_act(current_bet: 10, hero_street: 2, hero_stack: 98)

    assert_next_actions(game, [:fold, :call, :all_in, {:raise_to, 12, 100}])
    assert {:ok, _snapshot} = Poker.Game.act(game, :hero, :all_in)

    state = Poker.Game.internal_state(game)
    assert state.players.hero.stack == 0
    assert state.street_contributions.hero == 100
    assert state.current_bet == 100
    assert state.active_player == :villain
  end

  test "does not reopen raises to players who already acted after an incomplete all-in raise" do
    {:ok, game} = three_player_under_raise_game()

    assert {:ok, _snapshot} = Poker.Game.act(game, :short, :all_in)
    state = Poker.Game.internal_state(game)
    assert state.current_bet == 15
    assert state.min_raise == 10
    assert state.active_player == :third

    assert {:ok, _snapshot} = Poker.Game.act(game, :third, :call)
    assert {:ok, %{player_id: :hero, actions: actions}} = Poker.Game.next_action(game)
    assert :call in actions
    assert :fold in actions
    refute :all_in in actions
    refute Enum.any?(actions, &match?(%{raise_to: _}, &1))
    assert {:error, :raise_not_allowed} = Poker.Game.act(game, :hero, :all_in)
  end

  test "rejects actions that are not legal in the current betting state" do
    {:ok, facing_bet} = game_with_hero_to_act(current_bet: 10, hero_street: 2, hero_stack: 98)
    assert {:error, :cannot_check} = Poker.Game.act(facing_bet, :hero, :check)
    assert {:error, :bet_not_allowed} = Poker.Game.act(facing_bet, :hero, {:bet, 10})
    assert {:error, :raise_too_small} = Poker.Game.act(facing_bet, :hero, {:raise_to, 11})

    {:ok, no_bet} = game_with_hero_to_act(current_bet: 0, hero_street: 0, hero_stack: 100, phase: :flop)
    assert {:error, :fold_not_allowed} = Poker.Game.act(no_bet, :hero, :fold)
    assert {:error, :nothing_to_call} = Poker.Game.act(no_bet, :hero, :call)
    assert {:error, :raise_not_allowed} = Poker.Game.act(no_bet, :hero, {:raise_to, 10})
    assert {:error, :raise_too_small} = Poker.Game.act(no_bet, :hero, {:bet, 1})
  end

  test "offers an all-in wager when the player has chips but less than a normal big blind bet" do
    {:ok, game} = game_with_hero_to_act(current_bet: 0, hero_street: 0, hero_stack: 1, phase: :flop)

    assert_next_actions(game, [:check, :all_in])
    refute_next_actions(game, [:fold, :call, {:bet, 2, 1}])
    assert {:ok, _snapshot} = Poker.Game.act(game, :hero, :all_in)

    state = Poker.Game.internal_state(game)
    assert state.players.hero.stack == 0
    assert state.current_bet == 1
    assert MapSet.member?(state.all_in, :hero)
  end

  def two_player_game do
    {:ok, game} = Poker.Game.start_link(small_blind: 1, big_blind: 2)
    {:ok, _player} = Poker.Game.join(game, :hero, 100, 1)
    {:ok, _player} = Poker.Game.join(game, :villain, 100, 2)
    {:ok, game}
  end

  def game_with_hero_to_act(options) do
    {:ok, game} = two_player_game()
    {:ok, _state} = Poker.Game.start_hand(game)

    :sys.replace_state(game, fn state ->
      current_bet = Keyword.fetch!(options, :current_bet)
      hero_street = Keyword.fetch!(options, :hero_street)
      hero_stack = Keyword.fetch!(options, :hero_stack)
      villain_street = Keyword.get(options, :villain_street, current_bet)
      villain_stack = Keyword.get(options, :villain_stack, 100 - villain_street)

      %{
        state |
        phase: Keyword.get(options, :phase, :preflop),
        board: Keyword.get(options, :board, []),
        players: %{
          hero: %{id: :hero, seat: 1, stack: hero_stack},
          villain: %{id: :villain, seat: 2, stack: villain_stack}
        },
        hand_players: MapSet.new([:hero, :villain]),
        folded: MapSet.new(),
        all_in: MapSet.new(),
        pending: MapSet.new([:hero]),
        street_contributions: %{hero: hero_street, villain: villain_street},
        hand_contributions: %{hero: hero_street, villain: villain_street},
        current_bet: current_bet,
        min_raise: Keyword.get(options, :min_raise, 2),
        active_player: :hero,
        dealer: :hero,
        preflop_aggressor: Keyword.get(options, :preflop_aggressor),
        street_aggressor: Keyword.get(options, :street_aggressor)
      }
    end)

    {:ok, game}
  end

  def three_player_under_raise_game do
    {:ok, game} = Poker.Game.start_link(small_blind: 1, big_blind: 2)
    {:ok, _player} = Poker.Game.join(game, :hero, 100, 1)
    {:ok, _player} = Poker.Game.join(game, :short, 100, 2)
    {:ok, _player} = Poker.Game.join(game, :third, 100, 3)
    {:ok, _state} = Poker.Game.start_hand(game)

    :sys.replace_state(game, fn state ->
      %{
        state |
        phase: :flop,
        board: [{"A", "clubs"}, {"7", "diamonds"}, {"2", "spades"}],
        players: %{
          hero: %{id: :hero, seat: 1, stack: 90},
          short: %{id: :short, seat: 2, stack: 5},
          third: %{id: :third, seat: 3, stack: 90}
        },
        hand_players: MapSet.new([:hero, :short, :third]),
        folded: MapSet.new(),
        all_in: MapSet.new(),
        pending: MapSet.new([:short]),
        raise_blocked: MapSet.new(),
        street_contributions: %{hero: 10, short: 10, third: 10},
        hand_contributions: %{hero: 10, short: 10, third: 10},
        current_bet: 10,
        min_raise: 10,
        active_player: :short,
        dealer: :hero
      }
    end)

    {:ok, game}
  end

  def assert_next_actions(game, expected) do
    assert {:ok, %{player_id: :hero, actions: actions}} = Poker.Game.next_action(game)

    Enum.each(expected, fn expected_action ->
      assert action_present?(actions, expected_action), "missing action #{inspect(expected_action)} in #{inspect(actions)}"
    end)
  end

  def refute_next_actions(game, rejected) do
    assert {:ok, %{player_id: :hero, actions: actions}} = Poker.Game.next_action(game)

    Enum.each(rejected, fn rejected_action ->
      refute action_present?(actions, rejected_action), "unexpected action #{inspect(rejected_action)} in #{inspect(actions)}"
    end)
  end

  def action_present?(actions, {:bet, min, max}) do
    Enum.any?(actions, &(&1 == %{bet: %{min: min, max: max}}))
  end

  def action_present?(actions, {:raise_to, min, max}) do
    Enum.any?(actions, &(&1 == %{raise_to: %{min: min, max: max}}))
  end

  def action_present?(actions, action), do: action in actions
end
