defmodule GameSimulator.Simulation.PlayerMemory do
  @moduledoc """
  Short-term player state for a simulation session.
  """

  defstruct current_tilt: 0.0,
            hands_since_big_loss: 0,
            lost_buyins: 0,
            won_big_pot_recently: false,
            bad_beats: 0
end
