defmodule GameSimulator.Traversal.Game do
  @moduledoc "Authoritative Traversal rules; coordinates are zero-based, player 1 starts on row 9."
  @types ["sentinel", "vanguard", "explorer", "explorer", "vanguard", "sentinel"]

  def stats("explorer"), do: %{movement: 5, strength: 1}
  def stats("vanguard"), do: %{movement: 4, strength: 2}
  def stats("sentinel"), do: %{movement: 3, strength: 3}

  def valid_board?(board) when is_list(board) and length(board) == 10 do
    Enum.all?(board, &(is_list(&1) and length(&1) == 10 and Enum.all?(&1, fn h -> is_integer(h) and h in 0..5 end))) and
      Enum.all?(for(r <- 0..9, c <- 0..9, do: {r, c}), fn {r, c} ->
        h = height(board, r, c)
        h == height(board, 9 - r, 9 - c) and
          Enum.all?(for(dr <- -1..1, dc <- -1..1, inside?(r + dr, c + dc), do: {r + dr, c + dc}), fn {nr, nc} -> abs(h - height(board, nr, nc)) <= 2 end)
      end)
  end
  def valid_board?(_board), do: false

  def new(board) do
    pieces = for player <- [1, 2], {type, index} <- Enum.with_index(@types) do
      Map.merge(stats(type), %{id: "#{player}-#{index}", type: type, player: player, row: if(player == 1, do: 9, else: 0), col: index + 2, status: "active"})
    end
    %{board: board, pieces: pieces, turn: 1, moves: 0, exited: [], scores: [0, 0], result: nil, history: []}
  end

  def active(game), do: Enum.filter(game.pieces, &(&1.status == "active"))
  def occupant(game, row, col), do: Enum.find(game.pieces, &(&1.status == "active" and &1.row == row and &1.col == col))
  def height(board, row, col), do: board |> Enum.at(row) |> Enum.at(col)
  def inside?(row, col), do: row in 0..9 and col in 0..9
  def neighbours(row, col), do: [{row - 1, col}, {row + 1, col}, {row, col - 1}, {row, col + 1}]
  def last_row(1), do: 0
  def last_row(2), do: 9
  def exit_row(1), do: -1
  def exit_row(2), do: 10

  # Positive costs and a best-cost table bound the search to at most 100 cells.
  # Occupied cells are destinations only: neither friend nor enemy can be crossed.
  def distances(game, piece) do
    walk(game, piece, [{0, piece.row, piece.col}], %{{piece.row, piece.col} => 0}, %{})
  end

  def walk(_game, _piece, [], empty, enemies), do: {empty, enemies}
  def walk(game, piece, queue, empty, enemies) do
    [{cost, row, col} | rest] = Enum.sort(queue)
    if cost > Map.fetch!(empty, {row, col}) do
      walk(game, piece, rest, empty, enemies)
    else
      {next, empty, enemies} = Enum.reduce(neighbours(row, col), {rest, empty, enemies}, fn {r, c}, {q, cells, attacks} ->
        if inside?(r, c) do
          total = cost + 1 + abs(height(game.board, row, col) - height(game.board, r, c))
          target = occupant(game, r, c)
          cond do
            total > piece.movement -> {q, cells, attacks}
            target != nil and target.player != piece.player -> {q, cells, Map.update(attacks, {r, c}, total, &min(&1, total))}
            target != nil -> {q, cells, attacks}
            total < Map.get(cells, {r, c}, 100) -> {[{total, r, c} | q], Map.put(cells, {r, c}, total), attacks}
            true -> {q, cells, attacks}
          end
        else
          {q, cells, attacks}
        end
      end)
      walk(game, piece, next, empty, enemies)
    end
  end

  def combat(game, piece, target, cost) do
    support = neighbours(target.row, target.col) |> Enum.map(fn {r, c} -> occupant(game, r, c) end) |> Enum.reject(&is_nil/1)
    difference = height(game.board, piece.row, piece.col) - height(game.board, target.row, target.col)
    elevation = cond do difference > 0 -> 1; difference < 0 -> -1; true -> 0 end
    attack = piece.strength + elevation + Enum.reduce(support, 0, fn ally, sum -> if ally.player == piece.player and ally.id != piece.id, do: sum + ally.strength, else: sum end)
    attack = attack + if(piece.type == "vanguard" and cost == 4, do: 1, else: 0)
    defence = target.strength + Enum.count(support, &(&1.player == target.player))
    %{attack: attack, defence: defence}
  end

  def action(piece, row, col, cost, kind, special \\ false), do: %{piece: piece.id, row: row, col: col, cost: cost, kind: kind, special: special}

  def legal(game, id) do
    piece = Enum.find(game.pieces, &(&1.id == id and &1.status == "active" and &1.player == game.turn))
    if game.result != nil or piece == nil do
      []
    else
      {empty, enemies} = distances(game, piece)
      moves = for {{r, c}, cost} <- empty, {r, c} != {piece.row, piece.col}, do: action(piece, r, c, cost, "move")
      attacks = Enum.flat_map(enemies, fn {{r, c}, cost} ->
        strength = combat(game, piece, occupant(game, r, c), cost)
        if strength.attack >= strength.defence, do: [Map.merge(action(piece, r, c, cost, "attack"), strength)], else: []
      end)
      exits = for {{r, c}, cost} <- empty, r == last_row(piece.player), cost < piece.movement, do: action(piece, exit_row(piece.player), c, cost + 1, "exit")
      specials = if piece.type == "explorer", do: special_actions(game, piece, empty, enemies), else: []
      (moves ++ attacks ++ exits ++ specials) |> Enum.uniq_by(&{&1.row, &1.col}) |> Enum.sort_by(&{&1.row, &1.col})
    end
  end

  def special_actions(game, piece, empty, enemies) do
    Enum.flat_map([{-1, -1}, {-1, 1}, {1, -1}, {1, 1}, {-2, 0}, {2, 0}, {0, -2}, {0, 2}], fn {dr, dc} ->
      r = piece.row + dr
      c = piece.col + dc
      jumping = abs(dr) == 2 or abs(dc) == 2
      middle = {piece.row + div(dr, 2), piece.col + div(dc, 2)}
      blocked = jumping and (not inside?(elem(middle, 0), elem(middle, 1)) or occupant(game, elem(middle, 0), elem(middle, 1)) != nil)
      cond do
        blocked or c not in 0..9 -> []
        r == exit_row(piece.player) or (piece.player == 1 and r == -2) or (piece.player == 2 and r == 11) -> [action(piece, exit_row(piece.player), c, piece.movement, "exit", true)]
        not inside?(r, c) or Map.has_key?(empty, {r, c}) or Map.has_key?(enemies, {r, c}) -> []
        true ->
          target = occupant(game, r, c)
          cond do
            target == nil -> [action(piece, r, c, piece.movement, "move", true)]
            target.player == piece.player -> []
            true ->
              strength = combat(game, piece, target, piece.movement)
              if strength.attack >= strength.defence, do: [Map.merge(action(piece, r, c, piece.movement, "attack", true), strength)], else: []
          end
      end
    end)
  end

  def actions(game), do: active(game) |> Enum.filter(&(&1.player == game.turn)) |> Enum.flat_map(&legal(game, &1.id))

  def play(game, id, row, col) do
    case Enum.find(legal(game, id), &(&1.row == row and &1.col == col)) do
      nil -> {:error, :illegal_move}
      move -> {:ok, apply_action(game, move)}
    end
  end

  def apply_action(game, move) do
    piece = Enum.find(game.pieces, &(&1.id == move.piece))
    target = occupant(game, move.row, move.col)
    pieces = Enum.map(game.pieces, fn p ->
      cond do
        p.id == piece.id -> if move.kind == "exit", do: %{p | status: "exited"}, else: %{p | row: move.row, col: move.col}
        target != nil and p.id == target.id -> %{p | status: "captured"}
        true -> p
      end
    end)
    exited = if move.kind == "exit", do: game.exited ++ [piece.id], else: game.exited
    scores = for player <- [1, 2], do: pieces |> Enum.filter(&(&1.player == player and &1.status == "exited")) |> Enum.map(& &1.strength) |> Enum.sum()
    next = %{game | pieces: pieces, exited: exited, scores: scores, moves: game.moves + 1, turn: 3 - game.turn}
    next = cond do
      move.kind == "exit" and game.exited == [] and piece.type == "sentinel" -> finish(next, piece.player, "first_sentinel")
      length(exited) >= 2 -> finish(next, score_winner(scores), "two_exits")
      Enum.any?([1, 2], fn player -> not Enum.any?(active(next), &(&1.player == player)) end) ->
        bonuses = for player <- [1, 2], do: active(next) |> Enum.filter(&(&1.player == player)) |> Enum.map(& &1.strength) |> Enum.max(fn -> 0 end)
        final_scores = Enum.zip_with(scores, bonuses, &+/2)
        finish(%{next | scores: final_scores}, score_winner(final_scores), "no_active_pieces")
      next.moves >= 200 -> move_limit(next)
      true -> next
    end
    if next.result != nil do
      next
    else
      history = next.history ++ [position(next)]
      next = %{next | history: history}
      if repeated?(history), do: finish(next, 0, "threefold_repetition"), else: next
    end
  end

  def finish(game, winner, reason), do: %{game | result: %{winner: winner, reason: reason}}
  def score_winner([a, b]) when a > b, do: 1
  def score_winner([a, b]) when b > a, do: 2
  def score_winner(_scores), do: 0

  def move_limit(game) do
    winner = score_winner(game.scores)
    if winner != 0 do
      finish(game, winner, "move_limit_score")
    else
      ranks = for player <- [1, 2] do
        active(game) |> Enum.filter(&(&1.player == player)) |> Enum.map(fn p -> {abs(p.row - last_row(player)), -p.strength} end) |> Enum.min(fn -> {100, 0} end)
      end
      [a, b] = ranks
      winner = cond do a < b -> 1; b < a -> 2; true -> 0 end
      finish(game, winner, "move_limit_advancement")
    end
  end

  def position(game) do
    pieces = active(game) |> Enum.map(&{&1.player, &1.type, &1.row, &1.col}) |> Enum.sort()
    {game.turn, pieces, Enum.sort(game.exited)}
  end

  # Repeat a complete even-length sequence three times, as the official runtime does.
  def repeated?(history) when length(history) < 6, do: false
  def repeated?(history) do
    Enum.any?(2..div(length(history), 3)//2, fn period ->
      tail = Enum.take(history, -period * 3)
      [a, b, c] = Enum.chunk_every(tail, period)
      a == b and b == c
    end)
  end
end
