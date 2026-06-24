defmodule GameSimulator.Simulation.PlayerProfile do
  @enforce_keys [:archetype, :vpip, :pfr, :three_bet, :aggression]
  defstruct [:archetype, :vpip, :pfr, :three_bet, :aggression]
end

defmodule GameSimulator.Simulation.ProfileGenerator do
  alias GameSimulator.Simulation.PlayerProfile

  @archetypes [:nit, :tag, :lag, :fish_passif, :maniaque, :random]

  def generate_table(size) when is_integer(size) and size > 0 do
    Enum.map(1..size, fn _ -> generate_profile(weighted_archetype()) end)
  end

  def generate_profile(archetype) when archetype in @archetypes do
    {vpip_min, vpip_max, pfr_min, pfr_max, three_bet_min, three_bet_max, aggression_min, aggression_max} =
      ranges(archetype)

    vpip = random_int(vpip_min, vpip_max)
    pfr = random_int(pfr_min, min(pfr_max, vpip))

    %PlayerProfile{
      archetype: archetype,
      vpip: vpip,
      pfr: pfr,
      three_bet: random_int(three_bet_min, three_bet_max),
      aggression: random_float(aggression_min, aggression_max)
    }
  end

  def generate_profile(_archetype), do: {:error, :unknown_archetype}

  # Pondération cumulée de la population typique d'une table 6-max.
  def weighted_archetype do
    roll = :rand.uniform(100)

    cond do
      roll <= 30 -> :fish_passif
      roll <= 55 -> :tag
      roll <= 70 -> :nit
      roll <= 85 -> :lag
      roll <= 95 -> :maniaque
      true -> :random
    end
  end

  def ranges(:fish_passif), do: {35, 60, 2, 12, 0, 3, 0.05, 0.30}
  def ranges(:tag), do: {18, 28, 14, 23, 4, 8, 0.60, 1.30}
  def ranges(:nit), do: {10, 18, 7, 14, 2, 5, 0.40, 1.00}
  def ranges(:lag), do: {26, 38, 20, 32, 6, 12, 1.00, 2.00}
  def ranges(:maniaque), do: {45, 75, 25, 55, 8, 18, 1.50, 3.50}
  def ranges(:random), do: {5, 85, 0, 65, 0, 25, 0.00, 4.00}

  def random_int(min, max), do: min + :rand.uniform(max - min + 1) - 1

  def random_float(min, max) do
    # Arrondi léger pour garder des profils lisibles sans perdre l'aléatoire.
    Float.round(min + :rand.uniform() * (max - min), 2)
  end
end
