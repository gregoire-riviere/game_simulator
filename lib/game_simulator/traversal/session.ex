defmodule GameSimulator.Traversal.Session do
  @moduledoc "One temporary authoritative game per authenticated user, isolated from other tables."
  use GenServer
  alias GameSimulator.Traversal.{Game, Bot}

  def start_link(user), do: GenServer.start_link(__MODULE__, user, name: via(user))
  def via(user), do: {:via, Registry, {GameSimulator.TableRegistry, {:traversal, user}}}
  def child_spec(user), do: %{id: {__MODULE__, user}, start: {__MODULE__, :start_link, [user]}, restart: :temporary}

  def server(user) do
    case Registry.lookup(GameSimulator.TableRegistry, {:traversal, user}) do
      [{pid, _}] -> {:ok, pid}
      [] ->
        case DynamicSupervisor.start_child(GameSimulator.TableSupervisor, {__MODULE__, user}) do
          {:error, {:already_started, pid}} -> {:ok, pid}
          result -> result
        end
    end
  end

  def request(user, command) do
    with {:ok, pid} <- server(user), do: GenServer.call(pid, command, 5_000)
  end

  def init(_user), do: {:ok, nil, 1_800_000}

  def handle_call(:get, _from, state), do: {:reply, {:ok, public(state)}, state, 1_800_000}
  def handle_call({:new, board, difficulty}, from, state), do: handle_call({:new, board, difficulty, nil}, from, state)
  def handle_call({:new, board, difficulty, seed}, _from, state) do
    if Game.valid_board?(board) and difficulty in ["easy", "medium", "hard"] and (seed == nil or (is_binary(seed) and String.length(seed) <= 80)) do
      next = %{game: Game.new(board), seed: seed, difficulty: difficulty, revision: 0, id: Base.url_encode64(:crypto.strong_rand_bytes(18), padding: false)}
      {:reply, {:ok, public(next)}, next, 1_800_000}
    else
      {:reply, {:error, :invalid_game}, state, 1_800_000}
    end
  end
  def handle_call({:move, params}, _from, state) do
    cond do
      state == nil -> {:reply, {:error, :no_game}, state, 1_800_000}
      params["game_id"] != state.id or params["revision"] != state.revision -> {:reply, {:error, :stale_game}, state, 1_800_000}
      state.game.turn != 1 or state.game.result != nil -> {:reply, {:error, :not_your_turn}, state, 1_800_000}
      true ->
        case Game.play(state.game, params["piece"], params["row"], params["col"]) do
          {:error, reason} -> {:reply, {:error, reason}, state, 1_800_000}
          {:ok, game} ->
            next = %{state | game: game, revision: state.revision + 1}
            if game.result == nil, do: send(self(), {:bot, next.id, next.revision})
            {:reply, {:ok, public(next)}, next, 1_800_000}
        end
    end
  end

  def handle_info({:bot, id, revision}, %{id: id, revision: revision, game: %{turn: 2, result: nil}} = state) do
    case Bot.choose(state.game, state.difficulty) do
      nil -> {:noreply, state, 1_800_000}
      move -> {:noreply, %{state | game: Game.apply_action(state.game, move), revision: revision + 1}, 1_800_000}
    end
  end
  def handle_info({:bot, _id, _revision}, state), do: {:noreply, state, 1_800_000}
  def handle_info(:timeout, state), do: {:stop, :normal, state}

  def public(nil), do: %{game: nil}
  def public(state) do
    actions = Game.actions(state.game)
    game = Map.drop(state.game, [:history])
    %{game: game, seed: state.seed, game_id: state.id, revision: state.revision, difficulty: state.difficulty, legal: if(game.turn == 1, do: actions, else: []), thinking: game.turn == 2 and game.result == nil and actions != [], blocked: game.result == nil and actions == []}
  end
end
