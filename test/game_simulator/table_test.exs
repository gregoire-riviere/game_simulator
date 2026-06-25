defmodule GameSimulator.TableTest do
  use ExUnit.Case, async: true

  test "keeps bot profiles and hole cards private" do
    {:ok, table} = GameSimulator.Table.start_link(owner: "alice")
    assert {:ok, state} = GameSimulator.Table.state(table, "alice")

    assert length(state.players) == 6
    assert state.mode == :cash_nl2
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
    {:ok, table} = GameSimulator.Table.start_link(owner: "alice", mode: :elimination)
    state = :sys.get_state(table)

    :sys.replace_state(state.game, fn game ->
      put_in(game.players[state.human_id].stack, 0)
    end)

    assert {:error, :hero_busted} = GameSimulator.Table.next_hand(table, "alice")
  end

  test "shows automatic top-up in recent actions" do
    {:ok, table} = GameSimulator.Table.start_link(owner: "alice")
    state = :sys.get_state(table)

    :sys.replace_state(state.game, fn game ->
      players = Map.update!(game.players, state.human_id, &%{&1 | stack: 0})
      %{game | players: players, phase: :waiting}
    end)

    assert {:ok, state} = GameSimulator.Table.next_hand(table, "alice")
    assert %{player: "alice", action: "recave 200"} in state.recent_actions
  end

  test "exposes check and bet actions to the hero when poker rules say there is nothing to call" do
    {:ok, table} = GameSimulator.Table.start_link(owner: "alice")
    set_table_betting_state(table, current_bet: 0, hero_street: 0, hero_stack: 200, phase: :flop)

    assert {:ok, state} = GameSimulator.Table.state(table, "alice")

    assert state.hero_turn
    assert :check in state.actions
    assert :all_in in state.actions
    assert %{bet: %{min: 2, max: 200}} in state.actions
    refute :fold in state.actions
    refute :call in state.actions
  end

  test "exposes fold call and raise actions to the hero when facing a bet" do
    {:ok, table} = GameSimulator.Table.start_link(owner: "alice")
    set_table_betting_state(table, current_bet: 10, hero_street: 2, hero_stack: 198, phase: :flop)

    assert {:ok, state} = GameSimulator.Table.state(table, "alice")

    assert state.hero_turn
    assert :fold in state.actions
    assert :call in state.actions
    assert :all_in in state.actions
    assert %{raise_to: %{min: 12, max: 200}} in state.actions
    refute :check in state.actions
  end

  test "does not expose hero actions when a bot is active" do
    {:ok, table} = GameSimulator.Table.start_link(owner: "alice")
    table_state = :sys.get_state(table)

    :sys.replace_state(table_state.game, fn game ->
      bot = {:bot, 1}

      %{
        game |
        active_player: bot,
        pending: MapSet.new([bot]),
        current_bet: 0,
        street_contributions: Map.put(game.street_contributions, table_state.human_id, 0),
        hand_contributions: Map.put(game.hand_contributions, table_state.human_id, 0)
      }
    end)

    assert {:ok, state} = GameSimulator.Table.state(table, "alice")

    refute state.hero_turn
    assert state.actions == []
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

  def set_table_betting_state(table, options) do
    table_state = :sys.get_state(table)
    hero = table_state.human_id
    villain = {:bot, 1}

    :sys.replace_state(table_state.game, fn game ->
      current_bet = Keyword.fetch!(options, :current_bet)
      hero_street = Keyword.fetch!(options, :hero_street)
      hero_stack = Keyword.fetch!(options, :hero_stack)
      villain_street = Keyword.get(options, :villain_street, current_bet)
      villain_stack = Keyword.get(options, :villain_stack, 200 - villain_street)

      %{
        game |
        phase: Keyword.fetch!(options, :phase),
        players: %{
          hero => %{id: hero, seat: 6, stack: hero_stack},
          villain => %{id: villain, seat: 1, stack: villain_stack}
        },
        hole_cards: %{
          hero => [{"A", "spades"}, {"K", "spades"}],
          villain => [{"2", "clubs"}, {"7", "diamonds"}]
        },
        hand_players: MapSet.new([hero, villain]),
        folded: MapSet.new(),
        all_in: MapSet.new(),
        pending: MapSet.new([hero]),
        street_contributions: %{hero => hero_street, villain => villain_street},
        hand_contributions: %{hero => hero_street, villain => villain_street},
        current_bet: current_bet,
        min_raise: 2,
        active_player: hero,
        dealer: villain
      }
    end)
  end
end
