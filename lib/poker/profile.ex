defmodule Poker.Profile do
  @moduledoc """
  Génération locale de profils PNJ réalistes pour les micro-limites.

  Un archétype donne une plage de valeurs ; chaque PNJ en tire une variante pour
  éviter que deux fishs ou deux TAGs jouent exactement de la même façon.
  """

  @archetypes [
    %{name: :calling_station, weight: 20, vpip: 48..65, pfr: 2..10, three_bet: 0..3, fold_to_cbet: 15..35, showdown_curiosity: 70..95, aggression: 5..25, bluff: 0..6, resistance: 10..50, call_too_wide: true, overplays_top_pair: true, chases_draws: true, weird: 10..25, mistakes: 6..14, description: "Paie trop souvent, surtout avec paire ou tirage."},
    %{name: :limp_caller, weight: 15, vpip: 38..58, pfr: 1..8, three_bet: 0..2, fold_to_cbet: 25..50, showdown_curiosity: 55..85, aggression: 5..22, bluff: 0..5, resistance: 10..45, call_too_wide: true, overplays_top_pair: true, chases_draws: true, weird: 12..30, mistakes: 7..15, description: "Limp/call beaucoup et relance peu."},
    %{name: :fit_or_fold, weight: 12, vpip: 22..38, pfr: 8..18, three_bet: 1..6, fold_to_cbet: 65..85, showdown_curiosity: 15..40, aggression: 15..40, bluff: 1..8, resistance: 25..70, call_too_wide: false, overplays_top_pair: false, chases_draws: false, weird: 3..10, mistakes: 3..8, description: "Abandonne souvent sans main faite."},
    %{name: :nit_weak, weight: 12, vpip: 10..18, pfr: 6..13, three_bet: 1..4, fold_to_cbet: 65..85, showdown_curiosity: 10..30, aggression: 15..35, bluff: 1..5, resistance: 45..85, call_too_wide: false, overplays_top_pair: false, chases_draws: false, weird: 1..5, mistakes: 2..6, description: "Attend de bonnes mains et lâche trop souvent."},
    %{name: :tag, weight: 18, vpip: 20..27, pfr: 16..23, three_bet: 5..9, fold_to_cbet: 45..65, showdown_curiosity: 20..45, aggression: 35..60, bluff: 7..14, resistance: 55..90, call_too_wide: false, overplays_top_pair: false, chases_draws: false, weird: 2..8, mistakes: 1..4, description: "Joueur serré et agressif."},
    %{name: :lag, weight: 15, vpip: 28..40, pfr: 21..32, three_bet: 7..13, fold_to_cbet: 35..55, showdown_curiosity: 25..55, aggression: 55..80, bluff: 12..22, resistance: 40..80, call_too_wide: false, overplays_top_pair: true, chases_draws: true, weird: 5..15, mistakes: 3..8, description: "Met régulièrement la pression."},
    %{name: :spewy_aggro, weight: 8, vpip: 42..65, pfr: 25..48, three_bet: 10..22, fold_to_cbet: 15..35, showdown_curiosity: 40..80, aggression: 70..95, bluff: 20..40, resistance: 10..55, call_too_wide: true, overplays_top_pair: true, chases_draws: true, weird: 20..45, mistakes: 8..18, description: "Relance trop et overplay ses mains."}
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
      # Certains joueurs paient la river faible uniquement pour connaître la main adverse.
      showdown_curiosity: random(archetype.showdown_curiosity) / 100,
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
    # Les poids reproduisent une table NL2 avec plus de récréatifs que de bons réguliers.
    target = :rand.uniform(Enum.sum(Enum.map(archetypes, & &1.weight)))
    Enum.reduce_while(archetypes, 0, fn archetype, total ->
      total = total + archetype.weight
      if target <= total, do: {:halt, archetype}, else: {:cont, total}
    end)
  end

  def random(first..last//_step), do: first + :rand.uniform(last - first + 1) - 1

  def bot_name(index), do: Enum.at(["Michel", "Nadia", "Karim", "Sophie", "Lucas", "Emma", "Thierry", "Lina"], rem(index - 1, 8))
end
