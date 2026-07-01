defmodule Poker.Profile do
  @moduledoc """
  Génération locale de profils PNJ réalistes pour les micro-limites.

  Un archétype donne une plage de valeurs ; chaque PNJ en tire une variante pour
  éviter que deux fishs ou deux TAGs jouent exactement de la même façon.
  """

  @archetypes [
    %{name: :calling_station, weight: 14, vpip: 50..70, pfr: 2..8, three_bet: 0..3, fold_to_cbet: 5..20, showdown_curiosity: 80..98, aggression: 5..25, bluff: 0..6, resistance: 10..50, call_too_wide: true, overplays_top_pair: true, chases_draws: true, weird: 8..18, mistakes: 2..7, description: "Paie trop souvent, surtout avec paire ou tirage."},
    %{name: :limp_caller, weight: 12, vpip: 42..62, pfr: 2..10, three_bet: 0..2, fold_to_cbet: 15..35, showdown_curiosity: 65..90, aggression: 5..22, bluff: 0..5, resistance: 10..45, call_too_wide: true, overplays_top_pair: true, chases_draws: true, weird: 10..22, mistakes: 3..8, description: "Limp/call beaucoup et relance peu."},
    %{name: :fit_or_fold, weight: 16, vpip: 22..38, pfr: 8..18, three_bet: 1..6, fold_to_cbet: 65..85, showdown_curiosity: 15..40, aggression: 15..40, bluff: 1..8, resistance: 25..70, call_too_wide: false, overplays_top_pair: false, chases_draws: false, weird: 3..8, mistakes: 1..4, description: "Abandonne souvent sans main faite."},
    %{name: :nit_weak, weight: 14, vpip: 10..18, pfr: 6..13, three_bet: 1..4, fold_to_cbet: 65..85, showdown_curiosity: 10..30, aggression: 15..35, bluff: 1..5, resistance: 45..85, call_too_wide: false, overplays_top_pair: false, chases_draws: false, weird: 1..5, mistakes: 1..3, description: "Attend de bonnes mains et lâche trop souvent."},
    %{name: :tag, weight: 24, vpip: 20..27, pfr: 16..23, three_bet: 5..9, fold_to_cbet: 45..65, showdown_curiosity: 20..45, aggression: 35..60, bluff: 7..14, resistance: 55..90, call_too_wide: false, overplays_top_pair: false, chases_draws: false, weird: 2..6, mistakes: 0..2, description: "Joueur serré et agressif."},
    %{name: :lag, weight: 14, vpip: 28..40, pfr: 21..32, three_bet: 7..13, fold_to_cbet: 35..55, showdown_curiosity: 25..55, aggression: 55..80, bluff: 12..22, resistance: 40..80, call_too_wide: false, overplays_top_pair: true, chases_draws: true, weird: 5..12, mistakes: 1..5, description: "Met régulièrement la pression."},
    %{name: :spewy_aggro, weight: 3, vpip: 42..65, pfr: 25..48, three_bet: 10..22, fold_to_cbet: 15..35, showdown_curiosity: 40..80, aggression: 70..95, bluff: 20..40, resistance: 10..55, call_too_wide: true, overplays_top_pair: true, chases_draws: true, weird: 15..30, mistakes: 5..12, description: "Relance trop et overplay ses mains."}
  ]

  @bot_names [
    "Aaron", "Adam", "Adel", "Adrien", "Agathe", "Aïcha", "Alain", "Alex", "Alice", "Aline",
    "Amel", "Anaïs", "Anissa", "Antoine", "Arthur", "Aya", "Baptiste", "Bilal", "Bruno", "Camille",
    "Carla", "Céline", "Chloé", "Clara", "Clément", "Damien", "David", "Diane", "Dylan", "Élodie",
    "Emma", "Enzo", "Eva", "Farah", "Florian", "Gabriel", "Gaël", "Hana", "Hugo", "Inès",
    "Iris", "Jade", "Jérémy", "Julie", "Karim", "Laura", "Léa", "Lila", "Lina", "Lise",
    "Loïc", "Lola", "Lucas", "Maël", "Manon", "Marc", "Mathis", "Mehdi", "Mélissa", "Mia",
    "Michel", "Mila", "Naël", "Nadia", "Nathan", "Nina", "Noah", "Noémie", "Nora", "Océane",
    "Olivier", "Paul", "Quentin", "Raphaël", "Rayan", "Rémi", "Romane", "Samir", "Sarah", "Sasha",
    "Sofia", "Sonia", "Sophie", "Tania", "Théo", "Thierry", "Tom", "Valentin", "Victor", "Yanis",
    "Yasmine", "Zoé"
  ]

  def generate(count) when is_integer(count) and count > 0 do
    names = random_names(count)
    Enum.map(1..count, fn index -> new(index, Enum.at(names, index - 1)) end)
  end

  def new(index), do: new(index, bot_name(index))

  def new(_index, name) do
    archetype = weighted_archetype(@archetypes)
    vpip = random(archetype.vpip)

    %{
      name: name,
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

  def random_names(count), do: @bot_names |> Enum.shuffle() |> Stream.cycle() |> Enum.take(count)

  def bot_name(index), do: Enum.at(@bot_names, rem(index - 1, length(@bot_names)))
end
