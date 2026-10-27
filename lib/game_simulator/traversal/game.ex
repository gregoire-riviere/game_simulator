defmodule GameSimulator.Traversal.Game do
  @moduledoc "Authoritative Traversal rules; coordinates are zero-based, player 1 starts on row 9."
  @types ["sentinel", "vanguard", "explorer", "explorer", "vanguard", "sentinel"]

  def stats("cannon"), do: %{movement: 2, strength: 2}
  def stats("explorer"), do: %{movement: 5, strength: 1}
  def stats("vanguard"), do: %{movement: 4, strength: 2}
  def stats("sentinel"), do: %{movement: 3, strength: 3}

  def valid_board?(board) when is_list(board) and length(board) in [10, 12] do
    size = length(board)
    Enum.all?(board, &(is_list(&1) and length(&1) == size and Enum.all?(&1, fn h -> is_integer(h) and h in 0..5 end))) and
      Enum.all?(for(r <- 0..(size - 1), c <- 0..(size - 1), do: {r, c}), fn {r, c} ->
        h = height(board, r, c)
        h == height(board, size - 1 - r, size - 1 - c) and
          Enum.all?(for(dr <- -1..1, dc <- -1..1, inside?(r + dr, c + dc, size), do: {r + dr, c + dc}), fn {nr, nc} -> abs(h - height(board, nr, nc)) <= 2 end)
      end)
  end
  def valid_board?(_board), do: false

  def new(board, variant \\ "classic", seed \\ nil) do
    size = length(board)
    types = if size == 12, do: List.insert_at(@types, 3, "cannon"), else: @types
    pieces = for player <- [1, 2], {type, index} <- Enum.with_index(types) do
      col = if size == 12 and player == 2, do: size - 3 - index, else: index + 2
      Map.merge(stats(type), %{id: "#{player}-#{index}", type: type, player: player, row: if(player == 1, do: size - 1, else: 0), col: col, status: "active"})
    end
    %{board: board, variant: variant, forests: GameSimulator.Traversal.Variant.forests(variant, seed, size), bridge_open: true, pieces: pieces, turn: 1, moves: 0, exited: [], scores: [0, 0], result: nil, history: []}
  end

  def bridge?(game), do: "bridge" in String.split(Map.get(game, :variant, "classic"), "+")
  def crossing?(game, r, c, nr, nc, firing \\ false) do
    mid = div(length(game.board), 2)
    across = (r < mid and nr >= mid) or (r >= mid and nr < mid)
    if not bridge?(game) or not across do
      true
    else
      c == nc and (c in [1, length(game.board) - 2] or (c == mid and (firing or game.bridge_open)))
    end
  end

  def next_bridge(game) do
    if bridge?(game) do
      size = length(game.board)
      mid = div(size, 2)
      occupied = occupant(game, mid - 1, mid) != nil or occupant(game, mid, mid) != nil
      %{game | bridge_open: rem(game.moves, 4) < 2 or occupied}
    else
      game
    end
  end

  def forest?(game, row, col), do: Enum.any?(Map.get(game, :forests, []), &(&1.row == row and &1.col == col))

  def active(game), do: Enum.filter(game.pieces, &(&1.status == "active"))
  def occupant(game, row, col), do: Enum.find(game.pieces, &(&1.status == "active" and &1.row == row and &1.col == col))
  def height(board, row, col), do: board |> Enum.at(row) |> Enum.at(col)
  def inside?(row, col), do: inside?(row, col, 10)
  def inside?(row, col, size), do: row >= 0 and col >= 0 and row < size and col < size
  def neighbours(row, col), do: [{row - 1, col}, {row + 1, col}, {row, col - 1}, {row, col + 1}]
  def last_row(1), do: 0
  def last_row(2), do: 9
  def exit_row(1), do: -1
  def exit_row(2), do: 10
  def last_row(player, game), do: if(player == 1, do: 0, else: length(game.board) - 1)
  def exit_row(player, game), do: if(player == 1, do: -1, else: length(game.board))

  # Positive costs and a best-cost table bound the search to at most 100 cells.
  # Occupied cells are destinations only: neither friend nor enemy can be crossed.
  def distances(game, piece) do
    walk(game, piece, [{0, piece.row, piece.col}], %{{piece.row, piece.col} => 0}, %{})
  end

  def walk(_game, _piece, [], empty, enemies), do: {empty, enemies}
  def walk(game, piece, queue, empty, enemies) do
    [{cost, row, col} | rest] = Enum.sort(queue)
    # A forest is a destination, never a walking waypoint. Starting there
    # permits exactly one normal step; positive costs preserve minimal charge cost.
    stopped = cost > 0 and (forest?(game, row, col) or forest?(game, piece.row, piece.col))
    if stopped or cost > Map.fetch!(empty, {row, col}) do
      walk(game, piece, rest, empty, enemies)
    else
      {next, empty, enemies} = Enum.reduce(neighbours(row, col), {rest, empty, enemies}, fn {r, c}, {q, cells, attacks} ->
        if inside?(r, c, length(game.board)) and crossing?(game, row, col, r, c) do
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
      attacks = if piece.type == "cannon", do: cannon_actions(game, piece), else: Enum.flat_map(enemies, fn {{r, c}, cost} ->
        strength = combat(game, piece, occupant(game, r, c), cost)
        if strength.attack >= strength.defence, do: [Map.merge(action(piece, r, c, cost, "attack"), strength)], else: []
      end)
      exits = for {{r, c}, cost} <- empty, r == last_row(piece.player, game), cost < piece.movement,
        (cost == 0 or (not forest?(game, r, c) and not forest?(game, piece.row, piece.col))), do: action(piece, exit_row(piece.player, game), c, cost + 1, "exit")
      specials = if piece.type == "explorer", do: special_actions(game, piece, empty, enemies), else: []
      (moves ++ attacks ++ exits ++ specials) |> Enum.uniq_by(&{&1.row, &1.col}) |> Enum.sort_by(&{&1.row, &1.col})
    end
  end

  def cannon_actions(game, piece) do
    if forest?(game, piece.row, piece.col) do
      []
    else
      Enum.flat_map([{1, 0}, {-1, 0}, {0, 1}, {0, -1}], fn {dr, dc} ->
        Enum.flat_map(2..3, fn distance ->
          r = piece.row + dr * distance
          c = piece.col + dc * distance
          blocked = Enum.any?(1..(distance - 1), fn step -> occupant(game, piece.row + dr * step, piece.col + dc * step) != nil end)
          if inside?(r, c, length(game.board)) and not blocked and crossing?(game, piece.row, piece.col, r, c, true) do
            target = occupant(game, r, c)
            if target != nil and target.player != piece.player and height(game.board, r, c) <= height(game.board, piece.row, piece.col) do
              strength = combat(game, piece, target, distance)
              if strength.attack >= strength.defence, do: [Map.merge(action(piece, r, c, distance, "attack", true), strength)], else: []
            else
              []
            end
          else
            []
          end
        end)
      end)
    end
  end

  def special_actions(game, piece, _empty, _enemies) do
    Enum.flat_map([{-1, -1}, {-1, 1}, {1, -1}, {1, 1}, {-2, 0}, {2, 0}, {0, -2}, {0, 2}], fn {dr, dc} ->
      r = piece.row + dr
      c = piece.col + dc
      jumping = abs(dr) == 2 or abs(dc) == 2
      middle = {piece.row + div(dr, 2), piece.col + div(dc, 2)}
      blocked = jumping and (not inside?(elem(middle, 0), elem(middle, 1), length(game.board)) or occupant(game, elem(middle, 0), elem(middle, 1)) != nil)
      cond do
        blocked or c < 0 or c >= length(game.board) or not crossing?(game, piece.row, piece.col, r, c) -> []
        r == exit_row(piece.player, game) or (piece.player == 1 and r == -2) or (piece.player == 2 and r == length(game.board) + 1) -> [action(piece, exit_row(piece.player, game), c, piece.movement, "exit", true)]
        not inside?(r, c, length(game.board)) -> []
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
        p.id == piece.id -> cond do move.kind == "exit" -> %{p | status: "exited"}; p.type == "cannon" and move.kind == "attack" -> p; true -> %{p | row: move.row, col: move.col} end
        target != nil and p.id == target.id -> %{p | status: "captured"}
        true -> p
      end
    end)
    exited = if move.kind == "exit", do: game.exited ++ [piece.id], else: game.exited
    scores = for player <- [1, 2], do: pieces |> Enum.filter(&(&1.player == player and &1.status == "exited")) |> Enum.map(& &1.strength) |> Enum.sum()
    next = %{game | pieces: pieces, exited: exited, scores: scores, moves: game.moves + 1, turn: 3 - game.turn}
    next = next_bridge(next)
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
        active(game) |> Enum.filter(&(&1.player == player)) |> Enum.map(fn p -> {abs(p.row - last_row(player, game)), -p.strength} end) |> Enum.min(fn -> {100, 0} end)
      end
      [a, b] = ranks
      winner = cond do a < b -> 1; b < a -> 2; true -> 0 end
      finish(game, winner, "move_limit_advancement")
    end
  end

  def position(game) do
    pieces = active(game) |> Enum.map(&{&1.player, &1.type, &1.row, &1.col}) |> Enum.sort()
    if bridge?(game), do: {game.turn, pieces, Enum.sort(game.exited), rem(game.moves, 4), game.bridge_open}, else: {game.turn, pieces, Enum.sort(game.exited)}
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
