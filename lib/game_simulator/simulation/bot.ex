defmodule GameSimulator.Simulation.Bot do
  @moduledoc """
  Simulated poker player with a profile, memory and stack in big blinds.
  """

  alias GameSimulator.Simulation.{PlayerMemory, PlayerProfile}

  defstruct id: nil,
            name: nil,
            stack: 100,
            profile: %PlayerProfile{},
            memory: %PlayerMemory{}
end
