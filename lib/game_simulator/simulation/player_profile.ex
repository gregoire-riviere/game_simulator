defmodule GameSimulator.Simulation.PlayerProfile do
  @moduledoc """
  Fixed player tendencies used by simulations.

  Rates are simple numeric values between 0 and 1.
  """

  defstruct vpip: 0.25,
            pfr: 0.18,
            three_bet: 0.07,
            aggression: 0.5,
            bluff: 0.12,
            tilt_resistance: 0.7,
            call_too_wide: 0.0,
            overplays_top_pair: 0.0,
            chases_draws: 0.0,
            weird_sizing_frequency: 0.0,
            stupid_mistake_frequency: 0.0
end
