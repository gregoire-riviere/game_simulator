defmodule Poker.Game do
  @moduledoc """
  Arbitre d'une table de Texas Hold'em.

  Il applique exclusivement les règles : tours, montants légaux, cartes, pots et
  règlement. Les profils et décisions des PNJ vivent volontairement ailleurs.
  """

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
  def decision_context(game, id), do: GenServer.call(game, {:decision_context, id})
  def internal_state(game), do: GenServer.call(game, :internal_state)
  def history(game, count), do: GenServer.call(game, {:history, count})

  @impl true
  def init(options) do
    case Keyword.fetch(options, :state) do
      {:ok, state} -> if is_map(state), do: {:ok, state}, else: {:stop, :invalid_state}
      :error -> init_new(options)
    end
  end

  def init_new(options) do
    small_blind = Keyword.get(options, :small_blind)
    big_blind = Keyword.get(options, :big_blind)
    mode = Keyword.get(options, :mode, :elimination)
    top_up_to = Keyword.get(options, :top_up_to, 200)
    min_stack = Keyword.get(options, :min_stack, 80)

    if is_integer(small_blind) and is_integer(big_blind) and small_blind > 0 and big_blind > small_blind and mode in [:elimination, :cash_nl2] and is_integer(min_stack) and is_integer(top_up_to) and min_stack >= 0 and top_up_to >= min_stack do
      {:ok,
       %{
         mode: mode, # `:cash_nl2` recave les stacks trop courts avant la main suivante.
         min_stack: min_stack,
         top_up_to: top_up_to,
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
         raise_blocked: MapSet.new(), # Joueurs autorisés à payer un all-in incomplet, sans relancer.
         leaving: MapSet.new(), # Joueurs à retirer après le règlement de la main.
         street_contributions: %{}, # Jetons engagés dans la rue courante.
         hand_contributions: %{}, # Jetons engagés depuis le début de la main.
         hand_starting_stacks: %{}, # Stacks au début de la main, utilisés par l'export.
         top_ups: %{}, # Recaves automatiques appliquées juste avant la main courante.
         current_hand_actions: [], # Journal complet des actions de la main courante.
         current_bet: 0, # Plus grande contribution à égaler dans la rue.
         min_raise: big_blind, # Écart minimal requis pour une relance.
         preflop_aggressor: nil, # Dernier relanceur préflop, utilisé uniquement dans le contexte de décision.
         preflop_raise_count: 0, # Nombre de relances complètes préflop, open inclus.
         street_aggressor: nil, # Dernier miseur ou relanceur de la rue courante.
         active_player: nil, # Joueur dont l'action est actuellement attendue.
         hand_number: 0, # Numéro de la main courante depuis la création de la table.
         history: [] # Cinquante dernières mains, de la plus récente à la plus ancienne.
       }}
    else
      {:stop, :invalid_options}
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
        before = state

        case apply_action(state, id, action) do
          {:ok, state} ->
            state = record_action_detail(state, before, id, action)
            state = advance_after_action(state, id)
            {:reply, {:ok, public_snapshot(state, id)}, state}

          {:error, reason} -> {:reply, {:error, reason}, state}
        end
    end
  end

  def handle_call({:public_state, viewer_id}, _from, state) do
    {:reply, {:ok, public_snapshot(state, viewer_id)}, state}
  end

  def handle_call({:decision_context, id}, _from, state) do
    cond do
      state.active_player != id -> {:reply, {:error, :not_your_turn}, state}
      not Map.has_key?(state.hole_cards, id) -> {:reply, {:error, :not_in_hand}, state}
      true -> {:reply, {:ok, decision_snapshot(state, id)}, state}
    end
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
    state = top_up_players(state)

    # Seuls les joueurs ayant des jetons peuvent recevoir des cartes pour cette main.
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
          hand_number: state.hand_number + 1,
          dealer: dealer,
          deck: deck,
          board: [],
          hole_cards: hole_cards,
          hand_players: MapSet.new(ids),
          folded: MapSet.new(),
          all_in: MapSet.new(),
          pending: MapSet.new(ids),
          raise_blocked: MapSet.new(),
          leaving: MapSet.new(),
          street_contributions: Map.new(ids, &{&1, 0}),
          hand_contributions: Map.new(ids, &{&1, 0}),
          hand_starting_stacks: Map.new(ids, &{&1, Map.fetch!(state.players, &1).stack}),
          top_ups: state.top_ups,
          current_hand_actions: [],
          current_bet: 0,
          min_raise: state.big_blind,
          preflop_aggressor: nil,
          preflop_raise_count: 0,
          street_aggressor: nil,
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

  def top_up_players(%{mode: :cash_nl2} = state) do
    {players, top_ups} =
      Enum.reduce(state.players, {%{}, %{}}, fn {id, player}, {players, top_ups} ->
        new_stack = if player.stack < state.min_stack, do: state.top_up_to, else: player.stack
        amount = new_stack - player.stack
        top_ups = if amount > 0, do: Map.put(top_ups, id, amount), else: top_ups
        {Map.put(players, id, %{player | stack: new_stack}), top_ups}
      end)

    %{state | players: players, top_ups: top_ups}
  end

  def top_up_players(state), do: %{state | top_ups: %{}}

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
    before = state
    state = commit(state, id, committed)
    state = record_action_detail(state, before, id, if(amount == state.small_blind, do: :small_blind, else: :big_blind))
    if Map.fetch!(state.players, id).stack == 0, do: %{state | all_in: MapSet.put(state.all_in, id)}, else: state
  end

  def actions_for(state, id) do
    # Le montant à suivre est la différence entre la mise la plus haute et celle du joueur.
    player = Map.fetch!(state.players, id)
    to_call = state.current_bet - Map.fetch!(state.street_contributions, id)
    # Règle de tour d'enchères : sans mise à suivre, le joueur check ou mise.
    # Fold et call n'ont de sens que lorsqu'il existe déjà une mise adverse à payer.
    passive_actions = if to_call == 0, do: [:check], else: [:call, :fold]
    base = if all_in_available?(state, id), do: passive_actions ++ [:all_in], else: passive_actions

    cond do
      player.stack == 0 -> []
      state.current_bet == 0 and player.stack >= state.big_blind -> [%{bet: %{min: state.big_blind, max: player.stack}} | base]
      state.current_bet > 0 and not MapSet.member?(state.raise_blocked, id) and player.stack + Map.fetch!(state.street_contributions, id) >= state.current_bet + state.min_raise ->
        min_total = state.current_bet + state.min_raise
        max_total = player.stack + Map.fetch!(state.street_contributions, id)
        [%{raise_to: %{min: min_total, max: max_total}} | base]

      true -> base
    end
  end

  def all_in_available?(state, id) do
    not (MapSet.member?(state.raise_blocked, id) and all_in_true_raise?(state, id))
  end

  def all_in_true_raise?(state, id) do
    total = Map.fetch!(state.street_contributions, id) + Map.fetch!(state.players, id).stack
    state.current_bet > 0 and total >= state.current_bet + state.min_raise
  end

  def apply_action(state, id, :fold) do
    # Au poker, se coucher répond à une mise adverse ; sans mise, l'action correcte est check.
    if state.current_bet > Map.fetch!(state.street_contributions, id), do: {:ok, fold_player(state, id)}, else: {:error, :fold_not_allowed}
  end

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

    cond do
      MapSet.member?(state.raise_blocked, id) and all_in_true_raise?(state, id) -> {:error, :raise_not_allowed}
      total <= state.current_bet -> {:ok, commit_and_finish(state, id, player.stack)}
      true -> raise_to(state, id, total)
    end
  end

  def apply_action(_state, _id, _action), do: {:error, :invalid_action}

  def raise_to(state, id, total) do
    player = Map.fetch!(state.players, id)
    previous = Map.fetch!(state.street_contributions, id)
    amount = total - previous
    # Une relance doit augmenter la mise précédente d'au moins `min_raise`, sauf tapis.
    raise_size = total - state.current_bet

    cond do
      not is_integer(total) -> {:error, :invalid_amount}
      amount <= 0 or amount > player.stack -> {:error, :invalid_amount}
      total <= state.current_bet -> {:error, :raise_too_small}
      raise_size < state.min_raise and amount != player.stack -> {:error, :raise_too_small}
      true ->
        full_raise = raise_size >= state.min_raise
        pending_before = state.pending
        state = commit(state, id, amount)
        state = %{state | current_bet: total, min_raise: if(full_raise, do: max(state.min_raise, raise_size), else: state.min_raise)}
        state = if full_raise, do: %{state | street_aggressor: id}, else: state
        state = if full_raise and state.phase == :preflop, do: %{state | preflop_aggressor: id}, else: state
        state = if full_raise and state.phase == :preflop, do: %{state | preflop_raise_count: state.preflop_raise_count + 1}, else: state
        state = update_pending_after_raise(state, id, pending_before, full_raise)
        state = if Map.fetch!(state.players, id).stack == 0, do: %{state | all_in: MapSet.put(state.all_in, id)}, else: state
        {:ok, state}
    end
  end

  def update_pending_after_raise(state, id, _pending_before, true) do
    %{state | pending: pending_players(state, MapSet.new([id])), raise_blocked: MapSet.new()}
  end

  def update_pending_after_raise(state, id, pending_before, false) do
    candidates =
      state.hand_players
      |> MapSet.difference(state.folded)
      |> MapSet.difference(state.all_in)
      |> MapSet.delete(id)
      |> Enum.filter(&(Map.fetch!(state.street_contributions, &1) < state.current_bet))
      |> MapSet.new()

    # Un tapis inférieur au min-raise permet de payer le complément, mais ne rouvre pas la relance.
    blocked = MapSet.difference(candidates, MapSet.delete(pending_before, id))
    %{state | pending: candidates, raise_blocked: MapSet.union(state.raise_blocked, blocked)}
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

  def record_action_detail(state, before, id, action) do
    before_player = Map.fetch!(before.players, id)
    after_player = Map.fetch!(state.players, id)
    before_street = Map.get(before.street_contributions, id, 0)
    after_street = Map.get(state.street_contributions, id, 0)

    # Chaque ligne garde les stacks et pots avant/après pour permettre une analyse externe exhaustive.
    entry = %{
      street: before.phase,
      player: id,
      action: action_label(action),
      amount: max(after_street - before_street, 0),
      stack_before: before_player.stack,
      stack_after: after_player.stack,
      contribution_before: Map.get(before.hand_contributions, id, 0),
      contribution_after: Map.get(state.hand_contributions, id, 0),
      pot_before: Enum.sum(Map.values(before.hand_contributions)),
      pot_after: Enum.sum(Map.values(state.hand_contributions))
    }

    %{state | current_hand_actions: state.current_hand_actions ++ [entry]}
  end

  def action_label({:bet, amount}), do: "bet #{amount}"
  def action_label({:raise_to, amount}), do: "raise_to #{amount}"
  def action_label(action), do: Atom.to_string(action)

  def fold_player(state, id) do
    %{state | folded: MapSet.put(state.folded, id), pending: MapSet.delete(state.pending, id)}
  end

  def remove_pending(state, id), do: %{state | pending: MapSet.delete(state.pending, id), raise_blocked: MapSet.delete(state.raise_blocked, id)}

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
        street_aggressor: nil,
        pending: pending,
        raise_blocked: MapSet.new(),
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
           seat: Map.fetch!(state.players, id).seat,
           starting_stack: Map.fetch!(state.hand_starting_stacks, id),
           final_stack: Map.fetch!(state.players, id).stack,
           cards: Map.fetch!(state.hole_cards, id),
           contribution: contribution,
           payout: payout,
           profit_loss: payout - contribution,
           result: historical_result(state, id)
         }}
      end)

    hand = %{
      number: state.hand_number,
      dealer: state.dealer,
      board: state.board,
      players: players,
      winners: Map.keys(payouts),
      actions: state.current_hand_actions,
      small_blind: state.small_blind,
      big_blind: state.big_blind
    }

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
        raise_blocked: MapSet.new(),
        leaving: MapSet.new(),
        street_contributions: %{},
        hand_contributions: %{},
        hand_starting_stacks: %{},
        top_ups: %{},
        current_hand_actions: [],
        current_bet: 0,
        preflop_aggressor: nil,
        preflop_raise_count: 0,
        street_aggressor: nil,
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
        position = if MapSet.member?(state.hand_players, id), do: position_for(state, id), else: nil

        {id, Map.merge(Map.take(player, [:id, :seat, :stack]), %{cards: cards, folded: id in state.folded, contribution: Map.get(state.hand_contributions, id, 0), position: position})}
      end)

    %{
      phase: state.phase,
      mode: state.mode,
      hand_number: state.hand_number,
      dealer: state.dealer,
      board: state.board,
      pot: Enum.sum(Map.values(state.hand_contributions)),
      top_ups: state.top_ups,
      players: players,
      active_player: state.active_player,
      small_blind: state.small_blind,
      big_blind: state.big_blind
    }
  end

  def decision_snapshot(state, id) do
    player = Map.fetch!(state.players, id)
    contribution = Map.fetch!(state.street_contributions, id)

    %{
      phase: state.phase,
      cards: Map.fetch!(state.hole_cards, id),
      board: state.board,
      pot: Enum.sum(Map.values(state.hand_contributions)),
      stack: player.stack,
      position: position_for(state, id),
      to_call: state.current_bet - contribution,
      pot_odds: pot_odds(state, contribution),
      bet_size_ratio: bet_size_ratio(state, contribution),
      stack_pressure: stack_pressure(state, player, contribution),
      effective_stack: effective_stack(state, id),
      current_bet: state.current_bet,
      preflop_raise_count: state.preflop_raise_count,
      big_blind: state.big_blind,
      players_in_hand: length(active_ids(state)),
      facing_cbet: state.phase != :preflop and state.current_bet > 0 and state.street_aggressor == state.preflop_aggressor,
      actions: actions_for(state, id)
    }
  end

  def pot_odds(state, contribution) do
    to_call = state.current_bet - contribution
    if to_call > 0, do: to_call / (Enum.sum(Map.values(state.hand_contributions)) + to_call), else: 0.0
  end

  def bet_size_ratio(state, contribution) do
    pot = Enum.sum(Map.values(state.hand_contributions))
    to_call = state.current_bet - contribution
    if pot > 0 and to_call > 0, do: to_call / pot, else: 0.0
  end

  def stack_pressure(state, player, contribution) do
    to_call = state.current_bet - contribution
    if player.stack > 0 and to_call > 0, do: to_call / player.stack, else: 0.0
  end

  def effective_stack(state, id) do
    player_stack = Map.fetch!(state.players, id).stack

    state.hand_players
    |> MapSet.delete(id)
    |> Enum.reject(&MapSet.member?(state.folded, &1))
    |> Enum.map(&Map.fetch!(state.players, &1).stack)
    |> Enum.max(fn -> 0 end)
    |> min(player_stack)
  end

  def position_for(state, id) do
    order = ordered_ids(state, state.dealer, MapSet.to_list(state.hand_players))
    index = Enum.find_index(order, &(&1 == id))

    case {length(order), index} do
      {2, 0} -> :button
      {2, 1} -> :big_blind
      {_count, 0} -> :button
      {_count, 1} -> :small_blind
      {_count, 2} -> :big_blind
      {_count, value} when value == length(order) - 1 -> :cutoff
      {_count, value} when value == length(order) - 2 -> :hijack
      _other -> :early
    end
  end
end
