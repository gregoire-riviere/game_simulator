defmodule Belote.Online do
  @moduledoc """
  Salons temporaires de belote en ligne.

  Les joueurs humains occupent les sièges disponibles et les sièges restants
  sont joués par les bots déterministes existants.
  """

  use GenServer

  alias Belote.{Decision, Game, Table}

  @call_timeout 15_000
  @seat_order [4, 2, 1, 3]
  @code_alphabet String.graphemes("ABCDEFGHJKLMNPQRSTUVWXYZ23456789")

  def start_link(_options), do: GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  def create(user, game_key, target_score), do: GenServer.call(__MODULE__, {:create, user, game_key, target_score}, @call_timeout)
  def join(user, code), do: GenServer.call(__MODULE__, {:join, user, code}, @call_timeout)
  def state(user), do: GenServer.call(__MODULE__, {:state, user}, @call_timeout)
  def start_game(user), do: GenServer.call(__MODULE__, {:start_game, user}, @call_timeout)
  def act(user, action), do: GenServer.call(__MODULE__, {:act, user, action}, @call_timeout)
  def next_deal(user), do: GenServer.call(__MODULE__, {:next_deal, user}, @call_timeout)
  def leave(user), do: GenServer.call(__MODULE__, {:leave, user}, @call_timeout)

  @impl true
  def init(_state), do: {:ok, %{lobbies: %{}, users: %{}}}

  @impl true
  def handle_call({:create, user, game_key, target_score}, _from, state) do
    state = remove_user(state, user)
    code = unique_code(state.lobbies)
    lobby = %{code: code, host: user, game_key: game_key, target_score: target_score, status: :waiting, seats: %{4 => user}, game: nil, bot_names: %{}}
    state = %{state | lobbies: Map.put(state.lobbies, code, lobby), users: Map.put(state.users, user, code)}
    {:reply, {:ok, public_state(lobby, user)}, state}
  end

  def handle_call({:join, user, raw_code}, _from, state) do
    code = normalize_code(raw_code)

    if Map.get(state.users, user) == code do
      with {:ok, lobby} <- lobby(state, code) do
        {:reply, {:ok, public_state(lobby, user)}, state}
      else
        {:error, reason} -> {:reply, {:error, reason}, state}
      end
    else
      state = remove_user(state, user)

      with {:ok, lobby} <- lobby(state, code),
           :ok <- waiting?(lobby),
           :ok <- room_available?(lobby) do
        seat = Enum.find(@seat_order, &(not Map.has_key?(lobby.seats, &1)))
        lobby = %{lobby | seats: Map.put(lobby.seats, seat, user)}
        state = %{state | lobbies: Map.put(state.lobbies, code, lobby), users: Map.put(state.users, user, code)}
        {:reply, {:ok, public_state(lobby, user)}, state}
      else
        {:error, reason} -> {:reply, {:error, reason}, state}
      end
    end
  end

  def handle_call({:state, user}, _from, state) do
    with {:ok, lobby} <- user_lobby(state, user) do
      {:reply, {:ok, public_state(lobby, user)}, state}
    else
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:start_game, user}, _from, state) do
    with {:ok, lobby} <- user_lobby(state, user),
         :ok <- host?(lobby, user),
         :ok <- waiting?(lobby) do
      game = Game.new(variant(lobby.game_key), lobby.target_score)
      lobby = %{lobby | status: :playing, game: game, bot_names: bot_names(lobby.seats)} |> advance_bots()
      state = %{state | lobbies: Map.put(state.lobbies, lobby.code, lobby)}
      {:reply, {:ok, public_state(lobby, user)}, state}
    else
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:act, user, action}, _from, state) do
    with {:ok, lobby} <- user_lobby(state, user),
         :ok <- playing?(lobby),
         {:ok, seat} <- user_seat(lobby, user),
         {:ok, game} <- Game.act(lobby.game, seat, action) do
      lobby = %{lobby | game: game} |> advance_bots()
      state = %{state | lobbies: Map.put(state.lobbies, lobby.code, lobby)}
      {:reply, {:ok, public_state(lobby, user)}, state}
    else
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:next_deal, user}, _from, state) do
    with {:ok, lobby} <- user_lobby(state, user),
         :ok <- host?(lobby, user),
         :ok <- playing?(lobby),
         true <- lobby.game.phase == :deal_finished do
      lobby = %{lobby | game: Game.new_deal(lobby.game)} |> advance_bots()
      state = %{state | lobbies: Map.put(state.lobbies, lobby.code, lobby)}
      {:reply, {:ok, public_state(lobby, user)}, state}
    else
      false -> {:reply, {:error, :deal_not_finished}, state}
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:leave, user}, _from, state), do: {:reply, :ok, remove_user(state, user)}

  def remove_user(state, user) do
    case Map.fetch(state.users, user) do
      :error -> state
      {:ok, code} -> remove_user_from_lobby(state, user, code)
    end
  end

  def remove_user_from_lobby(state, user, code) do
    lobby = Map.get(state.lobbies, code)
    users = Map.delete(state.users, user)

    cond do
      lobby == nil -> %{state | users: users}
      lobby.status == :waiting and lobby.host == user -> close_lobby(state, lobby)
      true ->
        seats = lobby.seats |> Enum.reject(fn {_seat, username} -> username == user end) |> Map.new()
        remaining_users = Map.values(seats)

        if remaining_users == [] do
          %{state | lobbies: Map.delete(state.lobbies, code), users: users}
        else
          host = if lobby.host == user, do: hd(remaining_users), else: lobby.host
          lobby = %{lobby | seats: seats, host: host}
          lobby = if lobby.status == :playing, do: %{lobby | bot_names: bot_names(seats)} |> advance_bots(), else: lobby
          %{state | lobbies: Map.put(state.lobbies, code, lobby), users: users}
        end
    end
  end

  def close_lobby(state, lobby) do
    users = Enum.reduce(Map.values(lobby.seats), state.users, &Map.delete(&2, &1))
    %{state | lobbies: Map.delete(state.lobbies, lobby.code), users: users}
  end

  def advance_bots(%{status: :playing, game: %{phase: phase}} = lobby) when phase not in [:deal_finished, :match_finished] do
    if Map.has_key?(lobby.seats, lobby.game.turn) do
      lobby
    else
      seat = lobby.game.turn
      action = Decision.decide(lobby.game, seat)

      case Game.act(lobby.game, seat, action) do
        {:ok, game} -> advance_bots(%{lobby | game: game})
        {:error, _reason} -> lobby
      end
    end
  end

  def advance_bots(lobby), do: lobby

  def public_state(%{status: :waiting} = lobby, user) do
    %{
      online: true,
      status: :waiting,
      code: lobby.code,
      host: lobby.host,
      is_host: lobby.host == user,
      game_key: lobby.game_key,
      target_score: lobby.target_score,
      players: lobby_players(lobby, user),
      player_count: map_size(lobby.seats),
      capacity: 4
    }
  end

  def public_state(%{status: :playing} = lobby, user) do
    {:ok, seat} = user_seat(lobby, user)
    game = lobby.game
    team = Game.team(seat)
    opponent_team = 1 - team

    %{
      online: true,
      status: :playing,
      code: lobby.code,
      host: lobby.host,
      is_host: lobby.host == user,
      can_next_deal: lobby.host == user and game.phase == :deal_finished,
      game_key: lobby.game_key,
      format: if(game.variant == :classic, do: "Belote classique", else: "Coinche"),
      target_score: game.target_score,
      phase: game.phase,
      deal_number: game.deal_number,
      turn: game.turn,
      hero_turn: game.turn == seat,
      seat: seat,
      trump: Table.suit_name(game.trump),
      turned_card: Table.card_text(game.turned_card),
      contract: public_contract(game.contract, game.trump, team),
      scores: %{hero: game.scores[team], opponents: game.scores[opponent_team]},
      deal_points: %{hero: game.deal_points[team], opponents: game.deal_points[opponent_team]},
      hand: game.hands[seat] |> Table.sort_cards() |> Enum.map(&Table.card_text/1),
      players: Enum.map(1..4, &public_player(lobby, user, &1)),
      trick: Enum.map(game.trick, fn entry -> %{seat: entry.seat, card: Table.card_text(entry.card)} end),
      last_trick: Enum.map(Map.get(game, :last_trick, []), fn entry -> %{seat: entry.seat, card: Table.card_text(entry.card)} end),
      last_trick_winner: Map.get(game, :last_trick_winner),
      last_trick_points: Map.get(game, :last_trick_points, 0),
      trick_just_completed: Map.get(game, :trick_just_completed, false),
      deal_history: Enum.reverse(Map.get(game, :deal_history, [])) |> Enum.map(&public_deal(lobby, team, &1)),
      actions: if(game.turn == seat, do: Enum.map(Game.legal_actions(game, seat), &Table.public_action/1), else: []),
      last_event: game.last_event,
      match_finished: game.phase == :match_finished,
      llm_mode: :local,
      llm_remaining: 0,
      llm_available: false
    }
  end

  def lobby_players(lobby, user) do
    Enum.map(@seat_order, fn seat ->
      case Map.get(lobby.seats, seat) do
        nil -> %{seat: seat, name: "En attente", human: false, empty: true, self: false}
        username -> %{seat: seat, name: username, human: true, empty: false, self: username == user}
      end
    end)
  end

  def public_player(lobby, user, seat) do
    {:ok, user_seat} = user_seat(lobby, user)
    username = Map.get(lobby.seats, seat)
    name = username || Map.fetch!(lobby.bot_names, seat)

    %{
      seat: seat,
      name: if(username == user, do: "Vous", else: name),
      human: username != nil,
      cards: if(seat == user_seat, do: Enum.map(lobby.game.hands[seat], &Table.card_text/1), else: "hidden"),
      card_count: length(lobby.game.hands[seat]),
      active: lobby.game.turn == seat,
      taker: lobby.game.contract != nil and lobby.game.contract.taker == seat,
      pass_status: Table.pass_status(lobby.game, seat),
      team: if(Game.team(seat) == Game.team(user_seat), do: "hero", else: "opponents")
    }
  end

  def public_contract(nil, _trump, _team), do: nil
  def public_contract(contract, trump, team), do: %{team: if(contract.team == team, do: "hero", else: "opponents"), taker: contract.taker, amount: contract.amount, trump: Table.suit_name(Map.get(contract, :suit, trump)), multiplier: contract.multiplier}

  def public_deal(lobby, team, deal) do
    %{
      number: deal.number,
      taker: player_name(lobby, deal.taker),
      amount: deal.amount,
      trump: Table.suit_name(deal.trump),
      winner: if(deal.winner_team == team, do: "Votre équipe", else: "Adversaires"),
      scores: %{hero: deal.scores[team], opponents: deal.scores[1 - team]}
    }
  end

  def player_name(lobby, seat), do: Map.get(lobby.seats, seat) || Map.fetch!(lobby.bot_names, seat)
  def bot_names(seats), do: Map.new(1..4, fn seat -> {seat, if(Map.has_key?(seats, seat), do: Map.fetch!(seats, seat), else: Poker.Profile.bot_name(seat))} end)
  def variant("belote:classic"), do: :classic
  def variant("belote:coinche"), do: :coinche

  def unique_code(lobbies) do
    code = 1..5 |> Enum.map(fn _index -> Enum.random(@code_alphabet) end) |> Enum.join()
    if Map.has_key?(lobbies, code), do: unique_code(lobbies), else: code
  end

  def normalize_code(code) when is_binary(code), do: code |> String.trim() |> String.upcase()
  def normalize_code(_code), do: ""

  def lobby(state, code) do
    case Map.fetch(state.lobbies, code) do
      {:ok, lobby} -> {:ok, lobby}
      :error -> {:error, :lobby_not_found}
    end
  end

  def user_lobby(state, user) do
    case Map.fetch(state.users, user) do
      {:ok, code} -> lobby(state, code)
      :error -> {:error, :lobby_not_found}
    end
  end

  def user_seat(lobby, user) do
    case Enum.find(lobby.seats, fn {_seat, username} -> username == user end) do
      {seat, _username} -> {:ok, seat}
      nil -> {:error, :forbidden}
    end
  end

  def host?(%{host: user}, user), do: :ok
  def host?(_lobby, _user), do: {:error, :host_required}
  def waiting?(%{status: :waiting}), do: :ok
  def waiting?(_lobby), do: {:error, :game_already_started}
  def playing?(%{status: :playing}), do: :ok
  def playing?(_lobby), do: {:error, :game_not_started}
  def room_available?(lobby), do: if(map_size(lobby.seats) < 4, do: :ok, else: {:error, :lobby_full})
end
