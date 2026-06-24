defmodule Poker.Decision do
  def decide(profile, context) do
    case context.phase do
      :preflop -> preflop(profile, context)
      _street -> postflop(profile, context)
    end
  end

  def preflop(profile, context) do
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
    aggressive = profile.aggression + tilt_effect(profile)

    cond do
      context.to_call == 0 and category in [:nuts, :very_strong] and chance(aggressive) -> bet(profile, context)
      context.to_call == 0 and category == :strong and chance(aggressive * 0.7) -> bet(profile, context)
      context.to_call == 0 and category == :air and chance(profile.bluff + tilt_effect(profile)) -> bet(profile, context)
      context.to_call > 0 and category in [:nuts, :very_strong] and chance(aggressive * 0.6) -> raise_action(profile, context)
      context.to_call > 0 and category in [:nuts, :very_strong, :strong] -> call_or_fold(profile, context, 0.85)
      context.to_call > 0 and category == :medium and context.facing_cbet and chance(profile.fold_to_cbet) -> fold_or_check(context)
      context.to_call > 0 and category == :medium -> call_or_fold(profile, context, call_chance(profile, context))
      context.to_call > 0 and profile.call_too_wide and chance(0.22 + tilt_effect(profile)) -> call_or_fold(profile, context, 0.75)
      true -> fold_or_check(context)
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
    case Poker.best_hand(cards) do
      {value, _, _, _, _, _} when value >= 6 -> :nuts
      {value, _, _, _, _, _} when value >= 3 -> :very_strong
      {2, _, _, _, _, _} -> :strong
      {1, pair, _, _, _, _} when pair >= 11 -> :strong
      {1, _, _, _, _, _} -> :medium
      _other -> :air
    end
  end

  def call_chance(profile, context) do
    # Les pot odds réduisent les calls faibles face à une grosse mise.
    pot_odds = context.to_call / max(context.pot + context.to_call, 1)
    max(0.1, 0.65 - pot_odds + if(profile.chases_draws, do: 0.12, else: 0))
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
