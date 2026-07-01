defmodule GameSimulator.Tables do
  @moduledoc """
  Accès aux tables temporaires, indexées par leur propriétaire authentifié.
  """

  @default_game_key "poker:cash_nl2"

  def start(owner) do
    case table(owner) do
      {:ok, table} -> {:ok, table}
      :error -> DynamicSupervisor.start_child(GameSimulator.TableSupervisor, {GameSimulator.Table, owner: owner, name: via(owner)})
    end
  end

  def start_new(owner, game_key \\ @default_game_key) do
    :ok = stop(owner)

    DynamicSupervisor.start_child(
      GameSimulator.TableSupervisor,
      {GameSimulator.Table, owner: owner, name: via(owner), game_key: game_key, autosave: true}
    )
  end

  def resume(owner, game_key \\ @default_game_key) do
    case table(owner) do
      {:ok, table} ->
        {:ok, table}

      :error ->
        with {:ok, snapshot} <- GameSimulator.GameSaves.get(owner, game_key) do
          DynamicSupervisor.start_child(
            GameSimulator.TableSupervisor,
            {GameSimulator.Table, owner: owner, name: via(owner), game_key: game_key, autosave: true, snapshot: snapshot}
          )
        else
          {:error, reason} when reason in [:invalid_save, :unsupported_save_version] ->
            _ = GameSimulator.GameSaves.delete(owner, game_key)
            {:error, :not_found}

          {:error, reason} ->
            {:error, reason}
        end
    end
  end

  def save_status(owner, game_key \\ @default_game_key), do: GameSimulator.GameSaves.exists?(owner, game_key)

  def table(owner) do
    case Registry.lookup(GameSimulator.TableRegistry, owner) do
      [{pid, _value}] when is_pid(pid) -> if(Process.alive?(pid), do: {:ok, pid}, else: :error)
      [] -> :error
    end
  end

  def stop(owner) do
    # Terminer le processus ferme aussi le moteur de jeu lié à cette session.
    case table(owner) do
      {:ok, table} -> DynamicSupervisor.terminate_child(GameSimulator.TableSupervisor, table)
      :error -> :ok
    end
  end

  def via(owner), do: {:via, Registry, {GameSimulator.TableRegistry, owner}}
end
