defmodule GameSimulator.Simulation.Session do
  @moduledoc """
  Simulation session state decoupled from poker rules.
  """

  alias GameSimulator.Simulation.TableSpec

  defstruct id: nil,
            table: %TableSpec{},
            bots: [],
            hand_count: 0
end
