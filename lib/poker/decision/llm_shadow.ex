defmodule Poker.Decision.LLMShadow do
  @moduledoc """
  Appel shadow OpenRouter pour les décisions PNJ.

  Ce module ne renvoie jamais une action à appliquer au moteur. Il transforme la
  réponse du modèle en observation validée pour l'UI et l'audit.
  """

  def call(profile, context, local_action, metadata, config) do
    started_at = System.monotonic_time(:millisecond)

    try do
      task =
        Task.async(fn ->
          request(profile, context, local_action, metadata, config)
        end)

      case Task.yield(task, config.timeout_ms) || Task.shutdown(task, :brutal_kill) do
        {:ok, shadow} -> Map.put(shadow, :latency_ms, elapsed_ms(started_at))
        {:exit, reason} -> error_shadow(config, "provider_exit: #{inspect(reason)}", elapsed_ms(started_at))
        nil -> error_shadow(config, "timeout", elapsed_ms(started_at))
      end
    rescue
      error -> error_shadow(config, Exception.message(error), elapsed_ms(started_at))
    catch
      :exit, reason -> error_shadow(config, "provider_exit: #{inspect(reason)}", elapsed_ms(started_at))
    end
  end

  def request(profile, context, local_action, metadata, config) do
    settings = settings(config)
    prompt = user_prompt(profile, context, local_action, metadata)

    case LlmComposer.simple_chat(settings, Poison.encode!(prompt)) do
      {:ok, response} -> parse_response(response, context, local_action, config)
      {:error, reason} -> error_shadow(config, inspect(reason), nil)
    end
  end

  def settings(config) do
    %LlmComposer.Settings{
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
           headers: headers(config),
           response_schema: response_schema(),
           request_params: %{"temperature" => 0.2, "max_tokens" => 240}
         ]}
      ]
    }
  end

  def headers(config) do
    []
    |> maybe_header("HTTP-Referer", config.http_referer)
    |> maybe_header("X-Title", config.x_title)
  end

  def maybe_header(headers, _name, nil), do: headers
  def maybe_header(headers, _name, ""), do: headers
  def maybe_header(headers, name, value), do: [{name, value} | headers]

  def parse_response(response, context, local_action, config) do
    content = response.main_response && response.main_response.content

    with true <- is_binary(content),
         {:ok, decoded} <- Poison.decode(content) do
      decoded
      |> validate_response(context)
      |> shadow_from_validation(response, local_action, config)
    else
      false -> error_shadow(config, "empty_response", nil)
      {:error, _reason} -> error_shadow(config, "invalid_json", nil)
    end
  end

  def shadow_from_validation({:ok, decision}, response, local_action, config) do
    %{
      status: "available",
      provider: config.provider,
      model: provider_model(response, config),
      action: decision.action,
      amount: decision.amount,
      valid: true,
      diverged: diverged?(local_action, decision),
      confidence: decision.confidence,
      reason_tags: decision.reason_tags,
      short_reason: decision.short_reason,
      memory_update: decision.memory_update,
      cost_usd: cost_usd(response)
    }
  end

  def shadow_from_validation({:error, reason, decision}, response, local_action, config) do
    %{
      status: "error",
      provider: config.provider,
      model: provider_model(response, config),
      action: Map.get(decision, :action),
      amount: Map.get(decision, :amount),
      valid: false,
      diverged: diverged?(local_action, decision),
      confidence: Map.get(decision, :confidence),
      reason_tags: Map.get(decision, :reason_tags, []),
      short_reason: Map.get(decision, :short_reason),
      error: Atom.to_string(reason),
      cost_usd: cost_usd(response)
    }
  end

  def validate_response(decoded, context) when is_map(decoded) do
    decision = %{
      action: decoded["action"],
      amount: decoded["amount"],
      confidence: confidence(decoded["confidence"]),
      reason_tags: reason_tags(decoded["reason_tags"]),
      short_reason: short_reason(decoded["short_reason"]),
      memory_update: memory_update(decoded["memory_update"])
    }

    cond do
      decision.action not in ["fold", "check", "call", "bet", "raise", "all_in"] ->
        {:error, :invalid_action, decision}

      not legal_action?(decision, context) ->
        {:error, :illegal_action, decision}

      true ->
        {:ok, decision}
    end
  end

  def validate_response(_decoded, _context), do: {:error, :invalid_json, %{}}

  def legal_action?(%{action: action}, context) when action in ["fold", "check", "call", "all_in"] do
    String.to_existing_atom(action) in context.actions
  rescue
    ArgumentError -> false
  end

  def legal_action?(%{action: "bet", amount: amount}, context) when is_integer(amount) do
    case Enum.find(context.actions, &match?(%{bet: _limits}, &1)) do
      %{bet: %{min: min, max: max}} -> amount in min..max
      _other -> false
    end
  end

  def legal_action?(%{action: "raise", amount: amount}, context) when is_integer(amount) do
    case Enum.find(context.actions, &match?(%{raise_to: _limits}, &1)) do
      %{raise_to: %{min: min, max: max}} -> amount in min..max
      _other -> false
    end
  end

  def legal_action?(_decision, _context), do: false

  def diverged?(local_action, %{action: action, amount: amount}) do
    Poker.Decision.Router.local_action_map(local_action) != %{action: action, amount: amount}
  end

  def diverged?(_local_action, _decision), do: false

  def provider_model(response, config) do
    response.provider_model || config.decision_model
  end

  def cost_usd(%{cost_info: %{total_cost: nil}}), do: nil
  def cost_usd(%{cost_info: %{total_cost: value}}), do: to_string(value)
  def cost_usd(_response), do: nil

  def confidence(value) when is_integer(value), do: value / 1
  def confidence(value) when is_float(value), do: min(max(value, 0.0), 1.0)
  def confidence(_value), do: nil

  def reason_tags(tags) when is_list(tags) do
    tags
    |> Enum.filter(&is_binary/1)
    |> Enum.take(6)
  end

  def reason_tags(_tags), do: []

  def short_reason(reason) when is_binary(reason), do: String.slice(reason, 0, 240)
  def short_reason(_reason), do: nil

  def memory_update(update) when is_map(update), do: Map.take(update, ["tilt_delta", "note"])
  def memory_update(_update), do: %{}

  def error_shadow(config, error, latency_ms) do
    %{
      status: "error",
      provider: config.provider,
      model: config.decision_model,
      valid: false,
      error: error,
      latency_ms: latency_ms
    }
  end

  def elapsed_ms(started_at), do: System.monotonic_time(:millisecond) - started_at

  def user_prompt(profile, context, local_action, metadata) do
    made_category = Poker.Decision.Router.made_category(context)
    draw = Poker.Decision.Router.draw_category(context)

    %{
      format: "NL2 6-max",
      blinds: %{small: div(context.big_blind, 2), big: context.big_blind},
      phase: context.phase,
      pot: context.pot,
      effective_stack: context.effective_stack,
      position: context.position,
      board: card_codes(context.board),
      bot_cards: card_codes(context.cards),
      legal_actions: legal_actions(context.actions),
      bot_profile: %{
        archetype: profile.archetype,
        description: profile.short_description,
        aggression: profile.aggression,
        bluff: profile.bluff,
        call_too_wide: profile.call_too_wide,
        overplays_top_pair: profile.overplays_top_pair,
        chases_draws: profile.chases_draws
      },
      bot_memory: profile.memory,
      local_features: %{
        made_hand_category: made_category,
        draw: draw,
        pot_odds: context.pot_odds,
        spr: spr(context),
        facing_cbet: context.facing_cbet,
        opponent_sizing_ratio: context.bet_size_ratio,
        stack_pressure: context.stack_pressure,
        to_call: context.to_call,
        local_action: Poker.Decision.Router.local_action_map(local_action),
        previous_aggressive_action: Map.get(metadata, :previous_aggressive_action, false),
        interest_score: Map.get(metadata, :interest_score)
      }
    }
  end

  def legal_actions(actions) do
    Enum.map(actions, fn
      %{bet: limits} -> %{action: "bet", min: limits.min, max: limits.max}
      %{raise_to: limits} -> %{action: "raise", min: limits.min, max: limits.max}
      action when is_atom(action) -> %{action: Atom.to_string(action)}
    end)
  end

  def spr(%{effective_stack: effective_stack, pot: pot}) when pot > 0 do
    Float.round(effective_stack / pot, 2)
  end

  def spr(_context), do: nil

  def card_codes(cards), do: Enum.map(cards, &card_code/1)
  def card_code({rank, "clubs"}), do: rank_symbol(rank) <> "c"
  def card_code({rank, "diamonds"}), do: rank_symbol(rank) <> "d"
  def card_code({rank, "hearts"}), do: rank_symbol(rank) <> "h"
  def card_code({rank, "spades"}), do: rank_symbol(rank) <> "s"
  def rank_symbol("10"), do: "T"
  def rank_symbol(rank), do: rank

  def system_prompt do
    """
    Tu es un joueur de poker NL2 réaliste. Tu dois décider ce que ce profil PNJ aurait fait dans ce spot.
    Tu ne connais que les informations publiques et les cartes du PNJ. Tu dois respecter strictement les actions légales fournies.
    Réponds uniquement en JSON valide, sans markdown.
    """
    |> String.trim()
  end

  def response_schema do
    %{
      "type" => "object",
      "additionalProperties" => false,
      "required" => ["action", "amount", "confidence", "reason_tags", "short_reason", "memory_update"],
      "properties" => %{
        "action" => %{"type" => "string", "enum" => ["fold", "check", "call", "bet", "raise", "all_in"]},
        "amount" => %{"type" => ["integer", "null"]},
        "confidence" => %{"type" => "number", "minimum" => 0, "maximum" => 1},
        "reason_tags" => %{"type" => "array", "items" => %{"type" => "string"}, "maxItems" => 6},
        "short_reason" => %{"type" => "string", "maxLength" => 240},
        "memory_update" => %{
          "type" => "object",
          "additionalProperties" => false,
          "required" => ["tilt_delta", "note"],
          "properties" => %{
            "tilt_delta" => %{"type" => "number"},
            "note" => %{"type" => "string", "maxLength" => 180}
          }
        }
      }
    }
  end
end
