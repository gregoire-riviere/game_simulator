defmodule Poker.LLMShadowAudit do
  @moduledoc """
  Audit NDJSON du shadow mode LLM.

  L'écriture est volontairement best effort : un problème de disque ne doit jamais
  interrompre une main.
  """

  def append(file, entry) do
    directory = Path.dirname(file)
    line = Poison.encode!(entry) <> "\n"

    with :ok <- File.mkdir_p(directory),
         :ok <- File.write(file, line, [:append]) do
      :ok
    else
      _error -> :ok
    end
  rescue
    _error -> :ok
  end

  def stats(file) do
    case read_entries(file) do
      {:ok, entries} ->
        {:ok,
         %{
           calls: length(entries),
           divergence_rate: rate(Enum.count(entries, & &1["diverged"]), length(entries)),
           divergence_by_street: grouped_rate(entries, "phase", "diverged"),
           divergence_by_archetype: grouped_rate(entries, "archetype", "diverged"),
           invalid_actions: Enum.count(entries, &(not &1["llm_valid"])),
           average_latency_ms: average_latency(entries),
           p95_latency_ms: p95_latency(entries),
           errors: error_counts(entries),
           estimated_cost_usd: estimated_cost(entries)
         }}

      error ->
        error
    end
  end

  def read_entries(file) do
    case File.read(file) do
      {:ok, content} ->
        entries =
          content
          |> String.split("\n", trim: true)
          |> Enum.flat_map(&decode_line/1)

        {:ok, entries}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def decode_line(line) do
    case Poison.decode(line) do
      {:ok, entry} -> [entry]
      {:error, _reason} -> []
    end
  end

  def grouped_rate(entries, group_key, value_key) do
    entries
    |> Enum.group_by(&Map.get(&1, group_key, "unknown"))
    |> Map.new(fn {key, group} -> {key, rate(Enum.count(group, & &1[value_key]), length(group))} end)
  end

  def rate(_count, 0), do: 0.0
  def rate(count, total), do: Float.round(count / total, 4)

  def average_latency(entries) do
    latencies = latencies(entries)

    case latencies do
      [] -> nil
      values -> Float.round(Enum.sum(values) / length(values), 1)
    end
  end

  def p95_latency(entries) do
    values = latencies(entries) |> Enum.sort()

    case values do
      [] ->
        nil

      _values ->
        index = max(0, ceil(length(values) * 0.95) - 1)
        Enum.at(values, index)
    end
  end

  def latencies(entries) do
    entries
    |> Enum.map(& &1["latency_ms"])
    |> Enum.filter(&is_number/1)
  end

  def error_counts(entries) do
    entries
    |> Enum.map(& &1["error"])
    |> Enum.reject(&is_nil/1)
    |> Enum.frequencies()
  end

  def estimated_cost(entries) do
    costs =
      entries
      |> Enum.map(& &1["cost_usd"])
      |> Enum.flat_map(&parse_cost/1)

    case costs do
      [] -> nil
      values -> Enum.sum(values)
    end
  end

  def parse_cost(nil), do: []
  def parse_cost(value) when is_number(value), do: [value]

  def parse_cost(value) when is_binary(value) do
    case Float.parse(value) do
      {number, ""} -> [number]
      _other -> []
    end
  end

  def parse_cost(_value), do: []
end
