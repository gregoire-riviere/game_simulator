defmodule GameSimulator.Table do
  use GenServer

  def start_link(options) do
    name = Keyword.get(options, :name)
    GenServer.start_link(__MODULE__, options, if(name, do: [name: name], else: []))
  end

  def state(table, owner), do: GenServer.call(table, {:state, owner})
  def act(table, owner, action), do: GenServer.call(table, {:act, owner, action})
  def advance_bot(table, owner), do: GenServer.call(table, {:advance_bot, owner})
  def next_hand(table, owner), do: GenServer.call(table, {:next_hand, owner})

  @impl true
  def init(options) do
    owner = Keyword.fetch!(options, :owner)
    provider = Keyword.get(options, :profile_provider, Poker.LocalProfileProvider)
    {:ok, game} = Poker.Game.start_link(small_blind: 1, big_blind: 2)
    profiles = provider.generate(5)
    human_id = {:human, owner}

    Enum.each(1..5, fn seat ->
      Poker.Game.join(game, {:bot, seat}, 200, seat)
    end)

    Poker.Game.join(game, human_id, 200, 6)
    {:ok, _state} = Poker.Game.start_hand(game)

    profiles = Map.new(Enum.with_index(profiles, 1), fn {profile, seat} -> {{:bot, seat}, profile} end)
    {:ok, %{owner: owner, game: game, human_id: human_id, profiles: profiles, actions: []}}
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
    with :ok <- owner?(state, owner),
         {:ok, %{player_id: id}} <- Poker.Game.next_action(state.game),
         true <- bot?(id),
         {:ok, context} <- Poker.Game.decision_context(state.game, id),
         action = Poker.Decision.decide(Map.fetch!(state.profiles, id), context),
         {:ok, game_state} <- Poker.Game.act(state.game, id, action) do
      state = record_action(state, id, action)
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
         {:ok, _snapshot} <- Poker.Game.start_hand(state.game) do
      reply(%{state | actions: []}, owner)
    else
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  def reply(state, owner), do: {:reply, {:ok, public_state(state, owner)}, state}
  def owner?(%{owner: owner}, owner), do: :ok
  def owner?(_state, _owner), do: {:error, :forbidden}
  def bot?({:bot, _seat}), do: true
  def bot?(_id), do: false

  def record_action(state, id, action) do
    action = %{player: player_name(state, id), action: action_name(action)}
    %{state | actions: Enum.take([action | state.actions], 8)}
  end

  def action_name({:bet, amount}), do: "mise #{amount}"
  def action_name({:raise_to, amount}), do: "relance #{amount}"
  def action_name(action), do: Atom.to_string(action)

  def update_profiles(state, %{phase: :waiting}) do
    [hand | _history] = Poker.Game.history(state.game, 1) |> elem(1)

    profiles =
      Map.new(state.profiles, fn {id, profile} ->
        result = Map.fetch!(hand.players, id)
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

        {id, %{profile | memory: memory}}
      end)

    %{state | profiles: profiles}
  end

  def update_profiles(state, _game_state), do: state

  def public_state(state, owner) do
    {:ok, snapshot} = Poker.Game.public_state(state.game, state.human_id)

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
          active: id == snapshot.active_player
        }
      end)
      |> Enum.sort_by(& &1.seat)

    %{
      owner: owner,
      phase: snapshot.phase,
      dealer: public_id(state, snapshot.dealer),
      board: cards(snapshot.board),
      pot: snapshot.pot,
      small_blind: snapshot.small_blind,
      big_blind: snapshot.big_blind,
      players: players,
      hero_turn: snapshot.active_player == state.human_id,
      hand_finished: snapshot.phase == :waiting,
      last_result: last_result(state, snapshot.phase),
      actions: if(snapshot.active_player == state.human_id, do: Poker.Game.next_action(state.game) |> elem(1) |> Map.fetch!(:actions), else: []),
      recent_actions: Enum.reverse(state.actions)
    }
  end

  def public_id(state, id), do: if(id == state.human_id, do: "hero", else: "bot-#{elem(id, 1)}")
  def player_name(state, id), do: if(id == state.human_id, do: state.owner, else: Map.fetch!(state.profiles, id).name)
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
