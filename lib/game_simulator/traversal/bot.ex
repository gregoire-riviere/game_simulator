defmodule GameSimulator.Traversal.Bot do
  @moduledoc "Deterministic bounded search. No model, network call, randomness or extra dependency."
  alias GameSimulator.Traversal.Game

  def limits("easy"), do: %{depth: 1, width: 1, nodes: 0, milliseconds: 0}
  def limits("medium"), do: %{depth: 2, width: 12, nodes: 500, milliseconds: 800}
  def limits("hard"), do: %{depth: 3, width: 18, nodes: 2500, milliseconds: 1600}

  def choose(game, difficulty) do
    budget = limits(difficulty)
    deadline = System.monotonic_time(:millisecond) + budget.milliseconds
    budget = Map.put(budget, :terrain, terrain(game.board, Map.get(game, :forests, [])))
    options = ranked(game, game.turn, budget.terrain)
    options = if difficulty == "easy", do: options, else: defend(game, options, deadline)
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

  def ranked(game, player), do: ranked(game, player, terrain(game.board, Map.get(game, :forests, [])))
  def ranked(game, player, terrain) do
    Game.actions(game)
    # An exited piece is inactive: its exit column has no strategic consequence.
    |> Enum.uniq_by(fn move -> if move.kind == "exit", do: {move.piece, "exit"}, else: {move.piece, move.row, move.col} end)
    |> Enum.map(fn move -> {move, evaluate(Game.apply_action(game, move), player, terrain)} end)
    |> Enum.sort_by(fn {move, value} -> {-value, move.piece, move.row, move.col} end)
  end

  def immediate_win?(game) do
    game.result == nil and Enum.any?(Game.actions(game), fn move ->
      next = Game.apply_action(game, move)
      next.result != nil and next.result.winner == game.turn
    end)
  end

  # When threatened, a safe candidate must not be pushed out by positional scores.
  # Keep verified safe moves only, so a partial search cannot prefer a known loss.
  def defend(game, options, deadline) do
    case options do
      [{_move, 1_000_000} | _] -> options
      _ ->
        if immediate_win?(%{game | turn: 3 - game.turn}) do
          {safe, rest} = Enum.reduce(options, {[], []}, fn {move, _score} = option, {safe, rest} ->
            if not exhausted?(1, deadline) and not immediate_win?(Game.apply_action(game, move)) do
              {safe ++ [option], rest}
            else
              {safe, rest ++ [option]}
            end
          end)
          if safe == [], do: rest, else: safe
        else
          options
        end
    end
  end

  # Reverse Dijkstra ignores occupants and estimates the terrain cost to exit.
  # This fixed 100-cell field is computed once per side, then reused throughout search.
  def terrain(board, forests \\ []) do
    Map.new([1, 2], fn player ->
      frontier = for col <- 0..9, do: {1, Game.last_row(player), col}
      distances = Map.new(frontier, fn {cost, row, col} -> {{row, col}, cost} end)
      {player, terrain_walk(board, frontier, distances, forests)}
    end)
  end

  def terrain_walk(_board, [], distances, _forests), do: distances
  def terrain_walk(board, frontier, distances, forests) do
    [{cost, row, col} | rest] = Enum.sort(frontier)
    if cost > Map.fetch!(distances, {row, col}) do
      terrain_walk(board, rest, distances, forests)
    else
      {frontier, distances} = Enum.reduce(Game.neighbours(row, col), {rest, distances}, fn {r, c}, {queue, known} ->
        if Game.inside?(r, c) do
          next = cost + 1 + abs(Game.height(board, row, col) - Game.height(board, r, c)) +
            if(Enum.any?(forests, &(&1.row == row and &1.col == col)), do: 2, else: 0)
          if next < Map.get(known, {r, c}, 1_000), do: {[{next, r, c} | queue], Map.put(known, {r, c}, next)}, else: {queue, known}
        else
          {queue, known}
        end
      end)
      terrain_walk(board, frontier, distances, forests)
    end
  end

  # Beam width, depth, node budget and a monotonic deadline all bound the search.
  def search(game, depth, player, budget, nodes, deadline, alpha, beta) do
    if depth == 0 or game.result != nil or exhausted?(nodes, deadline) do
      {evaluate(game, player, budget.terrain), nodes}
    else
      maximizing = game.turn == player
      choices = ranked(game, game.turn, budget.terrain) |> Enum.take(budget.width)
      if choices == [] do
        {evaluate(game, player, budget.terrain), nodes}
      else
        initial = if maximizing, do: -2_000_000, else: 2_000_000
        {value, left, _alpha, _beta} = Enum.reduce_while(choices, {initial, nodes, alpha, beta}, fn {move, _estimate}, {best, left, a, b} ->
          if exhausted?(left, deadline) do
            {:halt, {if(best == initial, do: evaluate(game, player, budget.terrain), else: best), left, a, b}}
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
  def evaluate(game, player), do: evaluate(game, player, terrain(game.board, Map.get(game, :forests, [])))
  def evaluate(%{result: %{winner: winner}}, player, _terrain) do
    cond do winner == player -> 1_000_000; winner == 0 -> 0; true -> -1_000_000 end
  end
  def evaluate(game, player, terrain) do
    [a, b] = game.scores
    score = if player == 1, do: a - b, else: b - a
    score * 500 + Enum.reduce(Game.active(game), 0, fn piece, sum ->
      progress = 9 - abs(piece.row - Game.last_row(piece.player))
      neighbours = Game.neighbours(piece.row, piece.col) |> Enum.map(fn {r, c} -> Game.occupant(game, r, c) end) |> Enum.reject(&is_nil/1)
      support = Enum.count(neighbours, &(&1.player == piece.player))
      threats = Enum.count(neighbours, fn enemy -> enemy.player != piece.player and Game.combat(game, enemy, piece, 1).attack >= Game.combat(game, enemy, piece, 1).defence end)
      remaining = terrain |> Map.fetch!(piece.player) |> Map.fetch!({piece.row, piece.col})
      travel = round(remaining / piece.movement * 45)
      sentinel = if piece.type == "sentinel" and game.exited == [], do: progress * 7, else: 0
      value = piece.strength * 65 + progress * (12 + piece.strength * 2) + sentinel + support * 9 - threats * (35 + piece.strength * 15) - travel
      sum + if(piece.player == player, do: value, else: -value)
    end)
  end
end
