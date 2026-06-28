defmodule GameSimulator.Table do
  @moduledoc """
  Session temporaire d'un utilisateur : une table, son héros et cinq PNJ.

  Cette couche coordonne le moteur, les profils et l'API. Elle ne réimplémente
  jamais les règles de poker, qui restent dans `Poker.Game`.
  """

  use GenServer

  def child_spec(options) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [options]},
      restart: :temporary,
      type: :worker
    }
  end

  def start_link(options) do
    name = Keyword.get(options, :name)
    GenServer.start_link(__MODULE__, options, if(name, do: [name: name], else: []))
  end

  def state(table, owner), do: GenServer.call(table, {:state, owner})
  def act(table, owner, action), do: GenServer.call(table, {:act, owner, action})
  def advance_bot(table, owner), do: GenServer.call(table, {:advance_bot, owner})
  def next_hand(table, owner), do: GenServer.call(table, {:next_hand, owner})
  def extract(table, owner, count), do: GenServer.call(table, {:extract, owner, count})
  def set_llm_mode(table, owner, mode), do: GenServer.call(table, {:set_llm_mode, owner, mode})

  @impl true
  def init(options) do
    # La table V1 est toujours 6-max : le héros reçoit le siège 6, les PNJ les autres.
    owner = Keyword.fetch!(options, :owner)
    mode = Keyword.get(options, :mode, :cash_nl2)
    provider = Keyword.get(options, :profile_provider, Poker.LocalProfileProvider)
    {:ok, game} = Poker.Game.start_link(small_blind: 1, big_blind: 2, mode: mode, min_stack: 80, top_up_to: 200)
    profiles = provider.generate(5)
    human_id = {:human, owner}

    Enum.each(1..5, fn seat ->
      Poker.Game.join(game, {:bot, seat}, 200, seat)
    end)

    Poker.Game.join(game, human_id, 200, 6)
    {:ok, _state} = Poker.Game.start_hand(game)

    profiles = Map.new(Enum.with_index(profiles, 1), fn {profile, seat} -> {{:bot, seat}, profile} end)
    {:ok, %{owner: owner, game: game, human_id: human_id, profiles: profiles, actions: [], hand_actions: [], llm_mode: :shadow, mode: mode}}
  end

  @impl true
  def handle_call({:state, owner}, _from, state) do
    case owner?(state, owner) do
      :ok -> reply(state, owner)
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:act, owner, action}, _from, state) do
    with :ok <- owner?(state, owner),
         {:ok, game_state} <- Poker.Game.act(state.game, state.human_id, action) do
      state = record_action(state, state.human_id, action)
      state = update_profiles(state, game_state)
      reply(state, owner)
    else
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:advance_bot, owner}, _from, state) do
    # Le navigateur demande une seule action PNJ ; cela permet de la voir à l'écran.
    with :ok <- owner?(state, owner),
         {:ok, %{player_id: id}} <- Poker.Game.next_action(state.game),
         true <- bot?(id),
         {:ok, context} <- Poker.Game.decision_context(state.game, id),
         decision = Poker.Decision.Router.decide(Map.fetch!(state.profiles, id), context, decision_metadata(state, id)),
         action = decision.action,
         {:ok, game_state} <- Poker.Game.act(state.game, id, action) do
      state = record_action(state, id, action, decision.llm_shadow, decision.local_action, decision.llm_applied)
      state = update_profiles(state, game_state)
      reply(state, owner)
    else
      false -> {:reply, {:error, :human_action_required}, state}
      {:error, :no_action_required} -> {:reply, {:error, :no_action_required}, state}
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:next_hand, owner}, _from, state) do
    with :ok <- owner?(state, owner),
         :ok <- hero_has_chips(state),
         {:ok, snapshot} <- Poker.Game.start_hand(state.game) do
      state = %{state | actions: [], hand_actions: []} |> record_top_ups(snapshot)
      reply(state, owner)
    else
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:extract, owner, count}, _from, state) do
    with :ok <- owner?(state, owner),
         {:ok, count} <- valid_extract_count(count),
         {:ok, hands} <- Poker.Game.history(state.game, count) do
      {:reply, {:ok, %{count: length(hands), format: "markdown", text: extract_text(state, hands)}}, state}
    else
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:set_llm_mode, owner, mode}, _from, state) when mode in [:llm, :shadow, :off] do
    with :ok <- owner?(state, owner) do
      state = %{state | llm_mode: mode}
      reply(state, owner)
    else
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:set_llm_mode, owner, _mode}, _from, state) do
    with :ok <- owner?(state, owner) do
      {:reply, {:error, :invalid_llm_mode}, state}
    else
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  def reply(state, owner), do: {:reply, {:ok, public_state(state, owner)}, state}
  def owner?(%{owner: owner}, owner), do: :ok
  def owner?(_state, _owner), do: {:error, :forbidden}
  def bot?({:bot, _seat}), do: true
  def bot?(_id), do: false

  def hero_has_chips(state) do
    # Une cave vide ne peut pas entrer dans une nouvelle main ; le recave viendra plus tard.
    {:ok, snapshot} = Poker.Game.public_state(state.game, state.human_id)
    if state.mode == :cash_nl2 or snapshot.players[state.human_id].stack > 0, do: :ok, else: {:error, :hero_busted}
  end

  def decision_metadata(state, id) do
    game_state = Poker.Game.internal_state(state.game)
    llm_config = GameSimulator.Configuration.llm!()

    %{
      hand_id: "#{:erlang.phash2(state.owner)}-#{game_state.hand_number}",
      hand_number: game_state.hand_number,
      player_id: public_id(state, id),
      player_name: player_name(state, id),
      hero_in_hand: hero_in_hand?(game_state, state.human_id),
      previous_aggressive_action: previous_aggressive_action?(game_state),
      llm_config: %{llm_config | enabled: llm_config.enabled and state.llm_mode != :off, mode: state.llm_mode}
    }
  end

  def hero_in_hand?(game_state, human_id) do
    MapSet.member?(game_state.hand_players, human_id) and not MapSet.member?(game_state.folded, human_id)
  end

  def previous_aggressive_action?(%{current_hand_actions: actions}) do
    case List.last(actions) do
      %{action: action, amount: amount} -> aggressive_action?(action, amount)
      _other -> false
    end
  end

  def aggressive_action?("all_in", _amount), do: true
  def aggressive_action?("bet " <> _amount, amount), do: amount >= 0
  def aggressive_action?("raise_to " <> _amount, amount), do: amount >= 0
  def aggressive_action?(_action, _amount), do: false

  def record_action(state, id, action), do: record_action(state, id, action, nil, action, false)
  def record_action(state, id, action, llm_shadow), do: record_action(state, id, action, llm_shadow, action, false)
  def record_action(state, id, action, llm_shadow, local_action), do: record_action(state, id, action, llm_shadow, local_action, false)

  def record_action(state, id, action, llm_shadow, local_action, llm_applied) do
    action = action_entry(state, id, action, llm_shadow, local_action, llm_applied)
    %{state | actions: Enum.take([action | state.actions], 8), hand_actions: [action | state.hand_actions]}
  end

  def action_entry(state, id, action, nil, _local_action, _llm_applied), do: %{player: player_name(state, id), action: action_name(action)}

  def action_entry(state, id, action, llm_shadow, local_action, llm_applied) do
    %{
      player: player_name(state, id),
      action: action_name(action),
      played_action: Poker.Decision.Router.local_action_map(local_action),
      llm_shadow: llm_shadow,
      llm_applied: llm_applied
    }
  end

  def record_top_ups(state, %{top_ups: top_ups}) do
    Enum.reduce(top_ups, state, fn {id, amount}, state ->
      action = %{player: player_name(state, id), action: "recave #{amount}"}
      %{state | actions: Enum.take([action | state.actions], 8)}
    end)
  end

  def action_name({:bet, amount}), do: "mise #{amount}"
  def action_name({:raise_to, amount}), do: "relance #{amount}"
  def action_name(action), do: Atom.to_string(action)

  def update_profiles(state, %{phase: :waiting}) do
    # Le tilt est mis à jour seulement après le règlement complet de la main.
    [hand | _history] = Poker.Game.history(state.game, 1) |> elem(1)

    profiles =
      Map.new(state.profiles, fn {id, profile} ->
        case Map.fetch(hand.players, id) do
          {:ok, result} -> {id, update_profile_memory(profile, result)}

          :error ->
            # Un PNJ à 0 jeton ne participe plus aux mains suivantes.
            # Il garde donc sa mémoire telle quelle au lieu de faire crasher la table.
            {id, profile}
        end
      end)

    %{state | profiles: profiles}
  end

  def update_profiles(state, _game_state), do: state

  def valid_extract_count(count) when is_integer(count) and count in 1..50, do: {:ok, count}
  def valid_extract_count(_count), do: {:error, :invalid_extract_count}

  def extract_text(state, hands) do
    header = [
      "# Export table NL2",
      "",
      "Format: centimes entiers. Blindes: 1/2. Les mains sont listées de la plus récente à la plus ancienne.",
      ""
    ]

    body =
      hands
      |> Enum.with_index(1)
      |> Enum.flat_map(fn {hand, index} -> extract_hand(state, hand, index) end)

    Enum.join(header ++ body, "\n")
  end

  def extract_hand(state, hand, index) do
    [
      "## Main #{Map.get(hand, :number, index)}",
      "",
      "- Dealer: #{player_name(state, hand.dealer)}",
      "- Board: #{cards_text(hand.board)}",
      "- Winners: #{hand.winners |> Enum.map(&player_name(state, &1)) |> Enum.join(", ")}",
      "",
      "### Joueurs",
      Enum.map(hand.players |> Enum.sort_by(fn {_id, player} -> player.seat end), fn {id, player} ->
        "- #{player_name(state, id)} seat=#{player.seat} cards=#{cards_text(player.cards)} stack_start=#{player.starting_stack} contribution=#{player.contribution} payout=#{player.payout} profit_loss=#{player.profit_loss} stack_final=#{player.final_stack} result=#{result_text(player.result)}"
      end),
      "",
      "### Actions",
      Enum.map(hand.actions, &extract_action(state, &1)),
      ""
    ]
    |> List.flatten()
  end

  def extract_action(state, action) do
    "- #{action.street} #{player_name(state, action.player)} #{action.action} amount=#{action.amount} stack=#{action.stack_before}->#{action.stack_after} contribution=#{action.contribution_before}->#{action.contribution_after} pot=#{action.pot_before}->#{action.pot_after}"
  end

  def cards_text(cards), do: cards(cards) |> Enum.join(" ")
  def result_text(:folded), do: "folded"
  def result_text(:won_by_fold), do: "won_by_fold"
  def result_text(%{cards: _cards, hand: hand}), do: "#{hand_category(hand.category)} #{Enum.join(hand.ranks, " ")}"
  def result_text(result), do: inspect(result)

  def update_profile_memory(profile, result) do
    # Le tilt diminue lentement, puis bouge selon les gros pots gagnés ou perdus.
    tilt = max(profile.memory.current_tilt * 0.95, 0.0)
    big_loss = result.profit_loss <= -40
    big_win = result.profit_loss >= 40
    tilt = if big_loss, do: min(1.0, tilt + 0.15), else: tilt
    tilt = if big_win, do: max(0.0, tilt - 0.10), else: tilt

    memory = %{
      profile.memory |
      current_tilt: tilt,
      hands_since_big_loss: if(big_loss, do: 0, else: profile.memory.hands_since_big_loss + 1),
      lost_buyins: profile.memory.lost_buyins + if(big_loss, do: 1, else: 0),
      won_big_pot_recently: big_win
    }

    %{profile | memory: memory}
  end

  def public_state(state, owner) do
    {:ok, snapshot} = Poker.Game.public_state(state.game, state.human_id)
    llm_config = GameSimulator.Configuration.llm!()

    players =
      snapshot.players
      |> Enum.map(fn {id, player} ->
        %{
          id: public_id(state, id),
          name: player_name(state, id),
          seat: player.seat,
          stack: player.stack,
          cards: cards(player.cards),
          folded: player.folded,
          contribution: player.contribution,
          position: position_label(player.position),
          dealer_button: id == snapshot.dealer,
          active: id == snapshot.active_player
        }
      end)
      |> Enum.sort_by(& &1.seat)

    %{
      owner: owner,
      mode: state.mode,
      phase: snapshot.phase,
      hand_number: snapshot.hand_number,
      dealer: public_id(state, snapshot.dealer),
      board: cards(snapshot.board),
      pot: snapshot.pot,
      small_blind: snapshot.small_blind,
      big_blind: snapshot.big_blind,
      players: players,
      hero_turn: snapshot.active_player == state.human_id,
      hand_finished: snapshot.phase == :waiting,
      llm_available: llm_config.enabled,
      llm_mode: state.llm_mode,
      last_result: last_result(state, snapshot.phase),
      actions: if(snapshot.active_player == state.human_id, do: Poker.Game.next_action(state.game) |> elem(1) |> Map.fetch!(:actions), else: []),
      recent_actions: Enum.reverse(state.actions),
      hand_actions: Enum.reverse(state.hand_actions)
    }
  end

  def public_id(state, id), do: if(id == state.human_id, do: "hero", else: "bot-#{elem(id, 1)}")
  def player_name(state, id), do: if(id == state.human_id, do: state.owner, else: Map.fetch!(state.profiles, id).name)
  def position_label(:button), do: "BTN"
  def position_label(:small_blind), do: "SB"
  def position_label(:big_blind), do: "BB"
  def position_label(:cutoff), do: "CO"
  def position_label(:hijack), do: "HJ"
  def position_label(:early), do: "UTG"
  def position_label(_position), do: ""
  def last_result(_state, phase) when phase != :waiting, do: nil

  def last_result(state, :waiting) do
    case Poker.Game.history(state.game, 1) do
      {:ok, [hand]} ->
        %{
          board: cards(hand.board),
          reason: result_reason(hand),
          winners: Enum.map(hand.winners, &winner_result(state, hand, &1))
        }

      _other -> nil
    end
  end

  def winner_result(state, hand, id) do
    result = Map.fetch!(hand.players, id).result

    %{
      name: player_name(state, id),
      cards: result_cards(result),
      hand: result_hand(result)
    }
  end

  def result_cards(%{cards: cards}), do: cards(cards)
  def result_cards(_result), do: []
  def result_hand(%{hand: hand}), do: %{category: hand_category(hand.category), ranks: hand.ranks}
  def result_hand(_result), do: nil
  def result_reason(%{board: board}) when length(board) < 5, do: "Tous les autres joueurs se sont couchés."
  def result_reason(_hand), do: "Meilleure main de cinq cartes au showdown."
  def hand_category(:straight_flush), do: "Quinte flush"
  def hand_category(:four_of_a_kind), do: "Carré"
  def hand_category(:full_house), do: "Full"
  def hand_category(:flush), do: "Couleur"
  def hand_category(:straight), do: "Quinte"
  def hand_category(:three_of_a_kind), do: "Brelan"
  def hand_category(:two_pair), do: "Double paire"
  def hand_category(:pair), do: "Paire"
  def hand_category(:high_card), do: "Carte haute"
  def cards(:hidden), do: :hidden
  def cards(cards), do: Enum.map(cards, &card/1)
  def card({rank, "clubs"}), do: rank <> "♣"
  def card({rank, "diamonds"}), do: rank <> "♦"
  def card({rank, "hearts"}), do: rank <> "♥"
  def card({rank, "spades"}), do: rank <> "♠"
end
