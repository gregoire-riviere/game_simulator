defmodule MrWhite.Table do
  @moduledoc """
  Partie temporaire de Mr. White appartenant à un utilisateur authentifié.
  """

  use GenServer

  def child_spec(options) do
    %{id: __MODULE__, start: {__MODULE__, :start_link, [options]}, restart: :temporary, type: :worker}
  end

  def start_link(options) do
    name = Keyword.get(options, :name)
    GenServer.start_link(__MODULE__, options, if(name, do: [name: name], else: []))
  end

  def state(table, owner), do: GenServer.call(table, {:state, owner})
  def secret(table, owner), do: GenServer.call(table, {:secret, owner})
  def act(table, owner, action), do: GenServer.call(table, {:act, owner, action})
  def restart(table, owner), do: GenServer.call(table, {:restart, owner})

  @impl true
  def init(options) do
    owner = Keyword.fetch!(options, :owner)

    case MrWhite.Game.new(Keyword.fetch!(options, :players)) do
      {:ok, game} -> {:ok, %{owner: owner, game: game}}
      {:error, reason} -> {:stop, reason}
    end
  end

  @impl true
  def handle_call({:state, owner}, _from, state), do: reply_if_owner(state, owner, fn game -> {:ok, MrWhite.Game.public_state(game)} end)

  def handle_call({:secret, owner}, _from, state) do
    reply_if_owner(state, owner, fn game -> MrWhite.Game.secret(game) end)
  end

  def handle_call({:act, owner, action}, _from, state) do
    if state.owner == owner do
      case MrWhite.Game.act(state.game, action) do
        {:ok, game} -> {:reply, {:ok, MrWhite.Game.public_state(game)}, %{state | game: game}}
        {:error, reason} -> {:reply, {:error, reason}, state}
      end
    else
      {:reply, {:error, :forbidden}, state}
    end
  end

  def handle_call({:restart, owner}, _from, state) do
    if state.owner == owner do
      names = Enum.map(state.game.players, & &1.name)
      {:ok, game} = MrWhite.Game.new(names)
      {:reply, {:ok, MrWhite.Game.public_state(game)}, %{state | game: game}}
    else
      {:reply, {:error, :forbidden}, state}
    end
  end

  def reply_if_owner(state, owner, fun) do
    if state.owner == owner,
      do: {:reply, fun.(state.game), state},
      else: {:reply, {:error, :forbidden}, state}
  end
end
