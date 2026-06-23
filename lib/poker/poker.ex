defmodule Poker do
  @ranks ["2", "3", "4", "5", "6", "7", "8", "9", "10", "J", "Q", "K", "A"] # Rangs standards, du plus faible au plus fort.
  @suits ["clubs", "diamonds", "hearts", "spades"] # Couleurs standards du paquet.

  def deck do
    for rank <- @ranks, suit <- @suits, do: {rank, suit}
  end

  def shuffled_deck do
    Enum.shuffle(deck())
  end

  def rank_value("A"), do: 14
  def rank_value("K"), do: 13
  def rank_value("Q"), do: 12
  def rank_value("J"), do: 11
  def rank_value(rank) when rank in @ranks, do: String.to_integer(rank)

  def best_hand(cards) when is_list(cards) and length(cards) >= 5 do
    cards
    |> combinations(5)
    |> Enum.map(&hand_value/1)
    |> Enum.max()
  end

  def hand_description({8, high, 0, 0, 0, 0}), do: %{category: :straight_flush, ranks: straight_ranks(high)}
  def hand_description({7, quad, kicker, 0, 0, 0}), do: %{category: :four_of_a_kind, ranks: [rank_name(quad), rank_name(quad), rank_name(quad), rank_name(quad), rank_name(kicker)]}
  def hand_description({6, trips, pair, 0, 0, 0}), do: %{category: :full_house, ranks: [rank_name(trips), rank_name(trips), rank_name(trips), rank_name(pair), rank_name(pair)]}
  def hand_description({5, first, second, third, fourth, fifth}), do: %{category: :flush, ranks: Enum.map([first, second, third, fourth, fifth], &rank_name/1)}
  def hand_description({4, high, 0, 0, 0, 0}), do: %{category: :straight, ranks: straight_ranks(high)}
  def hand_description({3, trips, first, second, 0, 0}), do: %{category: :three_of_a_kind, ranks: [rank_name(trips), rank_name(trips), rank_name(trips), rank_name(first), rank_name(second)]}
  def hand_description({2, high_pair, low_pair, kicker, 0, 0}), do: %{category: :two_pair, ranks: [rank_name(high_pair), rank_name(high_pair), rank_name(low_pair), rank_name(low_pair), rank_name(kicker)]}
  def hand_description({1, pair, first, second, third, 0}), do: %{category: :pair, ranks: [rank_name(pair), rank_name(pair), rank_name(first), rank_name(second), rank_name(third)]}
  def hand_description({0, first, second, third, fourth, fifth}), do: %{category: :high_card, ranks: Enum.map([first, second, third, fourth, fifth], &rank_name/1)}

  def straight_ranks(5), do: ["5", "4", "3", "2", "A"]
  def straight_ranks(high), do: Enum.map(high..(high - 4), &rank_name/1)

  def rank_name(14), do: "A"
  def rank_name(13), do: "K"
  def rank_name(12), do: "Q"
  def rank_name(11), do: "J"
  def rank_name(rank), do: Integer.to_string(rank)

  # Chaque score a six éléments afin que la comparaison lexicographique soit stable.
  def hand_value(cards) do
    ranks = cards |> Enum.map(fn {rank, _suit} -> rank_value(rank) end) |> Enum.sort(:desc)
    suits = Enum.map(cards, fn {_rank, suit} -> suit end)
    counts = ranks |> Enum.frequencies() |> Enum.sort_by(fn {rank, count} -> {count, rank} end, :desc)
    straight_high = straight_high(ranks)

    cond do
      length(Enum.uniq(suits)) == 1 and straight_high -> {8, straight_high, 0, 0, 0, 0}
      match?([{_, 4}, {_, 1}], counts) ->
        [{quad, 4}, {kicker, 1}] = counts
        {7, quad, kicker, 0, 0, 0}

      match?([{_, 3}, {_, 2}], counts) ->
        [{trips, 3}, {pair, 2}] = counts
        {6, trips, pair, 0, 0, 0}

      length(Enum.uniq(suits)) == 1 -> List.to_tuple([5 | ranks])
      straight_high -> {4, straight_high, 0, 0, 0, 0}
      match?([{_, 3}, {_, 1}, {_, 1}], counts) ->
        [{trips, 3} | kickers] = counts
        [first, second] = Enum.map(kickers, &elem(&1, 0))
        {3, trips, first, second, 0, 0}

      match?([{_, 2}, {_, 2}, {_, 1}], counts) ->
        [{high_pair, 2}, {low_pair, 2}, {kicker, 1}] = counts
        {2, high_pair, low_pair, kicker, 0, 0}

      match?([{_, 2}, {_, 1}, {_, 1}, {_, 1}], counts) ->
        [{pair, 2} | kickers] = counts
        [first, second, third] = Enum.map(kickers, &elem(&1, 0))
        {1, pair, first, second, third, 0}

      true -> List.to_tuple([0 | ranks])
    end
  end

  def straight_high(ranks) do
    unique = Enum.uniq(ranks)
    values = if 14 in unique, do: [1 | unique], else: unique

    values
    |> Enum.sort()
    |> Enum.chunk_every(5, 1, :discard)
    |> Enum.filter(fn sequence -> Enum.max(sequence) - Enum.min(sequence) == 4 and length(Enum.uniq(sequence)) == 5 end)
    |> Enum.map(&Enum.max/1)
    |> Enum.max(fn -> nil end)
  end

  def combinations(_items, 0), do: [[]]
  def combinations([], _size), do: []

  def combinations([item | items], size) do
    with_item = Enum.map(combinations(items, size - 1), &[item | &1])
    without_item = combinations(items, size)
    with_item ++ without_item
  end

  def settle(players, board, odd_chip_order) do
    eligible = Enum.reject(players, & &1.folded)

    case eligible do
      [] -> %{}
      [winner] -> %{winner.id => Enum.sum(Enum.map(players, & &1.contribution))}
      _ ->
        # Chaque niveau de contribution forme un pot principal ou un side pot.
        levels = players |> Enum.map(& &1.contribution) |> Enum.filter(&(&1 > 0)) |> Enum.uniq() |> Enum.sort()
        settle_levels(levels, players, board, odd_chip_order, 0, %{})
    end
  end

  def settle_levels([], _players, _board, _order, _previous, payouts), do: payouts

  def settle_levels([level | levels], players, board, order, previous, payouts) do
    contributors = Enum.filter(players, &(&1.contribution >= level))
    eligible = Enum.reject(contributors, & &1.folded)
    amount = (level - previous) * length(contributors)
    winners = winning_ids(eligible, board)
    payouts = distribute(amount, winners, order, payouts)
    settle_levels(levels, players, board, order, level, payouts)
  end

  def winning_ids(players, board) do
    # Une seule main éligible gagne ce pot sans nécessiter de showdown.
    if length(players) == 1 do
      [player] = players
      [player.id]
    else
      winning_ids_at_showdown(players, board)
    end
  end

  def winning_ids_at_showdown(players, board) do
    values = Enum.map(players, fn player -> {player.id, best_hand(player.cards ++ board)} end)
    best = values |> Enum.map(&elem(&1, 1)) |> Enum.max()
    for {id, value} <- values, value == best, do: id
  end

  # Split first, then give odd chips from the first seat left of the button.
  def distribute(amount, winners, order, payouts) do
    share = div(amount, length(winners))
    remainder = rem(amount, length(winners))
    payouts = Enum.reduce(winners, payouts, fn id, result -> Map.update(result, id, share, &(&1 + share)) end)
    ordered_winners = Enum.filter(order, &(&1 in winners))

    ordered_winners
    |> Enum.take(remainder)
    |> Enum.reduce(payouts, fn id, result -> Map.update!(result, id, &(&1 + 1)) end)
  end
end
