defmodule Poker.Game do
  use GenServer

  def start_link(options) do
    GenServer.start_link(__MODULE__, options, Keyword.take(options, [:name]))
  end

  def join(game, id, stack), do: join(game, id, stack, nil)
  def join(game, id, stack, seat), do: GenServer.call(game, {:join, id, stack, seat})
  def leave(game, id), do: GenServer.call(game, {:leave, id})
  def start_hand(game), do: GenServer.call(game, :start_hand)
  def next_action(game), do: GenServer.call(game, :next_action)
  def act(game, id, action), do: GenServer.call(game, {:act, id, action})
  def public_state(game, viewer_id), do: GenServer.call(game, {:public_state, viewer_id})
  def internal_state(game), do: GenServer.call(game, :internal_state)
  def history(game, count), do: GenServer.call(game, {:history, count})

  @impl true
  def init(options) do
    small_blind = Keyword.get(options, :small_blind)
    big_blind = Keyword.get(options, :big_blind)

    if is_integer(small_blind) and is_integer(big_blind) and small_blind > 0 and big_blind > small_blind do
      {:ok,
       %{
         players: %{}, # Joueurs assis, indexés par leur identifiant.
         small_blind: small_blind, # Montant de la small blind de la table.
         big_blind: big_blind, # Montant de la big blind de la table.
         phase: :waiting, # Rue courante : attente, préflop, flop, turn ou river.
         dealer: nil, # Identifiant du joueur qui porte le bouton.
         deck: [], # Cartes non encore distribuées du paquet mélangé.
         board: [], # Cartes communes révélées sur le board.
         hole_cards: %{}, # Cartes privées, indexées par identifiant de joueur.
         hand_players: MapSet.new(), # Joueurs participant à la main courante.
         folded: MapSet.new(), # Joueurs ayant abandonné la main courante.
         all_in: MapSet.new(), # Joueurs sans jeton restant dans la main.
         pending: MapSet.new(), # Joueurs qui doivent encore agir dans cette rue.
         leaving: MapSet.new(), # Joueurs à retirer après le règlement de la main.
         street_contributions: %{}, # Jetons engagés dans la rue courante.
         hand_contributions: %{}, # Jetons engagés depuis le début de la main.
         current_bet: 0, # Plus grande contribution à égaler dans la rue.
         min_raise: big_blind, # Écart minimal requis pour une relance.
         active_player: nil, # Joueur dont l'action est actuellement attendue.
         history: [] # Cinquante dernières mains, de la plus récente à la plus ancienne.
       }}
    else
      {:stop, :invalid_blinds}
    end
  end

  @impl true
  def handle_call({:join, id, stack, seat}, _from, state) do
    seat = if is_nil(seat), do: random_available_seat(state), else: seat

    cond do
      is_nil(id) -> {:reply, {:error, :invalid_id}, state}
      not is_integer(stack) or stack < 0 -> {:reply, {:error, :invalid_stack}, state}
      is_nil(seat) -> {:reply, {:error, :no_available_seat}, state}
      not is_integer(seat) or seat not in 1..9 -> {:reply, {:error, :invalid_seat}, state}
      Map.has_key?(state.players, id) -> {:reply, {:error, :duplicate_player}, state}
      Enum.any?(state.players, fn {_id, player} -> player.seat == seat end) -> {:reply, {:error, :seat_taken}, state}
      true ->
        player = %{id: id, seat: seat, stack: stack}
        {:reply, {:ok, player}, %{state | players: Map.put(state.players, id, player)}}
    end
  end

  def handle_call({:leave, id}, _from, state) do
    case Map.fetch(state.players, id) do
      :error -> {:reply, {:error, :unknown_player}, state}
      {:ok, _player} when state.phase == :waiting ->
        {:reply, :ok, %{state | players: Map.delete(state.players, id)}}

      {:ok, _player} when not is_map_key(state.hole_cards, id) ->
        {:reply, :ok, %{state | players: Map.delete(state.players, id)}}

      {:ok, _player} ->
        state = fold_player(state, id)
        state = %{state | leaving: MapSet.put(state.leaving, id)}
        {:reply, :ok, advance_after_action(state, id)}
    end
  end

  def handle_call(:start_hand, _from, %{phase: :waiting} = state) do
    case begin_hand(state) do
      {:ok, state} -> {:reply, {:ok, public_snapshot(state, nil)}, state}
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  def handle_call(:start_hand, _from, state), do: {:reply, {:error, :hand_in_progress}, state}

  def handle_call(:next_action, _from, %{active_player: nil} = state) do
    {:reply, {:error, :no_action_required}, state}
  end

  def handle_call(:next_action, _from, state) do
    {:reply, {:ok, %{player_id: state.active_player, actions: actions_for(state, state.active_player)}}, state}
  end

  def handle_call({:act, id, action}, _from, state) do
    cond do
      state.active_player != id -> {:reply, {:error, :not_your_turn}, state}
      not Map.has_key?(state.players, id) -> {:reply, {:error, :unknown_player}, state}
      true ->
        case apply_action(state, id, action) do
          {:ok, state} ->
            state = advance_after_action(state, id)
            {:reply, {:ok, public_snapshot(state, id)}, state}

          {:error, reason} -> {:reply, {:error, reason}, state}
        end
    end
  end

  def handle_call({:public_state, viewer_id}, _from, state) do
    {:reply, {:ok, public_snapshot(state, viewer_id)}, state}
  end

  def handle_call(:internal_state, _from, state), do: {:reply, state, state}

  def handle_call({:history, count}, _from, state) when is_integer(count) and count > 0 do
    {:reply, {:ok, Enum.take(state.history, count)}, state}
  end

  def handle_call({:history, _count}, _from, state), do: {:reply, {:error, :invalid_history_count}, state}

  def random_available_seat(state) do
    taken_seats = state.players |> Map.values() |> Enum.map(& &1.seat)
    available_seats = Enum.reject(1..9, &(&1 in taken_seats))

    case available_seats do
      [] -> nil
      seats -> Enum.random(seats)
    end
  end

  def begin_hand(state) do
    ids =
      state.players
      |> Map.values()
      |> Enum.filter(&(&1.stack > 0))
      |> Enum.map(& &1.id)

    if length(ids) < 2 do
      {:error, :not_enough_players}
    else
      dealer = next_dealer(state, ids)
      order = ordered_ids(state, dealer, ids)
      {small_blind_player, big_blind_player, first_player} = blind_positions(order)
      deck = Poker.shuffled_deck()
      {hole_cards, deck} = deal_hole_cards(ids, deck, %{})
      state =
        %{state |
          phase: :preflop,
          dealer: dealer,
          deck: deck,
          board: [],
          hole_cards: hole_cards,
          hand_players: MapSet.new(ids),
          folded: MapSet.new(),
          all_in: MapSet.new(),
          pending: MapSet.new(ids),
          leaving: MapSet.new(),
          street_contributions: Map.new(ids, &{&1, 0}),
          hand_contributions: Map.new(ids, &{&1, 0}),
          current_bet: 0,
          min_raise: state.big_blind,
          active_player: nil
        }

      state = post_blind(state, small_blind_player, state.small_blind)
      state = post_blind(state, big_blind_player, state.big_blind)
      state = %{state | pending: pending_players(state, MapSet.new([small_blind_player, big_blind_player]))}
      state = Map.put(state, :pending, MapSet.union(state.pending, pending_players(state, MapSet.new())))
      state = %{state | active_player: first_pending_after(state, first_player)}
      {:ok, state}
    end
  end

  def blind_positions([dealer, other]), do: {dealer, other, dealer}
  def blind_positions([dealer, small_blind, big_blind]), do: {small_blind, big_blind, dealer}
  def blind_positions([_dealer, small_blind, big_blind, first_player | _]), do: {small_blind, big_blind, first_player}

  def deal_hole_cards([], deck, cards), do: {cards, deck}
  def deal_hole_cards([id | ids], [first, second | deck], cards) do
    deal_hole_cards(ids, deck, Map.put(cards, id, [first, second]))
  end

  def post_blind(state, id, amount) do
    player = Map.fetch!(state.players, id)
    committed = min(amount, player.stack)
    state = commit(state, id, committed)
    if Map.fetch!(state.players, id).stack == 0, do: %{state | all_in: MapSet.put(state.all_in, id)}, else: state
  end

  def actions_for(state, id) do
    player = Map.fetch!(state.players, id)
    to_call = state.current_bet - Map.fetch!(state.street_contributions, id)
    base = [:fold, :all_in]
    base = if to_call == 0, do: [:check | base], else: [:call | base]

    cond do
      player.stack == 0 -> []
      state.current_bet == 0 and player.stack >= state.big_blind -> [%{bet: %{min: state.big_blind, max: player.stack}} | base]
      state.current_bet > 0 and player.stack + Map.fetch!(state.street_contributions, id) >= state.current_bet + state.min_raise ->
        min_total = state.current_bet + state.min_raise
        max_total = player.stack + Map.fetch!(state.street_contributions, id)
        [%{raise_to: %{min: min_total, max: max_total}} | base]

      true -> base
    end
  end

  def apply_action(state, id, :fold), do: {:ok, fold_player(state, id)}

  def apply_action(state, id, :check) do
    if state.current_bet == Map.fetch!(state.street_contributions, id), do: {:ok, remove_pending(state, id)}, else: {:error, :cannot_check}
  end

  def apply_action(state, id, :call) do
    amount = state.current_bet - Map.fetch!(state.street_contributions, id)
    player = Map.fetch!(state.players, id)
    if amount > 0, do: {:ok, commit_and_finish(state, id, min(amount, player.stack))}, else: {:error, :nothing_to_call}
  end

  def apply_action(state, id, {:bet, amount}) do
    if state.current_bet != 0, do: {:error, :bet_not_allowed}, else: raise_to(state, id, amount)
  end

  def apply_action(state, id, {:raise_to, total}) do
    if state.current_bet == 0, do: {:error, :raise_not_allowed}, else: raise_to(state, id, total)
  end

  def apply_action(state, id, :all_in) do
    player = Map.fetch!(state.players, id)
    total = Map.fetch!(state.street_contributions, id) + player.stack

    if total <= state.current_bet do
      {:ok, commit_and_finish(state, id, player.stack)}
    else
      raise_to(state, id, total)
    end
  end

  def apply_action(_state, _id, _action), do: {:error, :invalid_action}

  def raise_to(state, id, total) do
    player = Map.fetch!(state.players, id)
    previous = Map.fetch!(state.street_contributions, id)
    amount = total - previous
    raise_size = total - state.current_bet

    cond do
      not is_integer(total) -> {:error, :invalid_amount}
      amount <= 0 or amount > player.stack -> {:error, :invalid_amount}
      total <= state.current_bet -> {:error, :raise_too_small}
      raise_size < state.min_raise and amount != player.stack -> {:error, :raise_too_small}
      true ->
        state = commit(state, id, amount)
        state = %{state | current_bet: total, min_raise: max(state.min_raise, raise_size)}
        state = %{state | pending: pending_players(state, MapSet.new([id]))}
        state = if Map.fetch!(state.players, id).stack == 0, do: %{state | all_in: MapSet.put(state.all_in, id)}, else: state
        {:ok, state}
    end
  end

  def commit_and_finish(state, id, amount) do
    state = commit(state, id, amount)
    state = remove_pending(state, id)
    if Map.fetch!(state.players, id).stack == 0, do: %{state | all_in: MapSet.put(state.all_in, id)}, else: state
  end

  def commit(state, id, amount) do
    player = Map.fetch!(state.players, id)
    players = Map.put(state.players, id, %{player | stack: player.stack - amount})
    street = Map.update!(state.street_contributions, id, &(&1 + amount))
    hand = Map.update!(state.hand_contributions, id, &(&1 + amount))
    %{state | players: players, street_contributions: street, hand_contributions: hand, current_bet: max(state.current_bet, Map.fetch!(street, id))}
  end

  def fold_player(state, id) do
    %{state | folded: MapSet.put(state.folded, id), pending: MapSet.delete(state.pending, id)}
  end

  def remove_pending(state, id), do: %{state | pending: MapSet.delete(state.pending, id)}

  def advance_after_action(state, id) do
    remaining = active_ids(state)

    cond do
      length(remaining) == 1 -> settle_fold(state, hd(remaining))
      MapSet.size(state.pending) == 0 -> advance_street(state)
      true -> %{state | active_player: first_pending_after(state, next_after(state, id))}
    end
  end

  def advance_street(state) do
    case state.phase do
      :preflop -> reveal_street(state, :flop, 3)
      :flop -> reveal_street(state, :turn, 1)
      :turn -> reveal_street(state, :river, 1)
      :river -> settle_showdown(state)
    end
  end

  def reveal_street(state, phase, count) do
    {cards, deck} = Enum.split(state.deck, count)
    pending = pending_players(state, MapSet.new())
    state =
      %{state |
        phase: phase,
        deck: deck,
        board: state.board ++ cards,
        street_contributions: Map.new(Map.keys(state.hole_cards), &{&1, 0}),
        current_bet: 0,
        min_raise: state.big_blind,
        pending: pending,
        active_player: nil
      }

    if MapSet.size(pending) == 0 do
      advance_street(state)
    else
      %{state | active_player: first_pending_after(state, next_after(state, state.dealer))}
    end
  end

  def settle_fold(state, winner) do
    amount = Enum.sum(Map.values(state.hand_contributions))
    payouts = %{winner => amount}
    state = state |> credit(payouts) |> record_hand(payouts)
    finish_hand(state)
  end

  def settle_showdown(state) do
    players =
      Enum.map(state.hand_players, fn id ->
        %{id: id, cards: Map.fetch!(state.hole_cards, id), contribution: Map.fetch!(state.hand_contributions, id), folded: id in state.folded}
      end)

    first_left_of_button = next_after(state, state.dealer, Map.keys(state.players))
    odd_chip_order = ordered_ids(state, first_left_of_button, Map.keys(state.players))
    payouts = Poker.settle(players, state.board, odd_chip_order)
    state |> credit(payouts) |> record_hand(payouts) |> finish_hand()
  end

  def record_hand(state, payouts) do
    players =
      Map.new(state.hand_players, fn id ->
        contribution = Map.fetch!(state.hand_contributions, id)
        payout = Map.get(payouts, id, 0)
        {id,
         %{
           profit_loss: payout - contribution,
           result: historical_result(state, id)
         }}
      end)

    hand = %{dealer: state.dealer, board: state.board, players: players}
    %{state | history: Enum.take([hand | state.history], 50)}
  end

  def historical_result(state, id) do
    cond do
      id in state.folded -> :folded
      length(state.board) < 5 -> :won_by_fold
      true ->
        cards = Map.fetch!(state.hole_cards, id)
        %{cards: cards, hand: cards |> Kernel.++(state.board) |> Poker.best_hand() |> Poker.hand_description()}
    end
  end

  def credit(state, payouts) do
    players =
      Enum.reduce(payouts, state.players, fn {id, amount}, players ->
        Map.update!(players, id, fn player -> %{player | stack: player.stack + amount} end)
      end)

    %{state | players: players}
  end

  def finish_hand(state) do
    players = Enum.reduce(state.leaving, state.players, &Map.delete(&2, &1))
    state =
      %{state |
        players: players,
        phase: :waiting,
        deck: [],
        board: [],
        hole_cards: %{},
        hand_players: MapSet.new(),
        folded: MapSet.new(),
        all_in: MapSet.new(),
        pending: MapSet.new(),
        leaving: MapSet.new(),
        street_contributions: %{},
        hand_contributions: %{},
        current_bet: 0,
        active_player: nil
      }

    state
  end

  def active_ids(state) do
    state.hand_players |> MapSet.difference(state.folded) |> MapSet.to_list()
  end

  def pending_players(state, excluded) do
    state.hand_players
    |> MapSet.difference(state.folded)
    |> MapSet.difference(state.all_in)
    |> MapSet.difference(excluded)
  end

  def next_dealer(%{dealer: nil} = state, ids) do
    ids |> Enum.map(&Map.fetch!(state.players, &1)) |> Enum.min_by(& &1.seat) |> Map.fetch!(:id)
  end

  def next_dealer(state, ids) do
    if Map.has_key?(state.players, state.dealer) do
      next_after(state, state.dealer, ids)
    else
      ids |> Enum.map(&Map.fetch!(state.players, &1)) |> Enum.min_by(& &1.seat) |> Map.fetch!(:id)
    end
  end

  def ordered_ids(state, dealer, ids) do
    players = ids |> Enum.map(&Map.fetch!(state.players, &1)) |> Enum.sort_by(& &1.seat)
    {before, remaining} = Enum.split_while(players, &(&1.id != dealer))
    Enum.map(remaining ++ before, & &1.id)
  end

  def next_after(state, id), do: next_after(state, id, MapSet.to_list(state.hand_players))

  def next_after(state, id, ids) do
    players = ids |> Enum.map(&Map.fetch!(state.players, &1)) |> Enum.sort_by(& &1.seat)
    anchor_seat = state.players |> Map.get(id, %{seat: 0}) |> Map.fetch!(:seat)
    next = Enum.find(players, &(&1.seat > anchor_seat)) || hd(players)
    next.id
  end

  def first_pending_after(state, id) do
    order = ordered_ids(state, id, MapSet.to_list(state.hand_players))
    Enum.find(order, &MapSet.member?(state.pending, &1))
  end

  def public_snapshot(state, viewer_id) do
    players =
      Map.new(state.players, fn {id, player} ->
        cards = if id == viewer_id, do: Map.get(state.hole_cards, id, []), else: :hidden
        {id, Map.merge(Map.take(player, [:id, :seat, :stack]), %{cards: cards, folded: id in state.folded, contribution: Map.get(state.hand_contributions, id, 0)})}
      end)

    %{
      phase: state.phase,
      dealer: state.dealer,
      board: state.board,
      pot: Enum.sum(Map.values(state.hand_contributions)),
      players: players,
      active_player: state.active_player,
      small_blind: state.small_blind,
      big_blind: state.big_blind
    }
  end
end
