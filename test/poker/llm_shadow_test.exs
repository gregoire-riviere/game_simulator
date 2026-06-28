defmodule Poker.LLMShadowTest do
  use ExUnit.Case, async: true

  test "validates legal raise amounts from LLM response" do
    context = context()

    assert {:ok, decision} =
             Poker.Decision.LLMShadow.validate_response(
               %{
                 "action" => "raise",
                 "amount" => 80,
                 "confidence" => 0.7,
                 "reason_tags" => ["pressure"],
                 "short_reason" => "Relance forte mais légale.",
                 "memory_update" => %{"tilt_delta" => 0.0, "note" => ""}
               },
               context
             )

    assert decision.action == "raise"
    assert decision.amount == 80
  end

  test "marks illegal LLM actions invalid without crashing" do
    assert {:error, :illegal_action, decision} =
             Poker.Decision.LLMShadow.validate_response(
               %{
                 "action" => "bet",
                 "amount" => 80,
                 "confidence" => 0.7,
                 "reason_tags" => ["pressure"],
                 "short_reason" => "Mise impossible face à une mise.",
                 "memory_update" => %{"tilt_delta" => 0.0, "note" => ""}
               },
               context()
             )

    assert decision.action == "bet"
  end

  def context do
    %{
      phase: :turn,
      cards: [{"Q", "clubs"}, {"9", "clubs"}],
      board: [{"Q", "diamonds"}, {"8", "hearts"}, {"5", "clubs"}, {"2", "spades"}],
      pot: 50,
      stack: 150,
      position: :button,
      to_call: 30,
      pot_odds: 0.37,
      bet_size_ratio: 0.60,
      stack_pressure: 0.20,
      effective_stack: 150,
      current_bet: 30,
      preflop_raise_count: 1,
      big_blind: 2,
      players_in_hand: 2,
      facing_cbet: false,
      actions: [:fold, :call, %{raise_to: %{min: 60, max: 180}}, :all_in]
    }
  end
end
