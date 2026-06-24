defmodule GameSimulator.Simulation.ProfileGeneratorTest do
  use ExUnit.Case, async: true

  alias GameSimulator.Simulation.PlayerProfile
  alias GameSimulator.Simulation.ProfileGenerator

  test "generate_profile returns valid profile for each archetype" do
    for archetype <- [:nit, :tag, :lag, :fish_passif, :maniaque, :random] do
      assert %PlayerProfile{} = profile = ProfileGenerator.generate_profile(archetype)
      assert profile.archetype == archetype
      assert profile.vpip >= profile.pfr
      assert profile.vpip in 0..100
      assert profile.pfr in 0..100
      assert profile.three_bet in 0..100
      assert profile.aggression >= 0.0
    end
  end

  test "generate_table returns requested number of profiles" do
    profiles = ProfileGenerator.generate_table(6)

    assert length(profiles) == 6
    assert Enum.all?(profiles, &match?(%PlayerProfile{}, &1))
  end
end
