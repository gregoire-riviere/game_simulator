defmodule GameSimulator.Tables do
  def start(owner) do
    case table(owner) do
      {:ok, table} -> {:ok, table}
      :error -> DynamicSupervisor.start_child(GameSimulator.TableSupervisor, {GameSimulator.Table, owner: owner, name: via(owner)})
    end
  end

  def table(owner) do
    case Registry.lookup(GameSimulator.TableRegistry, owner) do
      [{pid, _value}] -> {:ok, pid}
      [] -> :error
    end
  end

  def stop(owner) do
    case table(owner) do
      {:ok, table} -> DynamicSupervisor.terminate_child(GameSimulator.TableSupervisor, table)
      :error -> :ok
    end
  end

  def via(owner), do: {:via, Registry, {GameSimulator.TableRegistry, owner}}
end
