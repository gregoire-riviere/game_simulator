defmodule Poker.Profile do
  @archetypes [
    %{name: :fish_passif, weight: 30, vpip: 48..60, pfr: 3..12, three_bet: 0..3, fold_to_cbet: 20..40, aggression: 5..30, bluff: 0..8, resistance: 10..50, call_too_wide: true, overplays_top_pair: true, chases_draws: true, weird: 15..30, mistakes: 6..14, description: "Joue trop de mains et paie trop souvent."},
    %{name: :tag, weight: 25, vpip: 20..27, pfr: 16..23, three_bet: 5..9, fold_to_cbet: 45..65, aggression: 35..60, bluff: 7..14, resistance: 55..90, call_too_wide: false, overplays_top_pair: false, chases_draws: false, weird: 2..8, mistakes: 1..4, description: "Joueur serré et agressif."},
    %{name: :nit, weight: 15, vpip: 10..18, pfr: 8..15, three_bet: 2..5, fold_to_cbet: 60..80, aggression: 20..45, bluff: 2..7, resistance: 50..90, call_too_wide: false, overplays_top_pair: false, chases_draws: false, weird: 1..5, mistakes: 2..6, description: "Attend de très bonnes mains."},
    %{name: :lag, weight: 15, vpip: 28..40, pfr: 21..32, three_bet: 7..13, fold_to_cbet: 35..55, aggression: 55..80, bluff: 12..22, resistance: 40..80, call_too_wide: false, overplays_top_pair: true, chases_draws: true, weird: 5..15, mistakes: 3..8, description: "Met régulièrement la pression."},
    %{name: :maniaque, weight: 10, vpip: 45..70, pfr: 25..50, three_bet: 10..22, fold_to_cbet: 15..35, aggression: 70..95, bluff: 20..40, resistance: 10..55, call_too_wide: true, overplays_top_pair: true, chases_draws: true, weird: 20..45, mistakes: 8..18, description: "Relance beaucoup et varie ses mises."},
    %{name: :recreatif, weight: 5, vpip: 25..50, pfr: 8..25, three_bet: 1..8, fold_to_cbet: 30..60, aggression: 15..55, bluff: 3..15, resistance: 20..75, call_too_wide: true, overplays_top_pair: true, chases_draws: true, weird: 10..25, mistakes: 5..12, description: "Joueur imprévisible et imparfait."}
  ]

  def generate(count) when is_integer(count) and count > 0 do
    Enum.map(1..count, &new/1)
  end

  def new(index) do
    archetype = weighted_archetype(@archetypes)
    vpip = random(archetype.vpip)

    %{
      name: bot_name(index),
      archetype: archetype.name,
      vpip: vpip,
      pfr: min(random(archetype.pfr), vpip),
      three_bet: random(archetype.three_bet),
      fold_to_cbet: random(archetype.fold_to_cbet) / 100,
      aggression: random(archetype.aggression) / 100,
      bluff: random(archetype.bluff) / 100,
      tilt_resistance: random(archetype.resistance) / 100,
      call_too_wide: archetype.call_too_wide,
      overplays_top_pair: archetype.overplays_top_pair,
      chases_draws: archetype.chases_draws,
      weird_sizing_frequency: random(archetype.weird) / 100,
      stupid_mistake_frequency: random(archetype.mistakes) / 100,
      short_description: archetype.description,
      memory: %{current_tilt: 0.0, hands_since_big_loss: 0, lost_buyins: 0, won_big_pot_recently: false, bad_beats: 0}
    }
  end

  def weighted_archetype(archetypes) do
    target = :rand.uniform(Enum.sum(Enum.map(archetypes, & &1.weight)))
    Enum.reduce_while(archetypes, 0, fn archetype, total ->
      total = total + archetype.weight
      if target <= total, do: {:halt, archetype}, else: {:cont, total}
    end)
  end

  def random(first..last//_step), do: first + :rand.uniform(last - first + 1) - 1

  def bot_name(index), do: Enum.at(["Michel", "Nadia", "Karim", "Sophie", "Lucas", "Emma", "Thierry", "Lina"], rem(index - 1, 8))
end
