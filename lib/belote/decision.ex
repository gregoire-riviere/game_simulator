defmodule Belote.Decision do
  @moduledoc """
  Décideur local des PNJ. Les règles restent dans `Belote.Game` ; ce module ne
  fait que classer les choix déjà légaux.
  """

  alias Belote.Game

  def decide(state, seat) do
    actions = Game.legal_actions(state, seat)

    case state.phase do
      phase when phase in [:classic_first, :classic_second] -> take_or_pass(state, seat, actions)
      :coinche_bidding -> coinche_action(state, seat, actions)
      :playing -> best_card_action(state, seat, actions)
      _other -> hd(actions)
    end
  end

  def take_or_pass(state, seat, actions) do
    choices = Enum.filter(actions, fn action -> match?({:take, _suit}, action) end)

    case Enum.max_by(choices, fn {:take, suit} -> hand_strength(state.hands[seat], suit) end, fn -> nil end) do
      {:take, suit} = action -> if(hand_strength(state.hands[seat], suit) >= 47, do: action, else: :pass)
      _other -> :pass
    end
  end

  def coinche_action(state, seat, actions) do
    cond do
      :coinche in actions and hand_strength(state.hands[seat], state.bid.suit) >= state.bid.amount - 10 -> :coinche
      :surcoinche in actions and hand_strength(state.hands[seat], state.bid.suit) >= state.bid.amount + 5 -> :surcoinche
      true -> best_bid_or_pass(state, seat, actions)
    end
  end

  def best_bid_or_pass(state, seat, actions) do
    bids = Enum.filter(actions, fn action -> match?({:bid, _amount, _suit}, action) end)
    hand = state.hands[seat]

    case Enum.max_by(Game.suits(), &hand_strength(hand, &1)) do
      suit ->
        strength = hand_strength(hand, suit)
        amount = bid_amount(strength)

        case Enum.max_by(Enum.filter(bids, fn {:bid, bid_amount, bid_suit} -> bid_suit == suit and bid_amount <= amount end), fn {:bid, bid_amount, _suit} -> bid_amount end, fn -> nil end) do
          nil -> :pass
          action -> action
        end
    end
  end

  def best_card_action(state, seat, actions) do
    cards = Enum.map(actions, fn {:play, card} -> card end)

    card =
      cond do
        state.trick == [] -> lead_card(state, seat, cards)
        partner_winning?(state, seat) -> Enum.min_by(cards, &discard_cost(state, &1))
        true -> win_or_discard(state, seat, cards)
      end

    {:play, card}
  end

  def bid_amount(strength) when strength >= 75, do: 110
  def bid_amount(strength) when strength >= 65, do: 100
  def bid_amount(strength) when strength >= 55, do: 90
  def bid_amount(strength) when strength >= 45, do: 80
  def bid_amount(_strength), do: 0

  def lead_card(state, seat, cards) do
    trumps = Enum.filter(cards, fn {suit, _rank} -> suit == state.trump end)
    aces = Enum.filter(cards, fn {suit, rank} -> suit != state.trump and rank == :ace end)

    cond do
      Game.team(seat) == state.contract.team and length(trumps) >= 3 and Enum.any?(trumps, fn {_suit, rank} -> rank in [:jack, :nine] end) ->
        Enum.max_by(trumps, &trump_priority/1)

      aces != [] -> hd(aces)
      true ->
        pool = Enum.reject(cards, fn {suit, _rank} -> suit == state.trump end)
        pool = if pool == [], do: cards, else: pool
        Enum.max_by(pool, fn {suit, _rank} = card -> {length(Enum.filter(pool, fn {other_suit, _other_rank} -> other_suit == suit end)), -discard_cost(state, card)} end)
    end
  end

  def win_or_discard(state, seat, cards) do
    winners = Enum.filter(cards, &wins_trick?(state, seat, &1))

    if winners == [] do
      Enum.min_by(cards, &discard_cost(state, &1))
    else
      Enum.min_by(winners, &winning_cost(state, &1))
    end
  end

  def partner_winning?(state, seat), do: Game.team(Game.trick_winner(state.trick, state.trump)) == Game.team(seat)
  def wins_trick?(state, seat, card), do: Game.trick_winner(state.trick ++ [%{seat: seat, card: card}], state.trump) == seat

  # Un pli déjà assuré par le partenaire ne mérite ni un atout ni une carte comptante.
  def discard_cost(state, {suit, rank} = card), do: Game.card_points(card, state.trump) * 20 + if(suit == state.trump, do: 100, else: 0) + Game.card_strength(rank, suit == state.trump)
  def winning_cost(state, {suit, rank} = card), do: Game.card_points(card, state.trump) * 5 + Game.card_strength(rank, suit == state.trump)
  def trump_priority({_suit, rank}), do: %{jack: 8, nine: 7, ace: 6, ten: 5, king: 4, queen: 3, eight: 2, seven: 1}[rank]

  def hand_strength(cards, trump) do
    trump_points = cards |> Enum.filter(fn {suit, _rank} -> suit == trump end) |> Enum.map(&Game.card_points(&1, trump)) |> Enum.sum()
    aces = Enum.count(cards, fn {_suit, rank} -> rank == :ace end) * 10
    tens = Enum.count(cards, fn {_suit, rank} -> rank == :ten end) * 5
    trumps = Enum.count(cards, fn {suit, _rank} -> suit == trump end) * 4
    trump_points + aces + tens + trumps
  end

  def card_value(state, seat, card) do
    winning = if state.trick == [], do: true, else: Game.trick_winner(state.trick ++ [%{seat: seat, card: card}], state.trump) == seat
    points = Game.card_points(card, state.trump)
    trump_bonus = if elem(card, 0) == state.trump, do: 8, else: 0
    partner_winning = state.trick != [] and Game.team(Game.trick_winner(state.trick, state.trump)) == Game.team(seat)

    cond do
      winning and state.trick == [] -> 100 - points - trump_bonus
      winning -> 80 + points + trump_bonus
      partner_winning -> 60 - points - trump_bonus
      true -> 30 - points - trump_bonus
    end
  end
end
