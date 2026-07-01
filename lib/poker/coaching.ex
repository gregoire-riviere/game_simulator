defmodule Poker.Coaching do
  @moduledoc """
  Conseils courts de progression poker via LLM.

  Le coaching reste pédagogique : il ne choisit jamais une action de jeu.
  """

  def call(config, context) do
    if config.enabled do
      safe_request(config, context)
    else
      {:error, :llm_disabled}
    end
  end

  def safe_request(config, context) do
    task = Task.async(fn -> request(config, context) end)

    case Task.yield(task, config.timeout_ms) || Task.shutdown(task, :brutal_kill) do
      {:ok, result} -> result
      nil -> {:error, :timeout}
      {:exit, reason} -> {:error, reason}
    end
  end

  def request(config, context) do
    settings = %LlmComposer.Settings{
      api_key: config.api_key,
      system_prompt: system_prompt(),
      track_costs: false,
      providers: [
        {LlmComposer.Providers.OpenRouter,
         [
           api_key: config.api_key,
           url: config.base_url,
           model: config.decision_model,
           timeout: config.timeout_ms,
           headers: Poker.Decision.LLMShadow.headers(config),
           response_schema: response_schema(),
           request_params: %{"temperature" => 0.2, "max_tokens" => 220}
         ]}
      ]
    }

    case LlmComposer.simple_chat(settings, Poison.encode!(prompt(context))) do
      {:ok, response} -> parse_response(response)
      {:error, reason} -> {:error, reason}
    end
  end

  def parse_response(response) do
    content = response.main_response && response.main_response.content

    with true <- is_binary(content),
         {:ok, decoded} <- Poison.decode(content),
         {:ok, advice} <- validate_response(decoded) do
      {:ok, advice}
    else
      false -> {:error, :empty_response}
      {:error, reason} -> {:error, reason}
    end
  end

  def validate_response(%{"advice" => advice, "why" => why}) when is_binary(advice) and is_binary(why) do
    {:ok, %{advice: String.slice(advice, 0, 180), why: String.slice(why, 0, 240)}}
  end

  def validate_response(_decoded), do: {:error, :invalid_response}

  def prompt(context) do
    %{
      context: "Je suis un joueur de poker qui cherche a devenir rentable en NL2 et qui a besoin de conseils simples.",
      current_spot: context_text(context),
      task: "Donne un seul conseil tres court et concret adapte a la situation actuelle, puis explique pourquoi en une phrase courte.",
      constraints: [
        "Tu peux mentionner une tendance de jeu utile, mais ne donne pas un ordre mecanique du type clique sur tel bouton.",
        "Reste adapte a un joueur de NL2.",
        "Evite les concepts avances si un principe simple suffit."
      ]
    }
  end

  def context_text(context) do
    hero = context.hero
    actions = Enum.map_join(context.legal_actions, ", ", &action_text/1)
    villains = context.players |> Enum.reject(&(&1.id == "hero")) |> Enum.map_join(" | ", &player_text/1)
    history = Enum.map_join(context.hand_actions, " / ", &history_text/1)

    [
      "Format: #{context.format}",
      "Street: #{context.phase}, hero_turn: #{context.hero_turn}, hand_finished: #{context.hand_finished}",
      "Hero: #{Enum.join(hero.cards, " ")} #{hero.position}, stack #{hero.stack}, contribution #{hero.contribution}",
      "Board: #{Enum.join(context.board, " ")}",
      "Pot: #{context.pot}, blinds #{context.blinds.small}/#{context.blinds.big}",
      "Actions legales: #{actions}",
      "Joueurs: #{villains}",
      "Historique main: #{history}"
    ]
    |> Enum.join("\n")
  end

  def action_text(%{action: action, min: min, max: max}), do: "#{action} #{min}-#{max}"
  def action_text(%{action: action}), do: action

  def player_text(player) do
    "#{player.name} #{player.position} stack #{player.stack} contrib #{player.contribution} folded #{player.folded} active #{player.active}"
  end

  def history_text(%{player: player, action: action}), do: "#{player}: #{action}"
  def history_text(_action), do: ""

  def system_prompt do
    """
    Tu es un coach de poker micro-limites. Tu aides un joueur de NL2 a progresser avec des conseils courts, prudents et exploitables.
    Tu utilises la main, le board, le pot, les stacks, les positions et l'historique fournis pour donner un conseil contextuel simple.
    Reponds uniquement en JSON valide, sans markdown.
    """
    |> String.trim()
  end

  def response_schema do
    %{
      "type" => "object",
      "additionalProperties" => false,
      "required" => ["advice", "why"],
      "properties" => %{
        "advice" => %{"type" => "string", "maxLength" => 180},
        "why" => %{"type" => "string", "maxLength" => 240}
      }
    }
  end
end
