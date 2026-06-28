defmodule Poker.Decision.Router do
  @moduledoc """
  Routeur de décision PNJ.

  La décision locale reste toujours l'action retournée au moteur. Le LLM ne sert
  qu'à produire une observation shadow optionnelle pour l'UI et l'audit.
  """

  @typed_profiles [:calling_station, :lag, :spewy_aggro, :nit_weak]

  def decide(profile, context, metadata) do
    local_action = Poker.Decision.decide(profile, context)
    config = Map.get(metadata, :llm_config, GameSimulator.Configuration.llm!())
    score = interest_score(profile, context, local_action, metadata)
    metadata = Map.put(metadata, :interest_score, score)

    shadow =
      cond do
        not config.enabled ->
          skipped_shadow(score, "disabled")

        not config.shadow_mode ->
          skipped_shadow(score, "shadow_mode_off")

        score < config.interest_threshold ->
          skipped_shadow(score, "score_below_threshold")

        true ->
          config.client.call(profile, context, local_action, metadata, config)
      end

    audit_shadow(profile, context, local_action, metadata, shadow, config)
    %{action: local_action, llm_shadow: shadow}
  end

  def interest_score(profile, context, local_action, metadata) do
    [
      if(Map.get(metadata, :hero_in_hand), do: 2, else: 0),
      if(context.phase in [:turn, :river], do: 1, else: 0),
      if(context.pot >= context.big_blind * 20, do: 1, else: 0),
      if(big_call?(context), do: 1, else: 0),
      if(Map.get(metadata, :previous_aggressive_action), do: 1, else: 0),
      if(difficult_decision?(profile, context, local_action), do: 1, else: 0),
      if(profile.archetype in @typed_profiles, do: 1, else: 0)
    ]
    |> Enum.sum()
  end

  def big_call?(%{pot: pot, to_call: to_call}) when pot > 0 and to_call > 0 do
    to_call / pot >= 0.5
  end

  def big_call?(_context), do: false

  def difficult_decision?(_profile, %{phase: :preflop}, _local_action), do: false
  def difficult_decision?(_profile, %{to_call: to_call}, _local_action) when to_call <= 0, do: false

  def difficult_decision?(_profile, context, local_action) do
    made_category = made_category(context)
    draw = draw_category(context)
    local_action_name = local_action_name(local_action)

    local_action_name in ["call", "fold", "raise", "all_in"] and
      (made_category in [:medium, :ace_high] or draw != :none or context.pot_odds >= 0.25)
  end

  def made_category(%{cards: cards, board: board}) when length(board) >= 3 do
    cards
    |> Poker.Decision.made_hand_category(board)
    |> Poker.Decision.hand_strength_category()
  end

  def made_category(_context), do: :unknown

  def draw_category(%{cards: cards, board: board}) when length(board) >= 3 do
    Poker.Decision.draw_category(cards, board)
  end

  def draw_category(_context), do: :none

  def skipped_shadow(score, reason), do: %{status: "skipped", reason: reason, score: score}

  def audit_shadow(_profile, _context, _local_action, _metadata, %{status: "skipped"}, _config), do: :ok

  def audit_shadow(profile, context, local_action, metadata, shadow, config) do
    config.audit_file
    |> Poker.LLMShadowAudit.append(audit_entry(profile, context, local_action, metadata, shadow, config))
  end

  def audit_entry(profile, context, local_action, metadata, shadow, config) do
    %{
      hand_id: Map.get(metadata, :hand_id),
      player: Map.get(metadata, :player_name),
      archetype: Atom.to_string(profile.archetype),
      phase: Atom.to_string(context.phase),
      board: Poker.Decision.LLMShadow.card_codes(context.board),
      local_action: local_action_map(local_action),
      llm_action: llm_action_map(shadow),
      llm_valid: Map.get(shadow, :valid, false),
      diverged: Map.get(shadow, :diverged, false),
      confidence: Map.get(shadow, :confidence),
      short_reason: Map.get(shadow, :short_reason),
      reason_tags: Map.get(shadow, :reason_tags, []),
      latency_ms: Map.get(shadow, :latency_ms),
      model: Map.get(shadow, :model, config.decision_model),
      provider: config.provider,
      error: Map.get(shadow, :error),
      cost_usd: Map.get(shadow, :cost_usd),
      score: Map.get(metadata, :interest_score)
    }
  end

  def local_action_map(action) do
    %{action: local_action_name(action), amount: local_action_amount(action)}
  end

  def local_action_name({:bet, _amount}), do: "bet"
  def local_action_name({:raise_to, _amount}), do: "raise"
  def local_action_name(action) when is_atom(action), do: Atom.to_string(action)

  def local_action_amount({:bet, amount}), do: amount
  def local_action_amount({:raise_to, amount}), do: amount
  def local_action_amount(_action), do: nil

  def llm_action_map(%{action: action, amount: amount}), do: %{action: action, amount: amount}
  def llm_action_map(_shadow), do: nil
end
