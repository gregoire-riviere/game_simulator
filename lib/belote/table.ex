defmodule Belote.Table do
  @moduledoc """
  Session belote : coordination, sauvegarde et état public.
  """

  use GenServer

  alias Belote.{Decision, Game}

  @call_timeout 15_000

  def child_spec(options), do: %{id: __MODULE__, start: {__MODULE__, :start_link, [options]}, restart: :temporary, type: :worker}
  def start_link(options), do: GenServer.start_link(__MODULE__, options, name: Keyword.fetch!(options, :name))
  def state(table, owner), do: GenServer.call(table, {:state, owner}, @call_timeout)
  def act(table, owner, action), do: GenServer.call(table, {:act, owner, action}, @call_timeout)
  def advance_bot(table, owner), do: GenServer.call(table, {:advance_bot, owner}, @call_timeout)
  def next_deal(table, owner), do: GenServer.call(table, {:next_deal, owner}, @call_timeout)
  def set_llm_mode(table, owner, mode), do: GenServer.call(table, {:set_llm_mode, owner, mode}, @call_timeout)

  @impl true
  def init(options) do
    owner = Keyword.fetch!(options, :owner)
    game_key = Keyword.fetch!(options, :game_key)

    state =
      case Keyword.get(options, :snapshot) do
        %{owner: ^owner, game: game} = snapshot -> %{owner: owner, game_key: game_key, game: Game.new(game), bot_names: Map.get(snapshot, :bot_names, default_bot_names()), llm_mode: Map.get(snapshot, :llm_mode, :local), llm_remaining: Map.get(snapshot, :llm_remaining, 10), saving?: false}
        nil -> %{owner: owner, game_key: game_key, game: Game.new(variant(game_key), Keyword.get(options, :target_score, 1000)), bot_names: random_bot_names(), llm_mode: Keyword.get(options, :llm_mode, :local), llm_remaining: 10, saving?: false}
      end

    {:ok, save(state)}
  end

  @impl true
  def handle_call({:state, owner}, _from, state), do: reply(state, owner)

  def handle_call({:act, owner, action}, _from, state) do
    with :ok <- owner?(state, owner),
         {:ok, game} <- Game.act(state.game, 4, action) do
      reply(save(%{state | game: game}), owner)
    else
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:advance_bot, owner}, _from, state) do
    with :ok <- owner?(state, owner),
         seat when seat in 1..3 <- state.game.turn,
         {action, state} <- bot_action(state, seat),
         {:ok, game} <- Game.act(state.game, seat, action) do
      reply(save(%{state | game: game}), owner)
    else
      4 -> {:reply, {:error, :human_action_required}, state}
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:set_llm_mode, owner, mode}, _from, state) when mode in [:local, :llm] do
    with :ok <- owner?(state, owner),
         true <- mode == :local or GameSimulator.Configuration.llm!().enabled do
      reply(save(%{state | llm_mode: mode}), owner)
    else
      false -> {:reply, {:error, :llm_disabled}, state}
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

  def handle_call({:next_deal, owner}, _from, state) do
    with :ok <- owner?(state, owner),
         true <- state.game.phase == :deal_finished do
      reply(save(%{state | game: Game.new_deal(state.game)}), owner)
    else
      false -> {:reply, {:error, :deal_not_finished}, state}
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  def reply(state, owner), do: {:reply, {:ok, public_state(state, owner)}, state}
  def owner?(%{owner: owner}, owner), do: :ok
  def owner?(_state, _owner), do: {:error, :forbidden}

  def save(%{saving?: false} = state) do
    table = self()
    snapshot = %{version: 1, owner: state.owner, game: state.game, bot_names: Map.get(state, :bot_names, default_bot_names()), llm_mode: state.llm_mode, llm_remaining: state.llm_remaining}
    Task.start(fn -> GameSimulator.GameSaves.put(state.owner, state.game_key, snapshot); send(table, :saved) end)
    %{state | saving?: true}
  end

  def save(state), do: state
  @impl true
  def handle_info(:saved, state), do: {:noreply, %{state | saving?: false}}
  def variant("belote:classic"), do: :classic
  def variant("belote:coinche"), do: :coinche

  def bot_action(%{llm_mode: :llm, llm_remaining: remaining} = state, seat) when remaining > 0 do
    case Belote.Decision.LLM.decide(state.game, seat, GameSimulator.Configuration.llm!()) do
      {:ok, action} -> {action, %{state | llm_remaining: remaining - 1}}
      {:error, _reason} -> {Decision.decide(state.game, seat), state}
    end
  end

  def bot_action(state, seat), do: {Decision.decide(state.game, seat), state}
  def random_bot_names, do: Poker.Profile.generate(3) |> Enum.map(& &1.name) |> Enum.zip([1, 2, 3]) |> Map.new(fn {name, seat} -> {seat, name} end)
  def default_bot_names, do: Map.new(1..3, fn seat -> {seat, Poker.Profile.bot_name(seat)} end)

  def public_state(state, owner) do
    game = state.game

    %{
      owner: owner,
      game_key: state.game_key,
      format: if(game.variant == :classic, do: "Belote classique", else: "Coinche"),
      target_score: game.target_score,
      phase: game.phase,
      deal_number: game.deal_number,
      turn: game.turn,
      hero_turn: game.turn == 4,
      trump: suit_name(game.trump),
      turned_card: card_text(game.turned_card),
      contract: public_contract(game.contract, game.trump),
      scores: %{hero: game.scores[0], opponents: game.scores[1]},
      deal_points: %{hero: game.deal_points[0], opponents: game.deal_points[1]},
      hand: game.hands[4] |> sort_cards() |> Enum.map(&card_text/1),
      players: Enum.map(1..4, &public_player(state, &1)),
      trick: Enum.map(game.trick, fn entry -> %{seat: entry.seat, card: card_text(entry.card)} end),
      last_trick: Enum.map(Map.get(game, :last_trick, []), fn entry -> %{seat: entry.seat, card: card_text(entry.card)} end),
      last_trick_winner: Map.get(game, :last_trick_winner),
      last_trick_points: Map.get(game, :last_trick_points, 0),
      trick_just_completed: Map.get(game, :trick_just_completed, false),
      deal_history: Enum.reverse(Map.get(game, :deal_history, [])) |> Enum.map(&public_deal(state, &1)),
      actions: if(game.turn == 4, do: Enum.map(Game.legal_actions(game, 4), &public_action/1), else: []),
      last_event: game.last_event,
      match_finished: game.phase == :match_finished,
      llm_mode: state.llm_mode,
      llm_remaining: state.llm_remaining,
      llm_available: GameSimulator.Configuration.llm!().enabled
    }
  end

  def public_player(state, seat), do: %{seat: seat, name: player_name(state, seat), cards: if(seat == 4, do: Enum.map(state.game.hands[seat], &card_text/1), else: "hidden"), card_count: length(state.game.hands[seat]), active: state.game.turn == seat, taker: state.game.contract != nil and state.game.contract.taker == seat, pass_status: pass_status(state.game, seat), team: if(Game.team(seat) == 0, do: "hero", else: "opponents")}
  def pass_status(game, seat) when game.phase in [:classic_first, :classic_second] do
    cond do
      Enum.any?(game.history, &(pass_in_phase?(&1, seat, :classic_second))) -> :second_round
      Enum.any?(game.history, &(pass_in_phase?(&1, seat, :classic_first))) -> :folded
      true -> nil
    end
  end
  def pass_status(_game, _seat), do: nil
  def pass_in_phase?(entry, seat, phase), do: entry.seat == seat and entry.action == :pass and Map.get(entry, :phase) == phase
  def public_contract(nil, _trump), do: nil
  def public_contract(contract, trump), do: %{team: if(contract.team == 0, do: "hero", else: "opponents"), taker: contract.taker, amount: contract.amount, trump: suit_name(Map.get(contract, :suit, trump)), multiplier: contract.multiplier}
  def public_deal(state, deal), do: %{number: deal.number, taker: player_name(state, deal.taker), amount: deal.amount, trump: suit_name(deal.trump), winner: if(deal.winner_team == 0, do: "Votre équipe", else: "Adversaires"), scores: %{hero: deal.scores[0], opponents: deal.scores[1]}}
  def public_action(:pass), do: %{type: "pass"}
  def public_action(:coinche), do: %{type: "coinche"}
  def public_action(:surcoinche), do: %{type: "surcoinche"}
  def public_action({:take, suit}), do: %{type: "take", suit: Atom.to_string(suit)}
  def public_action({:bid, amount, suit}), do: %{type: "bid", amount: amount, suit: Atom.to_string(suit)}
  def public_action({:play, card}), do: %{type: "play", card: card_text(card)}
  def public_history(%{seat: seat, action: action}), do: %{player: player_name(seat), action: inspect(public_action(action))}
  def player_name(4), do: "Vous"
  def player_name(2), do: "Partenaire"
  def player_name(seat), do: "PNJ #{seat}"
  def player_name(_state, 4), do: "Vous"
  def player_name(state, seat), do: Map.fetch!(Map.get(state, :bot_names, default_bot_names()), seat)
  def sort_cards(cards), do: Enum.sort_by(cards, &card_sort_key/1)
  def card_sort_key({suit, rank}), do: {Enum.find_index([:hearts, :spades, :diamonds, :clubs], &(&1 == suit)), Enum.find_index([:seven, :eight, :nine, :ten, :jack, :queen, :king, :ace], &(&1 == rank))}
  def suit_name(nil), do: nil
  def suit_name(suit), do: %{clubs: "♣", diamonds: "♦", hearts: "♥", spades: "♠"}[suit]
  def card_text(nil), do: nil
  def card_text({suit, rank}), do: %{seven: "7", eight: "8", nine: "9", ten: "10", jack: "V", queen: "D", king: "R", ace: "A"}[rank] <> suit_name(suit)
end
