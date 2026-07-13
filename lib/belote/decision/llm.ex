defmodule Belote.Decision.LLM do
  @moduledoc """
  Option LLM strictement bornée : le modèle choisit un index dans les actions
  calculées par le moteur. Toute réponse invalide laisse le PNJ local jouer.
  """

  alias Belote.Game

  def decide(state, seat, config) do
    actions = Game.legal_actions(state, seat)

    with true <- config.enabled,
         {:ok, response} <- LlmComposer.simple_chat(settings(config), Poison.encode!(prompt(state, seat, actions))),
         content when is_binary(content) <- response.main_response && response.main_response.content,
         {:ok, %{"choice" => choice}} <- Poison.decode(content),
         true <- is_integer(choice) and choice in 0..(length(actions) - 1) do
      {:ok, Enum.at(actions, choice)}
    else
      _reason -> {:error, :unavailable}
    end
  rescue
    _error -> {:error, :unavailable}
  end

  def settings(config) do
    %LlmComposer.Settings{
      api_key: config.api_key,
      system_prompt: "Tu joues à la belote. Réponds uniquement par un JSON {\"choice\": n}. Choisis une action légale, sans explication.",
      track_costs: false,
      providers: [{LlmComposer.Providers.OpenRouter, [api_key: config.api_key, url: config.base_url, model: config.decision_model, timeout: config.timeout_ms, headers: Poker.Decision.LLMShadow.headers(config), request_params: %{"temperature" => 0.1, "max_tokens" => 30}]}]
    }
  end

  def prompt(state, seat, actions) do
    %{
      seat: seat,
      hand: Enum.map(state.hands[seat], &Belote.Table.card_text/1),
      trump: state.trump,
      contract: state.contract,
      trick: Enum.map(state.trick, fn entry -> %{seat: entry.seat, card: Belote.Table.card_text(entry.card)} end),
      actions: Enum.with_index(actions, fn action, index -> %{choice: index, action: inspect(action)} end)
    }
  end
end
