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
    # Préflop : on sépare les grandes situations avant d'appliquer les ranges.
    situation = preflop_situation(context)
    tilt = tilt_effect(profile)
    vpip = effective_rate(profile.vpip, context.position)
    pfr = effective_rate(profile.pfr, context.position)
    three_bet = effective_rate(profile.three_bet, context.position)
    call_range = preflop_call_range(profile, vpip)

    cond do
      situation == :facing_all_in and in_top_percent?(context.cards, max(4, three_bet)) -> call_or_fold(profile, context, 0.55)
      situation == :facing_all_in -> fold_or_check(context)
      situation == :facing_raise and premium_vs_large_preflop_raise?(profile, context) -> continue_premium_preflop(profile, context)
      situation == :facing_raise and in_top_percent?(context.cards, three_bet) and chance(three_bet_chance(profile) + tilt) -> raise_action(profile, context)
      situation == :facing_raise and in_top_percent?(context.cards, call_range) -> call_or_fold(profile, context, preflop_call_chance(profile, context))
      situation == :facing_limp and in_top_percent?(context.cards, pfr) and chance(0.75 + tilt) -> raise_action(profile, context)
      situation == :facing_limp and in_top_percent?(context.cards, call_range) -> call_or_fold(profile, context, preflop_limp_call_chance(profile))
      situation == :no_raise_yet and in_top_percent?(context.cards, pfr) -> raise_action(profile, context)
      situation == :no_raise_yet and in_top_percent?(context.cards, vpip) -> passive_action(context)
      chance(profile.stupid_mistake_frequency) -> passive_action(context)
      true -> fold_or_check(context)
    end
  end

  def preflop_situation(context) do
    cond do
      context.to_call >= context.stack and context.to_call > 0 -> :facing_all_in
      context.current_bet > context.big_blind -> :facing_raise
      context.to_call > 0 -> :facing_limp
      true -> :no_raise_yet
    end
  end

  def premium_vs_large_preflop_raise?(profile, context) do
    premium_preflop_hand?(context.cards) and premium_preflop_pressure?(context) and not ultra_deep_nit?(profile, context)
  end

  def premium_preflop_pressure?(context) do
    Map.get(context, :preflop_raise_count, 0) >= 3 or context.current_bet > context.big_blind * 25
  end

  def premium_preflop_hand?(cards) do
    normalize_hand(cards) in ["AA", "KK", "QQ", "AKs", "AKo"]
  end

  def ultra_deep_nit?(%{archetype: :nit_weak}, context) do
    Map.get(context, :effective_stack, context.stack) > context.big_blind * 250
  end

  def ultra_deep_nit?(_profile, _context), do: false

  def continue_premium_preflop(profile, context) do
    cond do
      Enum.any?(context.actions, &match?(%{raise_to: _}, &1)) and chance(three_bet_chance(profile)) -> raise_action(profile, context)
      :call in context.actions -> :call
      :all_in in context.actions -> :all_in
      true -> fold_or_check(context)
    end
  end

  def three_bet_chance(profile) do
    case profile.archetype do
      :tag -> 0.90
      :lag -> 0.95
      :spewy_aggro -> 1.0
      _other -> 0.70
    end
  end

  def preflop_call_range(profile, vpip) do
    multiplier =
      case profile.archetype do
        :calling_station -> 1.45
        :limp_caller -> 1.30
        _other -> 1.0
      end

    min(100, round(vpip * multiplier))
  end

  def preflop_limp_call_chance(profile) do
    case profile.archetype do
      :calling_station -> 0.90
      :limp_caller -> 0.85
      _other -> 0.65
    end
  end

  def postflop(profile, context) do
    category = context.cards |> made_hand_category(context.board) |> hand_strength_category()
    draw = draw_category(context.cards, context.board)

    # On part d'un comportement neutre, puis le profil et le tilt le déforment.
    probabilities = base_postflop_probabilities(category, draw, context)
    probabilities = apply_profile_biases(probabilities, profile, category, draw, context)
    probabilities = apply_price_pressure(probabilities, profile, context)
    probabilities = apply_tilt(probabilities, profile)
    probabilities = apply_late_street_value_pressure(probabilities, category, context)
    probabilities = apply_late_street_price_guard(probabilities, category, context)
    probabilities = apply_showdown_discipline(probabilities, profile, category, context)
    probabilities = apply_river_sanity_guard(probabilities, profile, category, draw, context)
    probabilities |> normalize_probabilities() |> weighted_random() |> postflop_action(profile, context)
  end

  def base_postflop_probabilities(category, draw, %{to_call: 0}) do
    case {category, draw} do
      {:nuts, _draw} -> %{bet: 0.80, check: 0.20}
      {:very_strong, _draw} -> %{bet: 0.75, check: 0.25}
      {:strong, _draw} -> %{bet: 0.60, check: 0.40}
      {:medium, _draw} -> %{bet: 0.30, check: 0.70}
      {:ace_high, _draw} -> %{bet: 0.05, check: 0.95}
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
      {:ace_high, _draw} -> %{raise: 0.0, call: 0.20, fold: 0.80}
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
    probabilities = apply_sticky_cbet_bias(probabilities, profile, context)

    # À la river il n'y a plus de carte à venir : la curiosité représente un call faible pour voir.
    if context.phase == :river and context.to_call > 0 do
      probabilities |> scale_probability(:call, 1 + profile.showdown_curiosity * 0.3) |> scale_probability(:fold, 1 - profile.showdown_curiosity * 0.25)
    else
      probabilities
    end
  end

  def apply_sticky_cbet_bias(probabilities, %{archetype: :calling_station}, %{facing_cbet: true}) do
    probabilities |> scale_probability(:call, 1.9) |> scale_probability(:fold, 0.45)
  end

  def apply_sticky_cbet_bias(probabilities, %{archetype: :limp_caller}, %{facing_cbet: true}) do
    probabilities |> scale_probability(:call, 1.55) |> scale_probability(:fold, 0.65)
  end

  def apply_sticky_cbet_bias(probabilities, %{archetype: archetype}, %{facing_cbet: true}) when archetype in [:tag, :lag] do
    probabilities |> scale_probability(:call, 1.35) |> scale_probability(:fold, 0.70)
  end

  def apply_sticky_cbet_bias(probabilities, _profile, _context), do: probabilities

  def apply_price_pressure(probabilities, _profile, %{to_call: 0}), do: probabilities

  def apply_price_pressure(probabilities, profile, context) do
    pressure = price_pressure(context)

    call_bonus =
      cond do
        profile.archetype == :calling_station -> 0.55
        profile.archetype == :limp_caller -> 0.35
        profile.call_too_wide -> 0.25
        true -> 0.0
      end

    fold_multiplier =
      cond do
        profile.archetype == :calling_station -> 0.35 + pressure * 0.25
        profile.archetype == :limp_caller -> 0.55 + pressure * 0.35
        true -> 0.85 + pressure * 0.65
      end

    probabilities
    |> scale_probability(:call, max(0.25, 1.15 - pressure * 0.45 + call_bonus))
    |> scale_probability(:raise, max(0.20, 1.05 - pressure * 0.45 + profile.aggression * 0.2))
    |> scale_probability(:fold, fold_multiplier)
  end

  def price_pressure(context) do
    # Combine pot odds, taille relative au pot et pression sur le stack sans modèle d'équité lourd.
    context.pot_odds * 1.2 + min(context.bet_size_ratio, 2.0) * 0.45 + min(context.stack_pressure, 1.0) * 0.9
  end

  def apply_tilt(probabilities, profile) do
    tilt = tilt_effect(profile)

    probabilities
    |> scale_probability(:bet, 1 + tilt)
    |> scale_probability(:raise, 1 + tilt)
    |> scale_probability(:fold, max(0.3, 1 - tilt))
  end

  def apply_late_street_value_pressure(probabilities, category, %{phase: phase, to_call: 0}) when phase in [:turn, :river] and category in [:nuts, :very_strong, :strong] do
    probabilities
    |> scale_probability(:bet, 1.7)
    |> scale_probability(:check, 0.35)
  end

  def apply_late_street_value_pressure(probabilities, category, %{phase: phase, to_call: 0}) when phase in [:turn, :river] and category in [:medium, :ace_high, :air] do
    probabilities
    |> scale_probability(:bet, 0.45)
    |> scale_probability(:check, 1.35)
  end

  def apply_late_street_value_pressure(probabilities, _category, _context), do: probabilities

  def apply_late_street_price_guard(probabilities, category, %{phase: phase, to_call: to_call, bet_size_ratio: ratio}) when phase in [:turn, :river] and to_call > 0 and ratio >= 0.66 and category in [:medium, :ace_high, :air] do
    # Les gros sizings turn/river polarisent davantage : les mains faibles doivent beaucoup moins payer.
    call_factor = if category == :medium, do: 0.45, else: 0.20

    probabilities
    |> scale_probability(:raise, 0.10)
    |> scale_probability(:call, call_factor)
    |> scale_probability(:fold, 2.4)
  end

  def apply_late_street_price_guard(probabilities, _category, _context), do: probabilities

  def apply_showdown_discipline(probabilities, profile, category, %{phase: phase, to_call: to_call}) when phase in [:turn, :river] and to_call > 0 and category in [:medium, :ace_high, :air] do
    call_factor =
      case profile.archetype do
        :calling_station -> 0.55
        :limp_caller -> 0.45
        :spewy_aggro -> 0.60
        :lag -> 0.32
        :tag -> 0.16
        :nit_weak -> 0.12
        :fit_or_fold -> 0.12
      end

    fold_factor =
      case profile.archetype do
        :calling_station -> 1.75
        :limp_caller -> 2.00
        :spewy_aggro -> 1.45
        :lag -> 2.30
        :tag -> 3.60
        :nit_weak -> 4.20
        :fit_or_fold -> 4.20
      end

    probabilities
    |> scale_probability(:raise, 0.15)
    |> scale_probability(:call, call_factor)
    |> scale_probability(:fold, fold_factor)
  end

  def apply_showdown_discipline(probabilities, _profile, _category, _context), do: probabilities

  def apply_river_sanity_guard(probabilities, profile, category, _draw, %{phase: :river, to_call: 0}) when category in [:air, :ace_high] do
    bet_factor =
      case profile.archetype do
        :spewy_aggro -> 0.55
        :lag -> 0.25
        _other -> 0.01
      end

    probabilities
    |> scale_probability(:bet, bet_factor)
    |> scale_probability(:check, 2.0)
  end

  def apply_river_sanity_guard(probabilities, _profile, :air, _draw, %{phase: :river, to_call: to_call} = context) when to_call > 0 do
    call_factor = if context.bet_size_ratio > 0.7, do: 0.2, else: 0.5

    probabilities
    |> scale_probability(:raise, 0.05)
    |> scale_probability(:call, call_factor)
    |> scale_probability(:fold, 2.0)
  end

  def apply_river_sanity_guard(probabilities, _profile, :medium, _draw, %{phase: :river, to_call: to_call, bet_size_ratio: ratio}) when to_call > 0 and ratio > 0.75 do
    probabilities
    |> scale_probability(:raise, 0.1)
    |> scale_probability(:call, 0.55)
    |> scale_probability(:fold, 1.7)
  end

  def apply_river_sanity_guard(probabilities, _profile, _category, _draw, _context), do: probabilities

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

  def position_factor(:early), do: 0.70
  def position_factor(:hijack), do: 0.85
  def position_factor(:cutoff), do: 1.00
  def position_factor(:button), do: 1.25
  def position_factor(:small_blind), do: 0.85
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

  def made_hand_category(hole_cards, board) do
    value = Poker.best_hand(hole_cards ++ board)
    board_value = if length(board) >= 5, do: Poker.best_hand(board), else: nil
    hole_ranks = Enum.map(hole_cards, fn {rank, _suit} -> Poker.rank_value(rank) end)
    board_ranks = Enum.map(board, fn {rank, _suit} -> Poker.rank_value(rank) end)

    if board_value == value do
      :plays_board
    else
      made_hand_from_value(value, hole_ranks, board_ranks)
    end
  end

  def made_hand_from_value(value, hole_ranks, board_ranks) do
    case value do
      {8, _, _, _, _, _} -> :nuts
      {7, quad, _, _, _, _} -> if(quad in hole_ranks, do: :nuts, else: :board_quads)
      {6, trips, pair, _, _, _} -> if(trips in hole_ranks or pair in hole_ranks, do: :full_house, else: :plays_board)
      {5, _, _, _, _, _} -> :flush
      {4, _, _, _, _, _} -> :straight
      {3, trips, _, _, _, _} -> if(trips in hole_ranks, do: :set_or_trips, else: :board_trips)
      {2, high_pair, low_pair, _, _, _} -> two_pair_category(high_pair, low_pair, hole_ranks)
      {1, pair, kicker, _, _, _} -> pair_category(pair, kicker, hole_ranks, board_ranks)
      _other -> unpaired_category(hole_ranks, board_ranks)
    end
  end

  def two_pair_category(high_pair, low_pair, hole_ranks) do
    if high_pair in hole_ranks or low_pair in hole_ranks, do: :two_pair, else: :board_two_pair
  end

  def pair_category(pair, kicker, hole_ranks, board_ranks) do
    board_high = Enum.max(board_ranks)

    cond do
      pair not in hole_ranks -> :board_pair
      Enum.all?(board_ranks, &(pair > &1)) -> :overpair
      pair not in board_ranks and pair < board_high -> :underpair
      pair == board_high and kicker >= 11 -> :top_pair_good_kicker
      pair == board_high -> :top_pair_bad_kicker
      pair > Enum.min(board_ranks) -> :middle_pair
      true -> :bottom_pair
    end
  end

  def unpaired_category(hole_ranks, board_ranks) do
    board_high = Enum.max(board_ranks)

    cond do
      Enum.count(hole_ranks, &(&1 > board_high)) == 2 -> :two_overcards
      14 in hole_ranks -> :ace_high
      true -> :air
    end
  end

  def hand_strength_category(category) do
    case category do
      :nuts -> :nuts
      category when category in [:full_house, :flush, :straight, :set_or_trips] -> :very_strong
      category when category in [:board_quads, :two_pair, :overpair, :top_pair_good_kicker] -> :strong
      category when category in [:top_pair_bad_kicker, :middle_pair, :bottom_pair, :board_trips, :board_two_pair] -> :medium
      :ace_high -> :ace_high
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
    amount =
      if Map.get(context, :phase) == :preflop do
        preflop_sizing(profile, context, action_type)
      else
        fraction = pot_fraction(profile)
        amount = round(context.pot * fraction)
        if action_type == :raise, do: context.current_bet + amount, else: amount
      end

    # Le maximum légal correspond souvent au stack : il ne définit pas une mise normale.
    realistic_max = min(max, max(min, round(context.pot * 1.5)))
    amount |> max(min) |> min(realistic_max)
  end

  def preflop_sizing(profile, context, :raise) do
    cond do
      context.current_bet <= context.big_blind and profile.archetype in [:calling_station, :limp_caller] and chance(profile.weird_sizing_frequency) ->
        Enum.random([context.big_blind * 2, context.big_blind * 4])

      context.current_bet <= context.big_blind and profile.archetype == :spewy_aggro ->
        Enum.random([context.big_blind * 3, context.big_blind * 4, context.big_blind * 5])

      context.current_bet <= context.big_blind ->
        Enum.random([round(context.big_blind * 2.5), context.big_blind * 3])

      context.position in [:button, :cutoff] ->
        round(context.current_bet * 3)

      true ->
        round(context.current_bet * 3.5)
    end
  end

  def preflop_sizing(_profile, context, _action_type), do: round(context.big_blind * 3)

  def pot_fraction(profile) do
    cond do
      chance(profile.weird_sizing_frequency * 0.25) -> Enum.random([1.0, 1.25])
      profile.archetype in [:calling_station, :limp_caller] -> Enum.random([0.25, 0.33, 0.5, 0.75])
      profile.archetype == :spewy_aggro -> Enum.random([0.5, 0.66, 0.75, 1.0])
      true -> Enum.random([0.33, 0.5, 0.66])
    end
  end

  def preflop_call_chance(profile), do: preflop_call_chance(profile, %{pot_odds: 0.0, bet_size_ratio: 0.0, stack_pressure: 0.0})

  def preflop_call_chance(profile, context) do
    base =
      cond do
        profile.call_too_wide -> 0.75
        profile.archetype == :nit_weak -> 0.35
        profile.archetype == :tag -> 0.50
        true -> 0.55
      end

    max(0.05, base - price_pressure(context) * 0.25)
  end

  def call_or_fold(profile, context), do: call_or_fold(profile, context, preflop_call_chance(profile))

  def call_or_fold(_profile, context, chance_to_call) do
    if :call in context.actions and chance(chance_to_call), do: :call, else: fold_or_check(context)
  end

  def passive_action(context), do: if(:call in context.actions, do: :call, else: fold_or_check(context))
  def fold_or_check(context), do: if(:check in context.actions, do: :check, else: :fold)
  def chance(probability), do: :rand.uniform() < min(max(probability, 0.0), 1.0)
end
