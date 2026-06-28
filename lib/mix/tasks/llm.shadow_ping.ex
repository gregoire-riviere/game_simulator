defmodule Mix.Tasks.Llm.ShadowPing do
  @moduledoc """
  Teste rapidement la connectivité OpenRouter du shadow mode LLM.

  Usage:

      GAME_SIMULATOR_LLM_API_KEY=... mix llm.shadow_ping
  """

  use Mix.Task

  @shortdoc "Teste un appel OpenRouter court pour le shadow mode LLM"

  @impl true
  def run(_args) do
    Mix.Task.run("app.config")
    Application.ensure_all_started(:llm_composer)

    config = GameSimulator.Configuration.llm!()

    if is_nil(config.api_key) or config.api_key == "" do
      Mix.raise("GAME_SIMULATOR_LLM_API_KEY is required for mix llm.shadow_ping")
    end

    profile = %{Poker.Profile.new(1) | name: "Ping", archetype: :tag}
    context = ping_context()
    metadata = %{hero_in_hand: true, previous_aggressive_action: true, interest_score: 6}
    shadow = Poker.Decision.LLMShadow.call(profile, context, :call, metadata, config)

    case shadow.status do
      "available" ->
        Mix.shell().info("LLM shadow ping OK")
        Mix.shell().info("model=#{shadow.model} action=#{shadow.action} confidence=#{inspect(shadow.confidence)}")
        Mix.shell().info("reason=#{shadow.short_reason}")

      "error" ->
        Mix.raise("LLM shadow ping failed: #{shadow.error}")
    end
  end

  def ping_context do
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
