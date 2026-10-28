defmodule GameSimulator.Traversal.Bot do
  @moduledoc "Deterministic bounded search. No model, network call, randomness or extra dependency."
  alias GameSimulator.Traversal.Game

  def limits("easy"), do: %{depth: 1, width: 1, nodes: 0, milliseconds: 0}
  def limits("medium"), do: %{depth: 2, width: 12, nodes: 500, milliseconds: 800}
  def limits("hard"), do: %{depth: 3, width: 18, reply_width: 7, nodes: 2500, milliseconds: 2450}

  # Keep the simple API for existing callers. The session records the exact trace
  # returned by the same search that selected the action.
  def choose(game, difficulty), do: elem(choose_with_trace(game, difficulty), 0)

  def choose_with_trace(game, difficulty) do
    started = System.monotonic_time(:millisecond)
    budget = limits(difficulty)
    fields = terrain(game.board, Map.get(game, :forests, []), game)
    fields = if difficulty == "easy", do: fields,
      else: Map.put(fields, :interceptions,
        interceptions(game, fields, if(difficulty == "hard", do: :hard, else: :regular)))
    fields = Map.put(fields, :tactical, difficulty == "hard")
    budget = Map.put(budget, :terrain, fields)
    deadline = started + budget.milliseconds
    ranked_options = ranked(game, game.turn, fields)
    static_scores = Map.new(ranked_options)
    medium_alerts = if difficulty == "medium", do: tactical_alerts(game), else: []
    options = if difficulty == "easy", do: ranked_options,
      else: defend(game, improve_candidates(ranked_options, game, budget.width, deadline), deadline)
    options = if medium_alerts == [], do: options,
      else: protect_threatened_pieces(game, options, medium_alerts, deadline)
    depth_limit = if difficulty == "medium" and medium_alerts != [], do: 3, else: budget.depth

    case options do
      [] -> {nil, nil}
      [{fallback, _} | _] ->
        candidates = if difficulty == "hard",
          do: strategic_candidates(game, options, budget.width),
          else: Enum.take(options, budget.width)
        initial = {fallback, 1, [], nil, budget.nodes, "preselection"}
        {chosen, depth, scored, last_attempt, remaining, stop} =
          if difficulty == "easy" do
            initial
          else
            # Do not replace a fully validated depth with an incomplete iteration.
            Enum.reduce_while(2..depth_limit, initial, fn level, {previous, previous_depth, previous_scores, _, nodes, _} ->
              # Medium explores a third ply only for concrete tactical alarms.
              # Six root choices with a five-wide reply search stay within its
              # existing 500-node / 800-ms limits. A partial pass is discarded.
              tactical_pass = difficulty == "medium" and level == 3
              scoped = if tactical_pass, do: medium_extension_choices(candidates, previous_scores), else: candidates
              search_budget = if tactical_pass, do: %{budget | width: 5}, else: budget
              {best, results, left, complete, win} = search_roots(game, scoped, level, search_budget, nodes, deadline)
              attempt = %{depth: level, checked: Enum.count(results, &(&1.searched != nil)), total: length(scoped)}
              if complete do
                {:cont, {best, level, results, attempt, left, if(win, do: "proven_win", else: "complete")}}
              else
                {:halt, {previous, previous_depth, previous_scores, attempt, left, "budget"}}
              end
            end)
          end

        # Report the best actual root comparisons, ALWAYS including the chosen
        # move even if it was not in the first five by searched score.
        entries = if scored == [] do
          Enum.map(Enum.take(candidates, 5), fn {move, adjusted} ->
            %{move: move, adjusted: adjusted, searched: nil, nodes: 0, pv: []}
          end)
        else
          Enum.sort_by(scored, fn item ->
            {-item.searched, item.move.piece, item.move.row, item.move.col}
          end) |> Enum.take(5)
        end
        chosen_entry = Enum.find(scored, &(&1.move == chosen))
        entries = if Enum.any?(entries, &(&1.move == chosen)), do: entries,
          else: entries ++ [chosen_entry || %{
            move: chosen, adjusted: elem(Enum.find(candidates, fn {move, _} -> move == chosen end), 1),
            searched: nil, nodes: 0, pv: []
          }]
        entries = Enum.map(entries, fn entry ->
          Map.put(entry, :static, Map.fetch!(static_scores, entry.move))
        end)
        score = if chosen_entry, do: chosen_entry.searched, else: Map.fetch!(static_scores, chosen)
        trace = %{
          chosen: chosen, score: score, depth: depth, limit_depth: depth_limit,
          tactical: medium_alerts != [], tactical_alerts: medium_alerts,
          mode: if(depth == 1, do: "preselection", else: "search"),
          stop: stop, interrupted: if(stop == "budget", do: Map.put(last_attempt, :reason, if(remaining <= 0, do: "nodes", else: "time")), else: nil),
          root_legal: length(ranked_options), root_filtered: length(options), root_considered: length(candidates),
          root_checked: length(scored), nodes_used: budget.nodes - remaining,
          nodes_limit: budget.nodes, elapsed_ms: System.monotonic_time(:millisecond) - started,
          time_limit_ms: budget.milliseconds, candidates: entries
        }
        {chosen, trace}
    end
  end

  defp search_roots(game, candidates, depth, budget, nodes, deadline) do
    {best, _score, left, entries, complete, win} =
      Enum.reduce_while(candidates, {nil, -2_000_000, nodes, [], true, false}, fn {move, adjusted}, {best, score, left, entries, _, _} ->
        if exhausted?(left, deadline) do
          {:halt, {best, score, left, entries, false, false}}
        else
          # Reuse the best root value as alpha, so inferior alternatives can be
          # pruned during the opponent's reply search.
          root_alpha = if best == nil, do: -2_000_000, else: score
          {value, remaining, line} =
            search_line(Game.apply_action(game, move), depth - 1, game.turn, budget, left - 1, deadline, root_alpha, 2_000_000)
          valid = not exhausted?(remaining, deadline)
          entry = %{
            move: move, adjusted: adjusted, searched: if(valid, do: value, else: nil),
            nodes: left - remaining, pv: if(valid, do: [move | line], else: [])
          }
          entries = [entry | entries]
          cond do
            not valid -> {:halt, {best, score, remaining, entries, false, false}}
            value == 1_000_000 -> {:halt, {move, value, remaining, entries, true, true}}
            value > score -> {:cont, {move, value, remaining, entries, true, false}}
            true -> {:cont, {best, score, remaining, entries, true, false}}
          end
        end
      end)
    {best, Enum.reverse(entries), left, complete, win}
  end

  # Tactical alarm based on legal opponent moves, rather than distance alone.
  # Attacks against our Vanguard/Sentinel and an opponent close to a decisive
  # exit warrant a deeper search; harmless opening moves retain depth two.
  def tactical_alerts(game) do
    opponent = 3 - game.turn
    attacks = Game.actions(%{game | turn: opponent})
      |> Enum.filter(&(&1.kind == "attack"))
      |> Enum.map(fn action -> Game.occupant(game, action.row, action.col) end)
      |> Enum.filter(&(&1 != nil and &1.player == game.turn and &1.strength >= 2))
      |> Enum.map(& &1.id)
      |> Enum.uniq()

    imminent_exit = Game.active(game)
      |> Enum.any?(fn piece ->
        piece.player == opponent and game.exited != [] and
          abs(piece.row - Game.last_row(opponent, game)) <=
            (if piece.type == "explorer", do: 3, else: 2)
      end)
    if imminent_exit, do: ["exit" | attacks], else: attacks
  end

  # Only candidate ordering changes here, never the score used by minimax.
  # Preserve moves that prevent a *real*, legal capture of a valuable piece
  # even when their positional score is below the regular beam cutoff.
  defp protect_threatened_pieces(_game, options, ["exit"], _deadline), do: options
  defp protect_threatened_pieces(game, options, alerts, deadline) do
    victims = Enum.filter(Game.active(game), &(&1.id in alerts))
    if victims == [] or match?([{_, 1_000_000} | _], options) do
      options
    else
      {head, tail} = Enum.split(options, 28)
      scored = Enum.map(head, fn {move, adjusted} = entry ->
        if exhausted?(1, deadline) do
          {entry, 0}
        else
          next = Game.apply_action(game, move)
          saved = Enum.reduce(victims, 0, fn victim, total ->
            target = Enum.find(next.pieces, &(&1.id == victim.id))
            if target.status == "active" and not capturable_next?(next, target) do
              total + target.strength
            else
              total
            end
          end)
          {{move, adjusted}, saved}
        end
      end)
      prioritized = Enum.sort_by(scored, fn {{move, adjusted}, saved} ->
        {-saved, -adjusted, move.piece, move.row, move.col}
      end) |> Enum.map(&elem(&1, 0))
      prioritized ++ tail
    end
  end

  defp capturable_next?(game, target) do
    Game.active(game)
    |> Enum.filter(fn attacker ->
      attacker.player == game.turn and
        abs(attacker.row - target.row) + abs(attacker.col - target.col) <= attacker.movement + 1
    end)
    |> Enum.any?(fn attacker ->
      Game.legal(game, attacker.id)
      |> Enum.any?(&(&1.kind == "attack" and &1.row == target.row and &1.col == target.col))
    end)
  end

  # The depth-two winner and highest scored alternatives stay in the deeper
  # set, together with defensive moves promoted by the tactical presort.
  defp medium_extension_choices(candidates, scored) do
    scored_first = Enum.sort_by(scored, fn entry ->
      {-entry.searched, entry.move.piece, entry.move.row, entry.move.col}
    end) |> Enum.take(4)
    ids = Enum.map(scored_first, & &1.move)
    prioritized = Enum.take(candidates, 2) |> Enum.map(&elem(&1, 0))
    Enum.uniq(prioritized ++ ids)
    |> Enum.take(6)
    |> Enum.map(fn move -> Enum.find(candidates, &(elem(&1, 0) == move)) end)
  end

  # Hard-only root selection: positional ranking alone can discard the move
  # that blocks a fast Sentinel on the opposite flank. Reserve up to four
  # candidates for legal defensive development, while still comparing them in
  # the same minimax search. This is only ordering, not a forced move.
  def strategic_candidates(game, options, width) do
    runners = Game.active(game)
      |> Enum.filter(fn piece ->
        piece.player != game.turn and piece.type == "sentinel" and
          abs(piece.row - Game.last_row(piece.player, game)) <= 8
      end)

    # An Explorer already at the end of the board is a more immediate
    # tactical emergency than a still-distant Sentinel. Do not let the
    # Sentinel reserve displace those legal Explorer interception options.
    explorer_alarm = Enum.any?(Game.active(game), fn piece ->
      piece.player != game.turn and piece.type == "explorer" and
        abs(piece.row - Game.last_row(piece.player, game)) <= 4
    end)
    if runners == [] or explorer_alarm do
      Enum.take(options, width)
    else
      defenders = Map.new(Game.active(game), &{&1.id, &1})
      tactical = options
        |> Enum.map(fn {move, adjusted} = entry ->
          defender = Map.fetch!(defenders, move.piece)
          priority = if defender.strength < 2 do
            0
          else
            # Apply the candidate first: only this state has the correct bridge
            # phase and occupancy for the opponent's upcoming move.
            next = Game.apply_action(game, move)
            Enum.reduce(runners, 0, fn runner, highest ->
              remaining_runner = Enum.find(Game.active(next), &(&1.id == runner.id))
              value = cond do
                remaining_runner == nil -> 10_000
                next.result != nil -> 0
                move.kind != "move" -> 0
                true ->
                  targets = Game.legal(next, runner.id)
                    |> Enum.filter(&(&1.kind == "move"))
                    |> Enum.sort_by(fn action ->
                      {abs(action.row - Game.last_row(runner.player, next)),
                       abs(action.col - runner.col)}
                    end)
                    |> Enum.take(6)
                    |> Enum.map(&{&1.row, &1.col})
                  targets = [{runner.row, runner.col} | targets]
                  from = targets |> Enum.map(fn {r, c} ->
                    abs(defender.row - r) + abs(defender.col - c)
                  end) |> Enum.min()
                  to = targets |> Enum.map(fn {r, c} ->
                    abs(move.row - r) + abs(move.col - c)
                  end) |> Enum.min()
                  improvement = from - to
                  if improvement > 0 and to <= defender.movement + 2,
                    do: 100 + improvement * 30 - to * 4, else: 0
              end
              max(highest, value)
            end)
          end
          {entry, priority, adjusted}
        end)
        |> Enum.filter(fn {_, priority, _} -> priority > 0 end)
        |> Enum.sort_by(fn {{move, _}, priority, adjusted} ->
          {-priority, -adjusted, move.piece, move.row, move.col}
        end)
        |> Enum.take(min(4, width))
        |> Enum.map(&elem(&1, 0))
      # Keep the high-ranking strategic choices, then fill the reserved slots.
      positional = Enum.take(options, width - length(tactical))
      selected = Enum.uniq_by(positional ++ tactical, &elem(&1, 0))
      selected_ids = MapSet.new(Enum.map(selected, &elem(&1, 0)))
      selected ++ (options
        |> Enum.reject(fn {move, _} -> MapSet.member?(selected_ids, move) end)
        |> Enum.take(width - length(selected)))
    end
  end

  # Only re-evaluate the promising root choices to preserve the response budget.
  # Captures are checked with the real movement and combat rules.
  def improve_candidates(options, game, width, deadline) do
    {head, tail} = Enum.split(options, max(width * 2, 24))
    rescored = Enum.map(head, fn {move, value} ->
      next = Game.apply_action(game, move)
      moved = Enum.find(next.pieces, &(&1.id == move.piece))
      exposed = if next.result == nil and moved.status == "active" and
        not exhausted?(1, deadline) do
        Enum.any?(Game.actions(next), fn reply ->
          reply.kind == "attack" and reply.row == moved.row and reply.col == moved.col
        end)
      else
        false
      end
      capture_penalty = if exposed, do: 280 + moved.strength * 160, else: 0
      # A two-ply reversal returns to the board before the previous own move.
      repeated = Enum.at(game.history, -2) == Game.position(next)
      reversal_penalty = if repeated, do: 260, else: 0
      {move, value - capture_penalty - reversal_penalty}
    end)
    Enum.sort_by(rescored ++ tail, fn {move, value} ->
      {-value, move.piece, move.row, move.col}
    end)
  end

  def evaluation_components(%{result: result}, player, _fields) when not is_nil(result),
    do: %{terminal: if(result.winner == player, do: 1_000_000, else: if(result.winner == 0, do: 0, else: -1_000_000))}
  def evaluation_components(game, player, fields) do
    material = Enum.reduce(Game.active(game), 0, fn p, sum ->
      sign = if p.player == player, do: 1, else: -1
      sum + sign * p.strength * 65
    end)
    progress = Enum.reduce(Game.active(game), 0, fn p, sum ->
      sign = if p.player == player, do: 1, else: -1
      advance = length(game.board) - 1 - abs(p.row - Game.last_row(p.player, game))
      sum + sign * advance * (12 + p.strength * 2)
    end)
    [a, b] = game.scores
    %{material: material, progress: progress,
      exits: (if player == 1, do: a - b, else: b - a) * 500,
      interception: interception_score(game, player, fields),
      other: evaluate(game, player, fields) - material - progress -
        (if player == 1, do: a - b, else: b - a) * 500 - interception_score(game, player, fields)}
  end

  def exhausted?(nodes, deadline), do: nodes <= 0 or System.monotonic_time(:millisecond) >= deadline

  def ranked(game, player), do: ranked(game, player, terrain(game.board, Map.get(game, :forests, []), game))
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

  # Reverse Dijkstra ignores occupants. Keep both bridge states because the
  # bridge can change while the same distance fields are reused during search.
  def terrain(board, forests \\ [], game \\ nil) do
    fields = terrain_fields(board, forests, game)
    if game != nil and Game.bridge?(game) do
      other = terrain_fields(board, forests, %{game | bridge_open: not game.bridge_open})
      Map.put(fields, :bridge_fields, %{game.bridge_open => fields, (not game.bridge_open) => other})
    else
      fields
    end
  end

  def terrain_fields(board, forests, game) do
    Map.new([1, 2], fn player ->
      frontier = for col <- 0..(length(board) - 1), do: {1, if(player == 1, do: 0, else: length(board) - 1), col}
      distances = Map.new(frontier, fn {cost, row, col} -> {{row, col}, cost} end)
      {player, terrain_walk(board, frontier, distances, forests, game)}
    end)
  end

  def terrain_for(game, terrain, player) do
    case Map.get(terrain, :bridge_fields) do
      nil -> Map.fetch!(terrain, player)
      fields -> fields |> Map.fetch!(game.bridge_open) |> Map.fetch!(player)
    end
  end

  def terrain_walk(_board, [], distances, _forests, _game), do: distances
  def terrain_walk(board, frontier, distances, forests, game) do
    [{cost, row, col} | rest] = Enum.sort(frontier)
    if cost > Map.fetch!(distances, {row, col}) do
      terrain_walk(board, rest, distances, forests, game)
    else
      {frontier, distances} = Enum.reduce(Game.neighbours(row, col), {rest, distances}, fn {r, c}, {queue, known} ->
        if Game.inside?(r, c, length(board)) and (game == nil or Game.crossing?(game, row, col, r, c)) do
          next = cost + 1 + abs(Game.height(board, row, col) - Game.height(board, r, c)) +
            if(Enum.any?(forests, &(&1.row == row and &1.col == col)), do: 2, else: 0)
          if next < Map.get(known, {r, c}, 1_000), do: {[{next, r, c} | queue], Map.put(known, {r, c}, next)}, else: {queue, known}
        else
          {queue, known}
        end
      end)
      terrain_walk(board, frontier, distances, forests, game)
    end
  end

  # Project each incoming Sentinel along legal fastest advances. The reply fields
  # count whole legal turns until a real capture, including blockers and forests.
  # They are built once at the root; search reuses them as a positional estimate.
  def interceptions(game, terrain), do: interceptions(game, terrain, :regular)
  defp interceptions(game, terrain, mode) do
    if game.result != nil do
      []
    else
      Game.active(game)
      |> Enum.filter(&(&1.player != game.turn and &1.type == "sentinel" and abs(&1.row - Game.last_row(&1.player, game)) <= 6))
      |> Enum.map(fn runner ->
        route = rush_route(game, runner.id, terrain, 0, [])
        defenders = if mode == :regular do
          # Preserve Medium's established threat model exactly.
          Game.active(game) |> Enum.filter(&(&1.player == game.turn))
            |> Enum.sort_by(fn piece -> {-piece.strength, abs(piece.row - runner.row) + abs(piece.col - runner.col), piece.id} end)
            |> Enum.take(2)
        else
          capable = Game.active(game)
            |> Enum.filter(&(&1.player == game.turn and &1.strength >= 2))
          sentinel = capable
            |> Enum.filter(&(&1.type == "sentinel"))
            |> Enum.min_by(fn piece ->
              {abs(piece.row - runner.row) + abs(piece.col - runner.col), piece.id}
            end, fn -> nil end)
          nearest = capable
            |> Enum.reject(&(&1.id == if(sentinel, do: sentinel.id, else: nil)))
            |> Enum.min_by(fn piece ->
              {div(abs(piece.row - runner.row) + abs(piece.col - runner.col) + piece.movement - 1, piece.movement),
               -piece.strength, piece.id}
            end, fn -> nil end)
          Enum.reject([sentinel, nearest], &is_nil/1)
        end
        fields = for {position, turn} <- route, defender <- defenders do
          {defender.id, turn, capture_distances(position, defender.id, runner.id)}
        end
        %{runner: runner.id, player: game.turn, fields: fields}
      end)
    end
  end

  def rush_route(_game, _id, _terrain, 4, route), do: Enum.reverse(route)
  def rush_route(game, id, terrain, turn, route) do
    runner = Enum.find(Game.active(game), &(&1.id == id))
    if runner == nil or game.result != nil do
      Enum.reverse(route)
    else
      route = [{game, turn} | route]
      distances = terrain_for(game, terrain, runner.player)
      moves = Game.legal(%{game | turn: runner.player}, id)
      # Keep the current lane on equal terrain costs; captures remain legal paths.
      move = Enum.min_by(moves, fn move ->
        remaining = if move.kind == "exit", do: 0, else: Map.get(distances, {move.row, move.col}, 1_000)
        {remaining, abs(move.col - runner.col), move.row, move.col}
      end, fn -> nil end)
      if move == nil or move.kind == "exit" do
        Enum.reverse(route)
      else
        rush_route(Game.apply_action(%{game | turn: runner.player}, move), id, terrain, turn + 1, route)
      end
    end
  end

  def capture_distances(game, defender_id, runner_id) do
    defender = Enum.find(Game.active(game), &(&1.id == defender_id))
    runner = Enum.find(Game.active(game), &(&1.id == runner_id))
    {edges, captures} = Enum.reduce(for(r <- 0..(length(game.board) - 1), c <- 0..(length(game.board) - 1), do: {r, c}), {%{}, %{}}, fn {r, c} = origin, {edges, captures} ->
      occupied = Game.occupant(game, r, c)
      if defender == nil or runner == nil or (occupied != nil and occupied.id != defender_id) do
        {edges, captures}
      else
        pieces = Enum.map(game.pieces, fn piece -> if piece.id == defender_id, do: %{piece | row: r, col: c}, else: piece end)
        moves = Game.legal(%{game | pieces: pieces, turn: defender.player}, defender_id)
        Enum.reduce(moves, {edges, captures}, fn move, {edges, captures} ->
          cond do
            move.kind == "attack" and move.row == runner.row and move.col == runner.col -> {edges, Map.put(captures, origin, 1)}
            move.kind == "move" -> {Map.update(edges, {move.row, move.col}, [origin], &[origin | &1]), captures}
            true -> {edges, captures}
          end
        end)
      end
    end)
    capture_walk(edges, Map.keys(captures), captures, 1)
  end

  def capture_walk(_edges, [], distances, _turn), do: distances
  def capture_walk(_edges, _frontier, distances, 5), do: distances
  def capture_walk(edges, frontier, distances, turn) do
    {next, distances} = Enum.reduce(frontier, {[], distances}, fn cell, acc ->
      Enum.reduce(Map.get(edges, cell, []), acc, fn origin, {next, distances} ->
        if Map.has_key?(distances, origin), do: {next, distances}, else: {[origin | next], Map.put(distances, origin, turn + 1)}
      end)
    end)
    capture_walk(edges, next, distances, turn + 1)
  end

  def interception_score(game, player, terrain) do
    Enum.reduce(Map.get(terrain, :interceptions, []), 0, fn threat, sum ->
      runner = Enum.find(Game.active(game), &(&1.id == threat.runner))
      if runner == nil do
        sum
      else
        margin = Enum.map(threat.fields, fn {id, turn, distances} ->
          defender = Enum.find(Game.active(game), &(&1.id == id))
          if defender == nil, do: 10, else: Map.get(distances, {defender.row, defender.col}, 10) - turn
        end) |> Enum.min(fn -> 10 end)
        value = -max(0, margin) * 350 - min(0, margin) * 20
        sum + if(threat.player == player, do: value, else: -value)
      end
    end)
  end

  # Preserve the public search/8 return shape while collecting the actual
  # principal line inside the search used by choose_with_trace/2.
  def search(game, depth, player, budget, nodes, deadline, alpha, beta) do
    {value, left, _line} = search_line(game, depth, player, budget, nodes, deadline, alpha, beta)
    {value, left}
  end

  # This mirrors the original alpha-beta control flow: collecting its best
  # branch does not alter cutoffs, budget checks, or the selected numeric score.
  # Only fully completed root searches are retained by choose_with_trace/2.
  defp search_line(game, depth, player, budget, nodes, deadline, alpha, beta) do
    if depth == 0 or game.result != nil or exhausted?(nodes, deadline) do
      {evaluate(game, player, budget.terrain), nodes, []}
    else
      maximizing = game.turn == player
      reply_width = Map.get(budget, :reply_width, budget.width)
      # At ANY depth the opponent must be allowed its full reply beam.
      # Selective pruning of opponent replies hides low-static tactical sprints
      # and breaks minimax's worst-case guarantee. Narrow our own moves only.
      width = if game.turn != player, do: budget.width, else: reply_width
      choices = ranked(game, game.turn, budget.terrain) |> Enum.take(width)
      if choices == [] do
        {evaluate(game, player, budget.terrain), nodes, []}
      else
        initial = if maximizing, do: -2_000_000, else: 2_000_000
        {value, left, _alpha, _beta, line} =
          Enum.reduce_while(choices, {initial, nodes, alpha, beta, []}, fn {move, _estimate}, {best, left, a, b, line} ->
            if exhausted?(left, deadline) do
              {:halt, {if(best == initial, do: evaluate(game, player, budget.terrain), else: best), left, a, b, line}}
            else
              {value, remaining, child_line} =
                search_line(Game.apply_action(game, move), depth - 1, player, budget, left - 1, deadline, a, b)
              better = if maximizing, do: value > best, else: value < best
              best = if maximizing, do: max(best, value), else: min(best, value)
              line = if better, do: [move | child_line], else: line
              a = if maximizing, do: max(a, best), else: a
              b = if maximizing, do: b, else: min(b, best)
              if a >= b, do: {:halt, {best, remaining, a, b, line}}, else: {:cont, {best, remaining, a, b, line}}
            end
          end)
        {value, left, line}
      end
    end
  end

  # Resolve imminent exits with the official legal-move and combat rules.
  # This is a selective one-ply tactical extension at evaluation leaves: it is
  # only activated for units close enough to leave on their NEXT turn. This
  # catches Explorer threats that a depth-two horizon would otherwise miss.
  #
  # A looming second exit (or first Sentinel exit) is decisive only if the
  # defender cannot capture the runner or win immediately on its own move.
  defp exit_threat_score(game, player) do
    game
    |> Game.active()
    |> Enum.reduce(0, fn runner, sum ->
      steps = abs(runner.row - Game.last_row(runner.player, game))
      # Four ranks is sufficient to include a five-PM Explorer's final sprint;
      # the authoritative exit test below handles relief, forests and blockers.
      if steps > 4 or runner.player == player do
        sum
      else
        can_exit = %{game | turn: runner.player}
          |> Game.legal(runner.id)
          |> Enum.any?(&(&1.kind == "exit"))

        if not can_exit do
          sum
        else
          value = exit_value(game, runner)

          # Capturing the runner this turn is a real legal defence, so score
          # the threat less urgently. Without this check the bot avoids useful
          # interception squares (e.g. Vanguard I2 against an Explorer at J1).
          countered = game.turn != runner.player and
            counter_exit?(game, runner)

          urgency = if countered, do: div(value, 12), else: value
          sum - urgency
        end
      end
    end)
  end

  # Exit outcome only depends on the already exited units and the runner's
  # strength/type, not on the exit square. Avoid creating simulated histories
  # for every static evaluation in the search tree.
  defp exit_value(game, runner) do
    case game.exited do
      [] -> if runner.type == "sentinel", do: 900_000, else: 1_100
      _ ->
        own = Enum.at(game.scores, runner.player - 1)
        opponent = Enum.at(game.scores, 2 - runner.player)
        if own + runner.strength > opponent, do: 900_000, else: 0
    end
  end

  defp counter_exit?(game, runner) do
    # Check the defender's immediate winning exit and legal attacks. Only
    # nearby attackers need full pathfinding, which keeps leaf checks bounded.
    Game.active(game)
    |> Enum.filter(&(&1.player == game.turn))
    |> Enum.any?(fn defender ->
      distance = abs(defender.row - runner.row) + abs(defender.col - runner.col)
      if distance > defender.movement + 1 and
        abs(defender.row - Game.last_row(defender.player, game)) > defender.movement do
        false
      else
        Game.legal(game, defender.id)
        |> Enum.any?(fn reply ->
          cond do
            reply.kind == "attack" -> reply.row == runner.row and reply.col == runner.col
            reply.kind == "exit" -> exit_value(game, defender) == 900_000
            true -> false
          end
        end)
      end
    end)
  end

  # Terminal outcomes dominate every positional term, including a first Sentinel exit.
  def evaluate(game, player), do: evaluate(game, player, terrain(game.board, Map.get(game, :forests, []), game))
  def evaluate(%{result: %{winner: winner}}, player, _terrain) do
    cond do winner == player -> 1_000_000; winner == 0 -> 0; true -> -1_000_000 end
  end
  def evaluate(game, player, terrain) do
    [a, b] = game.scores
    score = if player == 1, do: a - b, else: b - a
    tactical = if Map.get(terrain, :tactical, true), do: exit_threat_score(game, player), else: 0
    interception_score(game, player, terrain) + tactical + score * 500 + Enum.reduce(Game.active(game), 0, fn piece, sum ->
      progress = length(game.board) - 1 - abs(piece.row - Game.last_row(piece.player, game))
      neighbours = Game.neighbours(piece.row, piece.col) |> Enum.map(fn {r, c} -> Game.occupant(game, r, c) end) |> Enum.reject(&is_nil/1)
      support = Enum.count(neighbours, &(&1.player == piece.player))
      threats = Enum.count(neighbours, fn enemy -> enemy.player != piece.player and enemy.type != "cannon" and Game.combat(game, enemy, piece, 1).attack >= Game.combat(game, enemy, piece, 1).defence end)
      threats = threats + Enum.count(Game.active(game), fn enemy ->
        enemy.player != piece.player and enemy.type == "cannon" and
          Enum.any?(Game.cannon_actions(game, enemy), &(&1.row == piece.row and &1.col == piece.col))
      end)
      distances = terrain_for(game, terrain, piece.player)
      remaining = Map.get(distances, {piece.row, piece.col}, length(game.board) * 10)
      travel = round(remaining / piece.movement * 45)
      sentinel = if piece.type == "sentinel" and game.exited == [] do
        urgency = cond do
          remaining <= piece.movement -> 450
          remaining <= piece.movement * 2 -> 260
          remaining <= piece.movement * 4 -> 90
          true -> 0
        end
        progress * 7 + urgency
      else
        0
      end
      value = piece.strength * 65 + progress * (12 + piece.strength * 2) + sentinel + support * 9 - threats * (35 + piece.strength * 15) - travel
      sum + if(piece.player == player, do: value, else: -value)
    end)
  end
end
