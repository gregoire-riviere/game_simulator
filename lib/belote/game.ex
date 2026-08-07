defmodule Belote.Game do
  @moduledoc """
  Moteur déterministe de belote à quatre joueurs.

  Les entrées sont toujours vérifiées ici : l'interface et les décideurs ne
  peuvent proposer que des actions, jamais contourner les règles.
  """

  @suits [:clubs, :diamonds, :hearts, :spades]
  @ranks [:seven, :eight, :nine, :ten, :jack, :queen, :king, :ace]

  def new(variant, target_score) when variant in [:classic, :coinche] and target_score in [501, 701, 1000, 2000] do
    new_deal(%{variant: variant, target_score: target_score, dealer: 4, scores: %{0 => 0, 1 => 0}, deal_number: 0, deal_history: [], match_winner: nil})
  end

  def new(%{variant: :coinche, phase: :playing} = state) do
    played_cards = for %{action: {:play, card}} <- state.history, do: card
    played_counts = Enum.frequencies(for %{seat: seat, action: {:play, _card}} <- state.history, do: seat)
    card_totals = Map.new(1..4, fn seat -> {seat, length(state.hands[seat]) + Map.get(played_counts, seat, 0)} end)
    missing_cards = deck() -- (Enum.flat_map(state.hands, fn {_seat, cards} -> cards end) ++ played_cards)

    # Les anciennes sauvegardes de Coinche ont pu distribuer seulement 31 cartes.
    if card_totals == %{1 => 8, 2 => 8, 3 => 8, 4 => 7} and length(missing_cards) == 1 do
      put_in(state, [:hands, 4], state.hands[4] ++ missing_cards)
    else
      state
    end
  end

  def new(state), do: state

  def new_deal(state) do
    dealer = next_seat(Map.get(state, :dealer, 4))
    deck = Enum.shuffle(deck())
    {hands, rest} = deal(deck, 5)
    {turned_card, remaining_deck} = if state.variant == :classic, do: {hd(rest), tl(rest)}, else: {nil, rest}
    phase = if state.variant == :classic, do: :classic_first, else: :coinche_bidding

    Map.merge(state, %{
      dealer: dealer,
      hands: hands,
      deck: remaining_deck,
      turned_card: turned_card,
      turn: next_seat(dealer),
      phase: phase,
      passes: 0,
      bid: nil,
      contract: nil,
      trump: nil,
      trick: [],
      last_trick: [],
      last_trick_winner: nil,
      last_trick_points: 0,
      trick_just_completed: false,
      trick_leader: next_seat(dealer),
      tricks: %{0 => [], 1 => []},
      deal_points: %{0 => 0, 1 => 0},
      history: [],
      last_event: nil,
      deal_number: Map.get(state, :deal_number, 0) + 1
    })
  end

  def deck, do: for(suit <- @suits, rank <- @ranks, do: {suit, rank})
  def suits, do: @suits
  def team(seat), do: rem(seat, 2)
  def partner(seat), do: next_seat(next_seat(seat))
  def next_seat(4), do: 1
  def next_seat(seat), do: seat + 1

  def deal(deck, count) do
    hands = Enum.into(1..4, %{}, fn seat -> {seat, Enum.take_every(Enum.drop(deck, seat - 1), 4) |> Enum.take(count)} end)
    {hands, Enum.drop(deck, count * 4)}
  end

  def legal_actions(%{phase: phase, turn: turn} = state, seat) when seat == turn and phase in [:classic_first, :classic_second] do
    suits = if phase == :classic_first, do: [elem(state.turned_card, 0)], else: @suits -- [elem(state.turned_card, 0)]
    [:pass | Enum.map(suits, &{:take, &1})]
  end

  def legal_actions(%{phase: :coinche_bidding, turn: turn} = state, seat) when seat == turn do
    bids = for amount <- 80..160//10, suit <- @suits, valid_bid?(state.bid, amount), do: {:bid, amount, suit}
    [:pass | bids] ++ coinche_actions(state, seat)
  end

  def legal_actions(%{phase: :playing, turn: turn} = state, seat) when seat == turn do
    Enum.map(legal_cards(state, seat), &{:play, &1})
  end

  def legal_actions(_state, _seat), do: []

  def act(state, seat, action) do
    if action in legal_actions(state, seat) do
      apply_action(state, seat, action)
    else
      {:error, :illegal_action}
    end
  end

  def apply_action(state, seat, :pass) when state.phase == :classic_first do
    state = record(state, seat, :pass)
    if state.passes == 3 do
      {:ok, %{state | phase: :classic_second, passes: 0, turn: next_seat(state.dealer), last_event: "Second tour de prise."}}
    else
      {:ok, %{state | passes: state.passes + 1, turn: next_seat(seat)}}
    end
  end

  def apply_action(state, seat, :pass) when state.phase == :classic_second do
    state = record(state, seat, :pass)
    if state.passes == 3 do
      {:ok, new_deal(state)}
    else
      {:ok, %{state | passes: state.passes + 1, turn: next_seat(seat)}}
    end
  end

  def apply_action(state, seat, {:take, suit}) do
    state = record(state, seat, {:take, suit})
    {:ok, start_play(%{state | trump: suit, contract: %{team: team(seat), amount: 82, multiplier: 1, taker: seat}})}
  end

  def apply_action(state, seat, {:bid, amount, suit}) do
    state = record(state, seat, {:bid, amount, suit})
    {:ok, %{state | bid: %{team: team(seat), amount: amount, suit: suit, taker: seat}, passes: 0, turn: next_seat(seat)}}
  end

  def apply_action(state, seat, :pass) when state.phase == :coinche_bidding do
    state = record(state, seat, :pass)

    cond do
      state.bid == nil and state.passes == 3 -> {:ok, new_deal(state)}
      state.bid != nil and state.passes == 2 -> {:ok, start_coinche_play(state)}
      true -> {:ok, %{state | passes: state.passes + 1, turn: next_seat(seat)}}
    end
  end

  def apply_action(state, seat, :coinche) do
    state = record(state, seat, :coinche)
    {:ok, %{state | bid: Map.put(state.bid, :multiplier, 2), turn: next_seat(seat), passes: 0}}
  end

  def apply_action(state, seat, :surcoinche) do
    state = record(state, seat, :surcoinche)
    state = %{state | bid: Map.put(state.bid, :multiplier, 4)}
    {:ok, start_coinche_play(state)}
  end

  def apply_action(state, seat, {:play, card}) do
    hand = Map.fetch!(state.hands, seat) -- [card]
    state = state |> put_in([:hands, seat], hand) |> record(seat, {:play, card})
    trick = state.trick ++ [%{seat: seat, card: card}]

    if length(trick) == 4 do
      resolve_trick(%{state | trick: trick})
    else
      {:ok, %{state | trick: trick, turn: next_seat(seat), trick_just_completed: false}}
    end
  end

  def start_coinche_play(state) do
    contract = Map.put_new(state.bid, :multiplier, 1)
    start_play(%{state | trump: contract.suit, contract: contract})
  end

  def start_play(state) do
    hands = if Enum.all?(state.hands, fn {_seat, cards} -> length(cards) == 5 end), do: add_remaining_cards(state), else: state.hands
    leader = next_seat(state.dealer)
    %{state | hands: hands, phase: :playing, turn: leader, trick_leader: leader, turned_card: nil, last_event: "Le jeu commence."}
  end

  def add_remaining_cards(%{variant: :coinche} = state) do
    Enum.reduce(1..4, {state.hands, state.deck}, fn seat, {hands, deck} ->
      {Map.update!(hands, seat, &(&1 ++ Enum.take(deck, 3))), Enum.drop(deck, 3)}
    end)
    |> elem(0)
  end

  def add_remaining_cards(state) do
    deck = state.deck -- [state.turned_card]

    Enum.reduce(1..4, {state.hands, deck}, fn seat, {hands, remaining} ->
      count = if seat == state.contract.taker, do: 2, else: 3
      cards = if seat == state.contract.taker, do: [state.turned_card | Enum.take(remaining, count)], else: Enum.take(remaining, count)
      {Map.update!(hands, seat, &(&1 ++ cards)), Enum.drop(remaining, count)}
    end)
    |> elem(0)
  end

  def resolve_trick(state) do
    winner = trick_winner(state.trick, state.trump)
    points = Enum.sum(Enum.map(state.trick, &card_points(&1.card, state.trump))) + if(Enum.all?(state.hands, fn {_seat, hand} -> hand == [] end), do: 10, else: 0)
    winner_team = team(winner)
    tricks = Map.update!(state.tricks, winner_team, &(&1 ++ [state.trick]))
    deal_points = Map.update!(state.deal_points, winner_team, &(&1 + points))
    state = %{state | tricks: tricks, deal_points: deal_points, trick: [], last_trick: state.trick, last_trick_winner: winner, last_trick_points: points, trick_just_completed: true, trick_leader: winner, turn: winner, last_event: "Pli remporté par l'équipe #{winner_team + 1}."}

    if Enum.all?(state.hands, fn {_seat, hand} -> hand == [] end), do: finish_deal(state), else: {:ok, state}
  end

  def finish_deal(state) do
    scores = score_deal(state)
    total_scores = Enum.into(scores, %{}, fn {team, points} -> {team, state.scores[team] + points} end)
    winner = Enum.find([0, 1], fn side -> total_scores[side] >= state.target_score end)
    deal_history = Map.get(state, :deal_history, []) ++ [deal_summary(state, scores)]
    {:ok, Map.merge(state, %{scores: total_scores, deal_history: deal_history, phase: if(winner, do: :match_finished, else: :deal_finished), match_winner: winner, last_event: deal_result_text(state, scores)})}
  end

  def deal_summary(state, scores) do
    taker_team = state.contract.team
    winner_team = if(scores[taker_team] > 0, do: taker_team, else: 1 - taker_team)

    %{
      number: state.deal_number,
      taker: state.contract.taker,
      amount: state.contract.amount,
      trump: state.trump,
      winner_team: winner_team,
      scores: scores
    }
  end

  def score_deal(%{variant: :classic} = state) do
    taking_team = state.contract.team
    defending_team = 1 - taking_team
    taking_points = state.deal_points[taking_team]

    if taking_points > 81 do
      %{taking_team => capot_score(state, taking_team, taking_points), defending_team => state.deal_points[defending_team]}
    else
      %{taking_team => 0, defending_team => 162}
    end
  end

  def score_deal(%{variant: :coinche} = state) do
    taking_team = state.contract.team
    defending_team = 1 - taking_team
    multiplier = state.contract.multiplier
    taking_points = state.deal_points[taking_team]

    if taking_points >= state.contract.amount do
      %{taking_team => (state.contract.amount + capot_score(state, taking_team, taking_points)) * multiplier, defending_team => state.deal_points[defending_team] * multiplier}
    else
      %{taking_team => 0, defending_team => (162 + state.contract.amount) * multiplier}
    end
  end

  def capot_score(state, team, points) do
    if length(state.tricks[team]) == 8, do: 252, else: points
  end

  def deal_result_text(_state, scores), do: "Donne terminée : équipe 1 +#{scores[0]}, équipe 2 +#{scores[1]}."

  def legal_cards(state, seat) do
    hand = state.hands[seat]

    case state.trick do
      [] -> hand
      [%{card: {lead_suit, _rank}} | _rest] ->
        following = Enum.filter(hand, fn {suit, _rank} -> suit == lead_suit end)

        cond do
          following != [] -> following
          team(trick_winner(state.trick, state.trump)) == team(seat) -> hand
          true -> trump_cards(hand, state)
        end
    end
  end

  def trump_cards(hand, state) do
    trumps = Enum.filter(hand, fn {suit, _rank} -> suit == state.trump end)
    winner = Enum.find(state.trick, fn entry -> entry.seat == trick_winner(state.trick, state.trump) end)

    if trumps != [] and elem(winner.card, 0) == state.trump do
      higher = Enum.filter(trumps, fn card -> beats?(card, winner.card, state.trump, state.trump) end)
      if higher == [], do: trumps, else: higher
    else
      if trumps == [], do: hand, else: trumps
    end
  end

  def trick_winner([first | rest], trump) do
    lead_suit = elem(first.card, 0)
    Enum.reduce(rest, first, fn entry, winner -> if beats?(entry.card, winner.card, lead_suit, trump), do: entry, else: winner end).seat
  end

  def beats?({suit, rank}, {other_suit, other_rank}, lead_suit, trump) do
    cond do
      suit == other_suit -> card_strength(rank, suit == trump) > card_strength(other_rank, other_suit == trump)
      suit == trump -> true
      other_suit == trump -> false
      suit == lead_suit -> true
      true -> false
    end
  end

  def card_strength(rank, true), do: Enum.find_index([:seven, :eight, :queen, :king, :ten, :ace, :nine, :jack], &(&1 == rank))
  def card_strength(rank, false), do: Enum.find_index([:seven, :eight, :nine, :jack, :queen, :king, :ten, :ace], &(&1 == rank))

  def card_points({suit, :jack}, trump) when suit == trump, do: 20
  def card_points({suit, :nine}, trump) when suit == trump, do: 14
  def card_points({_suit, :ace}, _trump), do: 11
  def card_points({_suit, :ten}, _trump), do: 10
  def card_points({_suit, :king}, _trump), do: 4
  def card_points({_suit, :queen}, _trump), do: 3
  def card_points({_suit, :jack}, _trump), do: 2
  def card_points(_card, _trump), do: 0

  def valid_bid?(nil, _amount), do: true
  def valid_bid?(bid, amount), do: amount > bid.amount

  def coinche_actions(%{bid: nil}, _seat), do: []
  def coinche_actions(%{bid: %{multiplier: 1, team: bid_team}}, seat), do: if(bid_team != team(seat), do: [:coinche], else: [])
  def coinche_actions(%{bid: %{multiplier: 2, team: bid_team}}, seat), do: if(bid_team == team(seat), do: [:surcoinche], else: [])
  def coinche_actions(_state, _seat), do: []

  def record(state, seat, action), do: %{state | history: state.history ++ [%{seat: seat, action: action, phase: state.phase}]}
end
