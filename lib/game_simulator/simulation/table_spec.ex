defmodule GameSimulator.Simulation.TableSpec do
  @moduledoc """
  Table configuration for a simulation.

  Blind and stack values are expressed in big blinds.
  """

  defstruct name: nil,
            max_seats: 6,
            small_blind: 0.5,
            big_blind: 1,
            starting_stack: 100
end
