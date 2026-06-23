defmodule PokerTest do
  use ExUnit.Case, async: true

  test "builds a standard deck with string denominations" do
    cards = Poker.deck()

    assert length(cards) == 52
    assert length(Enum.uniq(cards)) == 52
    assert {"A", "spades"} in cards
    assert {"10", "hearts"} in cards
  end

  test "compares the best five cards from seven" do
    straight_flush = [{"A", "spades"}, {"K", "spades"}, {"Q", "spades"}, {"J", "spades"}, {"10", "spades"}, {"2", "clubs"}, {"3", "diamonds"}]
    full_house = [{"A", "clubs"}, {"A", "diamonds"}, {"A", "hearts"}, {"K", "clubs"}, {"K", "diamonds"}, {"2", "clubs"}, {"3", "diamonds"}]

    assert Poker.best_hand(straight_flush) > Poker.best_hand(full_house)
    assert tuple_size(Poker.best_hand(straight_flush)) == 6
    assert tuple_size(Poker.best_hand(full_house)) == 6
  end

  test "describes a hand without exposing its internal score" do
    assert Poker.hand_description({3, 13, 8, 6, 0, 0}) == %{
             category: :three_of_a_kind,
             ranks: ["K", "K", "K", "8", "6"]
           }
  end

  test "splits side pots without giving folded players a win" do
    players = [
      %{id: :short, cards: [{"A", "spades"}, {"A", "hearts"}], contribution: 10, folded: false},
      %{id: :deep, cards: [{"K", "spades"}, {"K", "hearts"}], contribution: 20, folded: false},
      %{id: :folded, cards: [{"Q", "spades"}, {"Q", "hearts"}], contribution: 20, folded: true}
    ]

    board = [{"2", "clubs"}, {"3", "diamonds"}, {"7", "hearts"}, {"9", "clubs"}, {"J", "diamonds"}]

    assert Poker.settle(players, board, [:short, :deep, :folded]) == %{short: 30, deep: 20}
  end

  test "awards the full pot directly when every opponent folded" do
    players = [
      %{id: :winner, cards: [{"A", "spades"}, {"A", "hearts"}], contribution: 10, folded: false},
      %{id: :folded, cards: [{"K", "spades"}, {"K", "hearts"}], contribution: 10, folded: true}
    ]

    assert Poker.settle(players, [], [:winner, :folded]) == %{winner: 20}
  end

  test "gives an odd chip to the first winner in the supplied left-of-button order" do
    players = [
      %{id: :left_of_button, cards: [{"2", "clubs"}, {"3", "clubs"}], contribution: 1, folded: false},
      %{id: :other_winner, cards: [{"4", "clubs"}, {"5", "clubs"}], contribution: 1, folded: false},
      %{id: :folded, cards: [{"A", "spades"}, {"A", "hearts"}], contribution: 1, folded: true}
    ]

    board = [{"10", "spades"}, {"J", "hearts"}, {"Q", "clubs"}, {"K", "diamonds"}, {"A", "clubs"}]

    assert Poker.settle(players, board, [:left_of_button, :other_winner, :folded]) == %{left_of_button: 2, other_winner: 1}
  end
end
