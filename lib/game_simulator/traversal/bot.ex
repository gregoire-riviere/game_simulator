defmodule GameSimulator.Traversal.Bot do
  @moduledoc "Deterministic bounded search. No model, network call, randomness or extra dependency."
  alias GameSimulator.Traversal.Game

  def limits("easy"), do: %{depth: 1, width: 1, nodes: 0, milliseconds: 0}
  def limits("medium"), do: %{depth: 2, width: 5, nodes: 70, milliseconds: 180}
  def limits("hard"), do: %{depth: 3, width: 8, nodes: 360, milliseconds: 600}

  def choose(game, difficulty) do
    budget = limits(difficulty)
    deadline = System.monotonic_time(:millisecond) + budget.milliseconds
    options = ranked(game, game.turn)
    case options do
      [] -> nil
      [{fallback, _score} | _rest] ->
        if difficulty == "easy" do
          fallback
        else
          {best, _score, _nodes} = Enum.reduce_while(Enum.take(options, budget.width), {fallback, -2_000_000, budget.nodes}, fn {move, _estimate}, {best, score, nodes} ->
            if exhausted?(nodes, deadline) do
              {:halt, {best, score, nodes}}
            else
              {value, left} = search(Game.apply_action(game, move), budget.depth - 1, game.turn, budget, nodes - 1, deadline, -2_000_000, 2_000_000)
              if value > score, do: {:cont, {move, value, left}}, else: {:cont, {best, score, left}}
            end
          end)
          best
        end
    end
  end

  def exhausted?(nodes, deadline), do: nodes <= 0 or System.monotonic_time(:millisecond) >= deadline

  def ranked(game, player) do
    Game.actions(game) |> Enum.map(fn move -> {move, evaluate(Game.apply_action(game, move), player)} end) |> Enum.sort_by(fn {move, value} -> {-value, move.piece, move.row, move.col} end)
  end

  # Beam width, depth, node budget and a monotonic deadline all bound the search.
  def search(game, depth, player, budget, nodes, deadline, alpha, beta) do
    if depth == 0 or game.result != nil or exhausted?(nodes, deadline) do
      {evaluate(game, player), nodes}
    else
      maximizing = game.turn == player
      choices = ranked(game, game.turn) |> Enum.take(budget.width)
      if choices == [] do
        {evaluate(game, player), nodes}
      else
        initial = if maximizing, do: -2_000_000, else: 2_000_000
        {value, left, _alpha, _beta} = Enum.reduce_while(choices, {initial, nodes, alpha, beta}, fn {move, _estimate}, {best, left, a, b} ->
          if exhausted?(left, deadline) do
            {:halt, {if(best == initial, do: evaluate(game, player), else: best), left, a, b}}
          else
            {value, remaining} = search(Game.apply_action(game, move), depth - 1, player, budget, left - 1, deadline, a, b)
            best = if maximizing, do: max(best, value), else: min(best, value)
            a = if maximizing, do: max(a, best), else: a
            b = if maximizing, do: b, else: min(b, best)
            if a >= b, do: {:halt, {best, remaining, a, b}}, else: {:cont, {best, remaining, a, b}}
          end
        end)
        {value, left}
      end
    end
  end

  # Terminal outcomes dominate every positional term, including a first Sentinel exit.
  def evaluate(%{result: %{winner: winner}}, player) do
    cond do winner == player -> 1_000_000; winner == 0 -> 0; true -> -1_000_000 end
  end
  def evaluate(game, player) do
    [a, b] = game.scores
    score = if player == 1, do: a - b, else: b - a
    score * 500 + Enum.reduce(Game.active(game), 0, fn piece, sum ->
      progress = 9 - abs(piece.row - Game.last_row(piece.player))
      neighbours = Game.neighbours(piece.row, piece.col) |> Enum.map(fn {r, c} -> Game.occupant(game, r, c) end) |> Enum.reject(&is_nil/1)
      support = Enum.count(neighbours, &(&1.player == piece.player))
      threats = Enum.count(neighbours, fn enemy -> enemy.player != piece.player and Game.combat(game, enemy, piece, 1).attack >= Game.combat(game, enemy, piece, 1).defence end)
      forward = piece.row + if(piece.player == 1, do: -1, else: 1)
      terrain_cost = if Game.inside?(forward, piece.col), do: abs(Game.height(game.board, piece.row, piece.col) - Game.height(game.board, forward, piece.col)), else: 0
      sentinel = if piece.type == "sentinel" and game.exited == [], do: progress * 7, else: 0
      value = piece.strength * 65 + progress * (12 + piece.strength * 2) + sentinel + support * 9 - threats * (35 + piece.strength * 15) - terrain_cost * 5
      sum + if(piece.player == player, do: value, else: -value)
    end)
  end
end
