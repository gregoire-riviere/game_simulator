defmodule PokerProfileStats do
  def run(args) do
    hands = args |> List.first() |> parse_hands()
    stack = 200
    ids = Enum.map(1..6, &{:bot, &1})
    profiles = Poker.Profile.generate(length(ids))
    profiles_by_id = ids |> Enum.zip(profiles) |> Map.new()
    {:ok, game} = Poker.Game.start_link(small_blind: 1, big_blind: 2)

    Enum.each(ids, fn {:bot, seat} = id ->
      {:ok, _player} = Poker.Game.join(game, id, stack, seat)
    end)

    stats =
      Enum.reduce(1..hands, new_stats(ids), fn _index, stats ->
        reset_stacks(game, stack)
        {:ok, _snapshot} = Poker.Game.start_hand(game)
        play_hand(game, profiles_by_id)
        {:ok, [hand]} = Poker.Game.history(game, 1)
        collect_hand(stats, hand, ids)
      end)

    print_report(stats, profiles_by_id, hands)
  end

  def parse_hands(nil), do: 10_000

  def parse_hands(value) do
    case Integer.parse(value) do
      {hands, ""} when hands > 0 -> hands
      _other -> raise ArgumentError, "usage: mix run --no-start scripts/poker_profile_stats.exs [hands]"
    end
  end

  def reset_stacks(game, stack) do
    :sys.replace_state(game, fn state ->
      players = Map.new(state.players, fn {id, player} -> {id, %{player | stack: stack}} end)
      %{state | players: players}
    end)
  end

  def play_hand(game, profiles_by_id) do
    case Poker.Game.next_action(game) do
      {:ok, %{player_id: id}} ->
        {:ok, context} = Poker.Game.decision_context(game, id)
        action = Poker.Decision.decide(Map.fetch!(profiles_by_id, id), context)

        case Poker.Game.act(game, id, action) do
          {:ok, _snapshot} -> play_hand(game, profiles_by_id)
          {:error, _reason} -> play_fallback_action(game, id, context, profiles_by_id)
        end

      {:error, :no_action_required} ->
        :ok
    end
  end

  def play_fallback_action(game, id, context, profiles_by_id) do
    action =
      cond do
        :check in context.actions -> :check
        :call in context.actions -> :call
        :fold in context.actions -> :fold
        :all_in in context.actions -> :all_in
        true -> raise "no legal fallback action for #{inspect(id)}: #{inspect(context.actions)}"
      end

    {:ok, _snapshot} = Poker.Game.act(game, id, action)
    play_hand(game, profiles_by_id)
  end

  def new_stats(ids), do: Map.new(ids, &{&1, empty_stats()})

  def empty_stats do
    %{
      hands: 0,
      vpip: 0,
      pfr: 0,
      limp: 0,
      three_bet_opp: 0,
      three_bet: 0,
      preflop_fold: 0,
      cbet_opp: 0,
      cbet: 0,
      fold_to_cbet_opp: 0,
      fold_to_cbet: 0,
      saw_flop: 0,
      wtsd: 0,
      wmsd: 0
    }
  end

  def collect_hand(stats, hand, ids) do
    preflop = analyze_preflop(hand.actions, hand.big_blind)
    postflop = analyze_postflop(hand, preflop)

    Enum.reduce(ids, stats, fn id, stats ->
      if Map.has_key?(hand.players, id) do
        result = Map.fetch!(hand.players, id)

        update_in(stats[id], fn player_stats ->
          player_stats
          |> inc(:hands, true)
          |> inc(:vpip, MapSet.member?(preflop.vpip, id))
          |> inc(:pfr, MapSet.member?(preflop.pfr, id))
          |> inc(:limp, MapSet.member?(preflop.limp, id))
          |> inc(:three_bet_opp, MapSet.member?(preflop.three_bet_opp, id))
          |> inc(:three_bet, MapSet.member?(preflop.three_bet, id))
          |> inc(:preflop_fold, MapSet.member?(preflop.folded, id))
          |> inc(:cbet_opp, postflop.cbet_opp == id)
          |> inc(:cbet, postflop.cbetter == id)
          |> inc(:fold_to_cbet_opp, MapSet.member?(postflop.fold_to_cbet_opp, id))
          |> inc(:fold_to_cbet, MapSet.member?(postflop.fold_to_cbet, id))
          |> inc(:saw_flop, saw_flop?(hand, preflop, id))
          |> inc(:wtsd, showdown?(hand, result))
          |> inc(:wmsd, showdown?(hand, result) and result.profit_loss > 0)
        end)
      else
        stats
      end
    end)
  end

  def inc(stats, key, true), do: Map.update!(stats, key, &(&1 + 1))
  def inc(stats, _key, false), do: stats

  def analyze_preflop(actions, big_blind) do
    initial = %{
      contribution: %{},
      current_bet: 0,
      min_raise: big_blind,
      raise_count: 0,
      aggressor: nil,
      vpip: MapSet.new(),
      pfr: MapSet.new(),
      limp: MapSet.new(),
      three_bet_opp: MapSet.new(),
      three_bet: MapSet.new(),
      folded: MapSet.new(),
      all_in: MapSet.new()
    }

    actions
    |> Enum.filter(&(&1.street == :preflop))
    |> Enum.reduce(initial, &analyze_preflop_action(&1, &2, big_blind))
    |> Map.take([:aggressor, :vpip, :pfr, :limp, :three_bet_opp, :three_bet, :folded, :all_in])
  end

  def analyze_preflop_action(%{action: blind} = action, state, _big_blind) when blind in ["small_blind", "big_blind"] do
    contribution = Map.put(state.contribution, action.player, action.contribution_after)
    %{state | contribution: contribution, current_bet: max(state.current_bet, action.contribution_after)}
  end

  def analyze_preflop_action(%{action: "fold"} = action, state, _big_blind) do
    state
    |> maybe_add_three_bet_opp(action.player)
    |> Map.update!(:folded, &MapSet.put(&1, action.player))
  end

  def analyze_preflop_action(action, state, big_blind) do
    voluntary = action.amount > 0
    all_in = action.action == "all_in"
    raises = action.contribution_after > state.current_bet
    full_raise = raises and action.contribution_after - state.current_bet >= state.min_raise
    aggressive = raises and (String.starts_with?(action.action, "raise_to") or String.starts_with?(action.action, "bet") or all_in)

    state = maybe_add_three_bet_opp(state, action.player)

    state =
      cond do
        voluntary and aggressive ->
          state
          |> put_in([:vpip], MapSet.put(state.vpip, action.player))
          |> put_in([:pfr], MapSet.put(state.pfr, action.player))
          |> add_three_bet(action.player, state.raise_count)

        voluntary ->
          state
          |> put_in([:vpip], MapSet.put(state.vpip, action.player))
          |> add_limp(action.player, state.raise_count, state.current_bet, big_blind)

        true ->
          state
      end

    contribution = Map.put(state.contribution, action.player, action.contribution_after)
    min_raise = if full_raise, do: max(state.min_raise, action.contribution_after - state.current_bet), else: state.min_raise
    raise_count = if full_raise, do: state.raise_count + 1, else: state.raise_count
    aggressor = if aggressive and is_nil(state.aggressor), do: action.player, else: state.aggressor
    all_in_set = if all_in, do: MapSet.put(state.all_in, action.player), else: state.all_in

    %{state | contribution: contribution, current_bet: max(state.current_bet, action.contribution_after), min_raise: min_raise, raise_count: raise_count, aggressor: aggressor, all_in: all_in_set}
  end

  def maybe_add_three_bet_opp(state, player) do
    if state.raise_count == 1 do
      %{state | three_bet_opp: MapSet.put(state.three_bet_opp, player)}
    else
      state
    end
  end

  def add_three_bet(state, player, 1), do: %{state | three_bet: MapSet.put(state.three_bet, player)}
  def add_three_bet(state, _player, _raise_count), do: state

  def add_limp(state, player, 0, current_bet, big_blind) when current_bet <= big_blind do
    %{state | limp: MapSet.put(state.limp, player)}
  end

  def add_limp(state, _player, _raise_count, _current_bet, _big_blind), do: state

  def analyze_postflop(hand, preflop) do
    flop_actions = Enum.filter(hand.actions, &(&1.street == :flop))
    active_on_flop = hand.players |> Map.keys() |> MapSet.new() |> MapSet.difference(preflop.folded) |> MapSet.difference(preflop.all_in)
    cbet = cbet_result(flop_actions, preflop.aggressor)
    fold_opp = if cbet.cbetter, do: MapSet.delete(active_on_flop, cbet.cbetter), else: MapSet.new()
    fold_to_cbet = if cbet.cbetter, do: fold_to_cbet_after(flop_actions, cbet.index, fold_opp), else: MapSet.new()

    %{
      cbet_opp: cbet.opp,
      cbetter: cbet.cbetter,
      fold_to_cbet_opp: fold_opp,
      fold_to_cbet: fold_to_cbet
    }
  end

  def cbet_result(_flop_actions, nil), do: %{opp: nil, cbetter: nil, index: nil}

  def cbet_result(flop_actions, aggressor) do
    flop_actions
    |> Enum.with_index()
    |> Enum.reduce_while(%{opp: nil, cbetter: nil, index: nil, blocked: false}, fn {action, index}, result ->
      cond do
        result.blocked -> {:halt, result}
        action.player == aggressor and aggressive_postflop?(action) -> {:halt, %{opp: aggressor, cbetter: aggressor, index: index, blocked: false}}
        action.player == aggressor -> {:halt, %{opp: aggressor, cbetter: nil, index: nil, blocked: false}}
        aggressive_postflop?(action) -> {:halt, %{opp: nil, cbetter: nil, index: nil, blocked: true}}
        true -> {:cont, result}
      end
    end)
    |> Map.take([:opp, :cbetter, :index])
  end

  def aggressive_postflop?(action) do
    String.starts_with?(action.action, "bet") or String.starts_with?(action.action, "raise_to") or (action.action == "all_in" and action.amount > 0)
  end

  def fold_to_cbet_after(_flop_actions, nil, _opponents), do: MapSet.new()

  def fold_to_cbet_after(flop_actions, index, opponents) do
    flop_actions
    |> Enum.drop(index + 1)
    |> Enum.filter(&(&1.action == "fold" and MapSet.member?(opponents, &1.player)))
    |> Enum.map(& &1.player)
    |> MapSet.new()
  end

  def showdown?(hand, result), do: length(hand.board) == 5 and result.result != :folded
  def saw_flop?(hand, preflop, id), do: length(hand.board) >= 3 and not MapSet.member?(preflop.folded, id)

  def print_report(stats, profiles_by_id, hands) do
    IO.puts("# Poker profile stats")
    IO.puts("")
    IO.puts("Hands simulated: #{hands}")
    IO.puts("Blinds: 1/2, stack reset to 200 between hands, six PNJ and no hero.")
    IO.puts("")
    IO.puts("| Seat | Archetype | VPIP | PFR | Limp | 3bet | 3bet opp | Fold PF | C-bet | Fold vs C-bet | WTSD | W$SD | Hands |")
    IO.puts("| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |")

    stats
    |> Enum.sort_by(fn {{:bot, seat}, _stats} -> seat end)
    |> Enum.each(fn {id, player_stats} ->
      profile = Map.fetch!(profiles_by_id, id)

      IO.puts("| #{elem(id, 1)} | #{profile.archetype} | #{pct(player_stats.vpip, player_stats.hands)} | #{pct(player_stats.pfr, player_stats.hands)} | #{pct(player_stats.limp, player_stats.hands)} | #{pct(player_stats.three_bet, player_stats.three_bet_opp)} | #{player_stats.three_bet_opp} | #{pct(player_stats.preflop_fold, player_stats.hands)} | #{pct(player_stats.cbet, player_stats.cbet_opp)} | #{pct(player_stats.fold_to_cbet, player_stats.fold_to_cbet_opp)} | #{pct(player_stats.wtsd, player_stats.saw_flop)} | #{pct(player_stats.wmsd, player_stats.wtsd)} | #{player_stats.hands} |")
    end)

    print_archetype_report(stats, profiles_by_id)
  end

  def print_archetype_report(stats, profiles_by_id) do
    IO.puts("")
    IO.puts("## By archetype")
    IO.puts("")
    IO.puts("| Archetype | VPIP | PFR | Limp | 3bet | 3bet opp | Fold PF | C-bet | Fold vs C-bet | WTSD | W$SD | Hands |")
    IO.puts("| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |")

    stats
    |> Enum.group_by(fn {id, _player_stats} -> Map.fetch!(profiles_by_id, id).archetype end, fn {_id, player_stats} -> player_stats end)
    |> Enum.sort_by(&elem(&1, 0))
    |> Enum.each(fn {archetype, rows} ->
      row = merge_stats(rows)
      IO.puts("| #{archetype} | #{pct(row.vpip, row.hands)} | #{pct(row.pfr, row.hands)} | #{pct(row.limp, row.hands)} | #{pct(row.three_bet, row.three_bet_opp)} | #{row.three_bet_opp} | #{pct(row.preflop_fold, row.hands)} | #{pct(row.cbet, row.cbet_opp)} | #{pct(row.fold_to_cbet, row.fold_to_cbet_opp)} | #{pct(row.wtsd, row.saw_flop)} | #{pct(row.wmsd, row.wtsd)} | #{row.hands} |")
    end)
  end

  def merge_stats(rows) do
    Enum.reduce(rows, empty_stats(), fn row, total ->
      Map.new(total, fn {key, value} -> {key, value + Map.fetch!(row, key)} end)
    end)
  end

  def pct(_count, 0), do: "n/a"

  def pct(count, total) do
    :io_lib.format("~.1f%", [count * 100 / total]) |> IO.iodata_to_binary()
  end
end

PokerProfileStats.run(System.argv())
