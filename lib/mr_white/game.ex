defmodule MrWhite.Game do
  @moduledoc """
  Moteur déterministe des phases et règles d'une partie de Mr. White.

  Le hasard ne sert qu'à préparer une partie. Une fois l'état créé, toutes les
  transitions sont validées ici sans décision confiée au navigateur.
  """

  @roles [:mr_white, :spy, :civil]

  def new(names, options \\ []) do
    with {:ok, names} <- validate_names(names) do
      pair = Keyword.get_lazy(options, :word_pair, &MrWhite.Words.random_pair/0)
      roles = Keyword.get_lazy(options, :roles, fn -> Enum.shuffle([:mr_white, :spy] ++ List.duplicate(:civil, length(names) - 2)) end)
      players = names |> Enum.with_index(1) |> Enum.zip(roles) |> Enum.map(fn {{name, id}, role} -> %{id: id, name: name, role: role, active: true} end)
      order = Keyword.get_lazy(options, :order, fn -> players |> Enum.map(& &1.id) |> Enum.shuffle() end)

      with :ok <- validate_roles(roles, length(names)),
           :ok <- validate_order(order, players) do
        order = move_mr_white_from_first(order, players)

        {:ok,
         %{
           players: players,
           order: order,
           civilian_word: elem(pair, 0),
           spy_word: elem(pair, 1),
           phase: :reveal,
           reveal_position: 0,
           round: 1,
           eliminated: nil,
           elimination_history: [],
           guess_result: nil,
           end_reason: nil
         }}
      end
    end
  end

  def validate_names(names) when is_list(names) and length(names) in 3..10 do
    normalized = Enum.map(names, fn name -> if is_binary(name), do: String.trim(name), else: "" end)
    unique = normalized |> Enum.map(&String.downcase/1) |> Enum.uniq()

    if Enum.all?(normalized, &(String.length(&1) in 1..40)) and length(unique) == length(normalized) do
      {:ok, normalized}
    else
      {:error, :invalid_players}
    end
  end

  def validate_names(_names), do: {:error, :invalid_players}

  def validate_roles(roles, player_count) do
    valid = length(roles) == player_count and Enum.all?(roles, &(&1 in @roles))
    counts = Enum.frequencies(roles)

    if valid and counts[:mr_white] == 1 and counts[:spy] == 1 and counts[:civil] == player_count - 2,
      do: :ok,
      else: {:error, :invalid_roles}
  end

  def validate_order(order, players) do
    ids = Enum.map(players, & &1.id)
    if Enum.sort(order) == Enum.sort(ids), do: :ok, else: {:error, :invalid_order}
  end

  def move_mr_white_from_first([first | rest] = order, players) do
    if player(first, players).role == :mr_white do
      [replacement | remaining] = rest
      [replacement, first | remaining]
    else
      order
    end
  end

  def current_reveal_player(%{phase: :reveal} = state) do
    id = Enum.at(state.order, state.reveal_position)
    {:ok, player(id, state.players)}
  end

  def current_reveal_player(_state), do: {:error, :invalid_phase}

  def secret(state) do
    with {:ok, player} <- current_reveal_player(state) do
      {:ok, player_secret(player, state)}
    end
  end

  def review_secret(%{phase: :vote} = state, id) when is_integer(id) do
    case Enum.find(state.players, &(&1.id == id and &1.active)) do
      nil -> {:error, :invalid_player}
      player -> {:ok, player_secret(player, state)}
    end
  end

  def review_secret(_state, _id), do: {:error, :invalid_phase}

  def player_secret(player, state) do
    word = if player.role == :civil, do: state.civilian_word, else: if(player.role == :spy, do: state.spy_word, else: nil)
    %{player_id: player.id, name: player.name, role: if(player.role == :mr_white, do: :mr_white, else: nil), word: word}
  end

  def act(%{phase: :reveal} = state, :confirm_reveal) do
    next_position = state.reveal_position + 1

    if next_position == length(state.order) do
      {:ok, %{state | phase: :vote, reveal_position: next_position}}
    else
      {:ok, %{state | reveal_position: next_position}}
    end
  end

  def act(%{phase: :vote} = state, {:eliminate, id}) when is_integer(id) do
    case Enum.find(state.players, &(&1.id == id and &1.active)) do
      nil -> {:error, :invalid_player}
      eliminated -> eliminate(state, eliminated)
    end
  end

  def act(%{phase: :elimination, eliminated: %{role: :mr_white}, guess_result: nil} = state, {:mr_white_guess, accepted}) when is_boolean(accepted) do
    if accepted do
      {:ok, %{state | phase: :finished, guess_result: :accepted, end_reason: :mr_white_guess_accepted}}
    else
      state = %{state | guess_result: :rejected}
      {:ok, finish_if_needed(state)}
    end
  end

  def act(%{phase: :elimination, end_reason: nil} = state, :next_round) do
    if state.eliminated.role != :mr_white or state.guess_result == :rejected do
      {:ok, %{state | phase: :vote, round: state.round + 1, eliminated: nil, guess_result: nil}}
    else
      {:error, :mr_white_guess_required}
    end
  end

  def act(_state, _action), do: {:error, :invalid_action}

  def eliminate(state, eliminated) do
    players = Enum.map(state.players, fn player -> if player.id == eliminated.id, do: %{player | active: false}, else: player end)
    revealed = Map.take(eliminated, [:id, :name, :role])

    state = %{
      state
      | players: players,
        phase: :elimination,
        eliminated: revealed,
        elimination_history: state.elimination_history ++ [revealed],
        guess_result: nil
    }

    if eliminated.role == :mr_white, do: {:ok, state}, else: {:ok, finish_if_needed(state)}
  end

  def finish_if_needed(state) do
    active = Enum.filter(state.players, & &1.active)
    infiltrators = Enum.filter(active, &(&1.role in [:mr_white, :spy]))

    cond do
      infiltrators == [] -> %{state | phase: :finished, end_reason: :both_infiltrators_eliminated}
      length(active) == 2 -> %{state | phase: :finished, end_reason: :two_players_remaining}
      true -> state
    end
  end

  def public_state(state) do
    finished = state.phase == :finished
    revealed_ids = MapSet.new(Enum.map(state.elimination_history, & &1.id))

    %{
      phase: state.phase,
      round: state.round,
      reveal_player: reveal_player_summary(state),
      players: Enum.map(state.players, &public_player(&1, state.order, finished, revealed_ids)),
      order: state.order,
      eliminated: state.eliminated,
      guess_result: state.guess_result,
      end_reason: state.end_reason,
      words: if(finished, do: %{civil: state.civilian_word, spy: state.spy_word}, else: nil)
    }
  end

  def reveal_player_summary(%{phase: :reveal} = state) do
    {:ok, current} = current_reveal_player(state)
    %{id: current.id, name: current.name, number: state.reveal_position + 1, total: length(state.order)}
  end

  def reveal_player_summary(_state), do: nil

  def public_player(player, order, finished, revealed_ids) do
    %{
      id: player.id,
      name: player.name,
      active: player.active,
      position: Enum.find_index(order, &(&1 == player.id)) + 1,
      role: if(finished or MapSet.member?(revealed_ids, player.id), do: player.role, else: nil)
    }
  end

  def player(id, players), do: Enum.find(players, &(&1.id == id))
end
