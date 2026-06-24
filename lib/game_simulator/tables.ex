defmodule GameSimulator.Tables do
  @moduledoc """
  Accès aux tables temporaires, indexées par leur propriétaire authentifié.
  """

  def start(owner) do
    case table(owner) do
      {:ok, table} -> {:ok, table}
      :error -> DynamicSupervisor.start_child(GameSimulator.TableSupervisor, {GameSimulator.Table, owner: owner, name: via(owner)})
    end
  end

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
