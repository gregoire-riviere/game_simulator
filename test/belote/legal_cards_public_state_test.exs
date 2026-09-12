defmodule Belote.LegalCardsPublicStateTest do
  use ExUnit.Case, async: true

  alias Belote.{Game, Table}

  test "publishes exactly the human legal cards only when the human must play" do
    game =
      Game.new(:coinche, 1_000)
      |> Map.merge(%{
        phase: :playing,
        turn: 4,
        trump: :hearts,
        hands: %{
          1 => [{:clubs, :ace}],
          2 => [{:clubs, :king}],
          3 => [{:clubs, :queen}],
          4 => [{:clubs, :seven}, {:hearts, :seven}, {:hearts, :jack}]
        },
        trick: [%{seat: 1, card: {:clubs, :ace}}],
        contract: %{team: 0, amount: 80, multiplier: 1, taker: 4, suit: :hearts}
      })

    state = %{owner: "alice", game_key: "belote:coinche", game: game, bot_names: Table.default_bot_names(), llm_mode: :local, llm_remaining: 10}
    public = Table.public_state(state, "alice")

    assert public.legal_cards == Enum.map(Game.legal_cards(game, 4), fn {:play, card} -> Table.card_text(card) end)
    refute Table.card_text({:hearts, :seven}) in public.legal_cards
    assert public.legal_card_reason == "couleur demandée"

    waiting = Table.public_state(%{state | game: %{game | turn: 1}}, "alice")
    assert waiting.legal_cards == []
    assert waiting.legal_card_reason == nil
  end
end
