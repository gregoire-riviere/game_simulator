defmodule Poker.Decision do
  @moduledoc """
  Décisions probabilistes des PNJ.

  Le module reçoit un profil et un contexte sans cartes adverses. Il ne modifie pas
  la table : l'action retournée est ensuite validée par `Poker.Game`.
  """

  def decide(profile, context) do
    case context.phase do
      :preflop -> preflop(profile, context)
      _street -> postflop(profile, context)
    end
  end

  def preflop(profile, context) do
    # Préflop : aucune carte commune, la décision dépend surtout de la range et position.
    facing_open = context.current_bet > context.big_blind
    tilt = tilt_effect(profile)
    vpip = effective_rate(profile.vpip, context.position)
    pfr = effective_rate(profile.pfr, context.position)
    three_bet = effective_rate(profile.three_bet, context.position)

    cond do
      facing_open and in_top_percent?(context.cards, three_bet) and chance(0.7 + tilt) -> raise_action(profile, context)
      facing_open and in_top_percent?(context.cards, vpip) -> call_or_fold(profile, context, preflop_call_chance(profile))
      not facing_open and in_top_percent?(context.cards, pfr) -> bet(profile, context)
      not facing_open and in_top_percent?(context.cards, vpip) -> passive_action(context)
      chance(profile.stupid_mistake_frequency) -> passive_action(context)
      true -> fold_or_check(context)
    end
  end

  def postflop(profile, context) do
    category = hand_category(context.cards ++ context.board)
    draw = draw_category(context.cards, context.board)

    # On part d'un comportement neutre, puis le profil et le tilt le déforment.
    probabilities = base_postflop_probabilities(category, draw, context)
    probabilities = apply_profile_biases(probabilities, profile, category, draw, context)
    probabilities = apply_tilt(probabilities, profile)
    probabilities |> normalize_probabilities() |> weighted_random() |> postflop_action(profile, context)
  end

  def base_postflop_probabilities(category, draw, %{to_call: 0}) do
    case {category, draw} do
      {:nuts, _draw} -> %{bet: 0.80, check: 0.20}
      {:very_strong, _draw} -> %{bet: 0.75, check: 0.25}
      {:strong, _draw} -> %{bet: 0.60, check: 0.40}
      {:medium, _draw} -> %{bet: 0.30, check: 0.70}
      {:air, :none} -> %{bet: 0.10, check: 0.90}
      {:air, _draw} -> %{bet: 0.35, check: 0.65}
    end
  end

  def base_postflop_probabilities(category, draw, _context) do
    case {category, draw} do
      {:nuts, _draw} -> %{raise: 0.45, call: 0.50, fold: 0.05}
      {:very_strong, _draw} -> %{raise: 0.35, call: 0.60, fold: 0.05}
      {:strong, _draw} -> %{raise: 0.15, call: 0.70, fold: 0.15}
      {:medium, :none} -> %{raise: 0.0, call: 0.45, fold: 0.55}
      {:medium, _draw} -> %{raise: 0.10, call: 0.55, fold: 0.35}
      {:air, :none} -> %{raise: 0.05, call: 0.05, fold: 0.90}
      {:air, _draw} -> %{raise: 0.10, call: 0.55, fold: 0.35}
    end
  end

  def apply_profile_biases(probabilities, profile, category, draw, context) do
    probabilities = scale_probability(probabilities, :bet, 0.5 + profile.aggression)
    probabilities = scale_probability(probabilities, :raise, 0.5 + profile.aggression)
    probabilities = if category == :air, do: scale_probability(probabilities, :bet, 1 + profile.bluff), else: probabilities
    probabilities = if category == :air, do: scale_probability(probabilities, :raise, 1 + profile.bluff), else: probabilities
    probabilities = if profile.call_too_wide, do: scale_probability(probabilities, :call, 1.4) |> scale_probability(:fold, 0.7), else: probabilities
    probabilities = if profile.overplays_top_pair and category == :strong, do: scale_probability(probabilities, :raise, 1.5) |> scale_probability(:fold, 0.5), else: probabilities
    probabilities = if profile.chases_draws and draw != :none, do: scale_probability(probabilities, :call, 1.5) |> scale_probability(:fold, 0.6), else: probabilities
    probabilities = if context.facing_cbet and category in [:medium, :air], do: scale_probability(probabilities, :fold, 1 + profile.fold_to_cbet), else: probabilities

    # À la river il n'y a plus de carte à venir : la curiosité représente un call faible pour voir.
    if context.phase == :river and context.to_call > 0 do
      probabilities |> scale_probability(:call, 1 + profile.showdown_curiosity * 0.3) |> scale_probability(:fold, 1 - profile.showdown_curiosity * 0.25)
    else
      probabilities
    end
  end

  def apply_tilt(probabilities, profile) do
    tilt = tilt_effect(profile)

    probabilities
    |> scale_probability(:bet, 1 + tilt)
    |> scale_probability(:raise, 1 + tilt)
    |> scale_probability(:fold, max(0.3, 1 - tilt))
  end

  def scale_probability(probabilities, action, factor) do
    Map.update(probabilities, action, 0.0, &(&1 * factor))
  end

  def normalize_probabilities(probabilities) do
    total = probabilities |> Map.values() |> Enum.sum()
    Map.new(probabilities, fn {action, probability} -> {action, probability / total} end)
  end

  def weighted_random(probabilities) do
    target = :rand.uniform()

    probabilities
    |> Enum.sort_by(&elem(&1, 0))
    |> Enum.reduce_while(0.0, fn {action, probability}, total ->
      total = total + probability
      if target <= total, do: {:halt, action}, else: {:cont, total}
    end)
  end

  def postflop_action(:bet, profile, context), do: bet(profile, context)
  def postflop_action(:raise, profile, context), do: raise_action(profile, context)
  def postflop_action(:call, _profile, _context), do: :call
  def postflop_action(:fold, _profile, _context), do: :fold
  def postflop_action(:check, _profile, _context), do: :check

  def draw_category(hole_cards, board) do
    flush_draw = flush_draw?(hole_cards, board)
    straight_draw = straight_draw(hole_cards ++ board)

    cond do
      flush_draw and straight_draw != :none -> :combo_draw
      flush_draw -> :flush_draw
      true -> straight_draw
    end
  end

  def flush_draw?(hole_cards, board) do
    # Un tirage couleur exige quatre cartes de la même couleur, dont une carte privée.
    suits = hole_cards ++ board |> Enum.map(&elem(&1, 1))
    hole_suits = Enum.map(hole_cards, &elem(&1, 1))
    Enum.any?(hole_suits, fn suit -> Enum.count(suits, &(&1 == suit)) == 4 end)
  end

  def straight_draw(cards) do
    values = cards |> Enum.map(fn {rank, _suit} -> Poker.rank_value(rank) end) |> Enum.uniq()
    values = if 14 in values, do: [1 | values], else: values

    missing_ranks =
      5..14
      |> Enum.flat_map(fn high ->
        sequence = if high == 5, do: [1, 2, 3, 4, 5], else: Enum.to_list((high - 4)..high)
        missing = sequence -- values
        if length(missing) == 1 and length(sequence -- missing) == 4, do: missing, else: []
      end)
      |> Enum.uniq()

    cond do
      length(missing_ranks) >= 2 -> :open_ended
      length(missing_ranks) == 1 -> :gutshot
      true -> :none
    end
  end

  def effective_rate(rate, position) do
    round(rate * position_factor(position)) |> min(100)
  end

  def position_factor(:early), do: 0.55
  def position_factor(:hijack), do: 0.75
  def position_factor(:cutoff), do: 0.90
  def position_factor(:button), do: 1.25
  def position_factor(:small_blind), do: 0.80
  def position_factor(:big_blind), do: 1.10

  def in_top_percent?(hand, percent) do
    # Les 169 catégories de mains n'ont pas le même nombre de combinaisons : AA en a 6,
    # AK assorti 4 et AK dépareillé 12. Le pourcentage est donc compté sur les 1 326 combos.
    target = round(1_326 * min(max(percent, 0), 100) / 100)
    normalized = normalize_hand(hand)

    Enum.reduce_while(preflop_order(), 0, fn category, total ->
      combos = category_combos(category)

      cond do
        total >= target -> {:halt, false}
        category == normalized -> {:halt, true}
        true -> {:cont, total + combos}
      end
    end)
  end

  def normalize_hand([{first, first_suit}, {second, second_suit}]) do
    {high, low} = if Poker.rank_value(first) >= Poker.rank_value(second), do: {first, second}, else: {second, first}
    high = rank_symbol(high)
    low = rank_symbol(low)

    cond do
      high == low -> high <> low
      first_suit == second_suit -> high <> low <> "s"
      true -> high <> low <> "o"
    end
  end

  def rank_symbol("10"), do: "T"
  def rank_symbol(rank), do: rank

  def preflop_order do
    ranks = ["A", "K", "Q", "J", "T", "9", "8", "7", "6", "5", "4", "3", "2"]

    pairs = Enum.map(ranks, &(&1 <> &1))

    non_pairs =
      for {high, high_index} <- Enum.with_index(ranks),
          {low, low_index} <- Enum.with_index(ranks),
          high_index < low_index,
          suffix <- ["s", "o"],
          do: high <> low <> suffix

    Enum.sort_by(pairs ++ non_pairs, &preflop_category_score/1, :desc)
  end

  def preflop_category_score(category) do
    [first, second] = String.graphemes(String.slice(category, 0, 2))
    high = symbol_value(first)
    low = symbol_value(second)
    pair = String.length(category) == 2
    suited = String.ends_with?(category, "s")
    gap = high - low

    if pair, do: 500 + high * 10, else: high * 20 + low * 3 + if(suited, do: 12, else: 0) + if(gap <= 2, do: 8, else: 0)
  end

  def symbol_value("T"), do: 10
  def symbol_value(rank), do: Poker.rank_value(rank)

  def category_combos(category) do
    if String.length(category) == 2, do: 6, else: if(String.ends_with?(category, "s"), do: 4, else: 12)
  end

  def hand_category(cards) do
    # Cette classe volontairement grossière suffit pour choisir des fréquences V1.
    case Poker.best_hand(cards) do
      {value, _, _, _, _, _} when value >= 6 -> :nuts
      {value, _, _, _, _, _} when value >= 3 -> :very_strong
      {2, _, _, _, _, _} -> :strong
      {1, pair, _, _, _, _} when pair >= 11 -> :strong
      {1, _, _, _, _, _} -> :medium
      _other -> :air
    end
  end

  def tilt_effect(profile) do
    profile.memory.current_tilt * (1 - profile.tilt_resistance)
  end

  def bet(profile, context) do
    case Enum.find(context.actions, &match?(%{bet: _}, &1)) do
      %{bet: limits} -> {:bet, sizing(limits, profile, context, :bet)}
      nil -> raise_action(profile, context)
    end
  end

  def raise_action(profile, context) do
    case Enum.find(context.actions, &match?(%{raise_to: _}, &1)) do
      %{raise_to: limits} -> {:raise_to, sizing(limits, profile, context, :raise)}
      nil -> call_or_fold(profile, context)
    end
  end

  def sizing(%{min: min, max: max}, profile, context, action_type) do
    fraction = pot_fraction(profile)
    amount = round(context.pot * fraction)
    amount = if action_type == :raise, do: context.current_bet + amount, else: amount

    # Le maximum légal correspond souvent au stack : il ne définit pas une mise normale.
    realistic_max = min(max, max(min, round(context.pot * 1.5)))
    amount |> max(min) |> min(realistic_max)
  end

  def pot_fraction(profile) do
    cond do
      chance(profile.weird_sizing_frequency * 0.25) -> Enum.random([1.25, 1.5])
      profile.archetype == :fish_passif -> Enum.random([0.25, 0.33, 0.5, 0.75])
      profile.archetype == :maniaque -> Enum.random([0.5, 0.75, 1.0, 1.25])
      true -> Enum.random([0.33, 0.5, 0.66])
    end
  end

  def preflop_call_chance(profile) do
    cond do
      profile.call_too_wide -> 0.75
      profile.archetype == :nit -> 0.35
      profile.archetype == :tag -> 0.50
      true -> 0.55
    end
  end

  def call_or_fold(profile, context), do: call_or_fold(profile, context, preflop_call_chance(profile))

  def call_or_fold(_profile, context, chance_to_call) do
    if :call in context.actions and chance(chance_to_call), do: :call, else: fold_or_check(context)
  end

  def passive_action(context), do: if(:call in context.actions, do: :call, else: fold_or_check(context))
  def fold_or_check(context), do: if(:check in context.actions, do: :check, else: :fold)
  def chance(probability), do: :rand.uniform() < min(max(probability, 0.0), 1.0)
end
