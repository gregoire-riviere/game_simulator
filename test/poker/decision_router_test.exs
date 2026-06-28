defmodule Poker.DecisionRouterFakeClient do
  def call(_profile, _context, _local_action, metadata, config) do
    send(metadata.test_pid, {:llm_shadow_called, metadata.interest_score})

    %{
      status: "available",
      provider: config.provider,
      model: config.decision_model,
      action: "fold",
      amount: nil,
      valid: true,
      diverged: true,
      confidence: 0.68,
      reason_tags: ["pot_odds"],
      short_reason: "Fold prudent contre forte pression.",
      latency_ms: 12
    }
  end
end

defmodule Poker.DecisionRouterTest do
  use ExUnit.Case, async: false

  test "shadow off returns local action without calling the client" do
    context = interesting_context()
    profile = %{Poker.Profile.new(1) | archetype: :tag}
    result = Poker.Decision.Router.decide(profile, context, metadata(false, 1))

    assert result.action in [:fold, :call, :all_in] or match?({:raise_to, _amount}, result.action)
    assert result.llm_shadow.status == "skipped"
    refute_received {:llm_shadow_called, _score}
  end

  test "shadow on but score below threshold skips the client" do
    context = %{interesting_context() | phase: :flop, pot: 8, to_call: 0, pot_odds: 0.0, actions: [:check, %{bet: %{min: 2, max: 200}}]}
    profile = %{Poker.Profile.new(1) | archetype: :tag}
    result = Poker.Decision.Router.decide(profile, context, metadata(true, 4))

    assert result.llm_shadow.status == "skipped"
    assert result.llm_shadow.reason == "score_below_threshold"
    refute_received {:llm_shadow_called, _score}
  end

  test "standard profile can trigger shadow on a large important spot" do
    context = interesting_context()
    profile = %{Poker.Profile.new(1) | archetype: :tag}
    result = Poker.Decision.Router.decide(profile, context, metadata(true, 4))

    assert_receive {:llm_shadow_called, score}
    assert score >= 4
    assert result.llm_shadow.status == "available"
    assert File.read!(audit_file()) =~ "\"player\":\"Sophie\""
  end


  test "llm mode applies a valid LLM decision" do
    context = interesting_context()
    profile = %{Poker.Profile.new(1) | archetype: :tag}
    config = Map.put(metadata(true, 4).llm_config, :mode, :llm)
    result = Poker.Decision.Router.decide(profile, context, %{base_metadata() | llm_config: config})

    assert_receive {:llm_shadow_called, _score}
    assert result.action == :fold
    assert result.local_action != result.action
  end

  test "typed profile is only a score bonus, not a hard filter" do
    context = %{interesting_context() | phase: :flop, pot: 8, to_call: 0, pot_odds: 0.0, actions: [:check, %{bet: %{min: 2, max: 200}}]}
    tag = %{Poker.Profile.new(1) | archetype: :tag}
    calling_station = %{Poker.Profile.new(1) | archetype: :calling_station}

    assert Poker.Decision.Router.interest_score(calling_station, context, :check, base_metadata()) ==
             Poker.Decision.Router.interest_score(tag, context, :check, base_metadata()) + 1
  end

  def interesting_context do
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

  def metadata(enabled, threshold) do
    Map.put(base_metadata(), :llm_config, %{
      enabled: enabled,
      shadow_mode: true,
      provider: "openrouter",
      api_key: "test-key",
      base_url: "https://openrouter.ai/api/v1",
      decision_model: "google/gemini-2.5-flash",
      timeout_ms: 1_500,
      audit_file: audit_file(),
      http_referer: nil,
      x_title: "game_simulator",
      interest_threshold: threshold,
      client: Poker.DecisionRouterFakeClient
    })
  end

  def base_metadata do
    %{
      hand_id: "test-hand",
      player_name: "Sophie",
      hero_in_hand: true,
      previous_aggressive_action: true,
      test_pid: self()
    }
  end

  def audit_file do
    Path.join(System.tmp_dir!(), "game_simulator-router-test-#{inspect(self())}.ndjson")
  end
end
