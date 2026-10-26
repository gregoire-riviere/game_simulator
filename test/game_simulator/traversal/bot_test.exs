defmodule GameSimulator.Traversal.BotTest do
  use ExUnit.Case, async: true
  alias GameSimulator.Traversal.{Game, Bot}
  def board, do: List.duplicate(List.duplicate(0, 10), 10)
  def piece(type, player, row, col, id), do: Map.merge(Game.stats(type), %{id: id, type: type, player: player, row: row, col: col, status: "active"})
  def game(pieces), do: %{Game.new(board()) | pieces: pieces}

  test "three levels have increasing concrete search depths and bounded work" do
    assert Enum.map(["easy", "medium", "hard"], &Bot.limits(&1).depth) == [1, 2, 3]
    assert Bot.limits("hard").nodes <= 2500
    state = %{Game.new(board()) | turn: 2}
    for difficulty <- ["easy", "medium", "hard"] do
      {elapsed, move} = :timer.tc(fn -> Bot.choose(state, difficulty) end)
      assert move in Game.actions(state)
      assert elapsed < 3_000_000
    end
  end

  test "medium and hard choose a legal response after the opening move" do
    initial = Game.new(board())
    opening = Enum.find(Game.actions(initial), &(&1.piece == "1-0" and &1.row == 7 and &1.col == 2))
    assert opening != nil
    state = Game.apply_action(initial, opening)
    for difficulty <- ["medium", "hard"] do
      assert Bot.choose(state, difficulty) in Game.actions(state)
    end
  end

  test "the bot decision trace is produced by the chosen search, not a replay" do
    state = %{game([
      piece("sentinel", 2, 2, 2, "bot"),
      piece("sentinel", 1, 7, 7, "human")
    ]) | turn: 2}

    for difficulty <- ["easy", "medium", "hard"] do
      {chosen, trace} = Bot.choose_with_trace(state, difficulty)
      assert chosen in Game.actions(state)
      assert trace.chosen == chosen
      assert trace.depth >= 1 and trace.depth <= Bot.limits(difficulty).depth
      assert trace.root_legal >= trace.root_considered
      assert trace.nodes_used >= 0 and trace.nodes_used <= trace.nodes_limit
      assert Enum.any?(trace.candidates, &(&1.move == chosen))
      assert Enum.all?(trace.candidates, fn entry ->
        entry.move in Game.actions(state) and is_number(entry.static) and
          is_number(entry.adjusted) and is_integer(entry.nodes) and is_list(entry.pv)
      end)

      selected = Enum.find(trace.candidates, &(&1.move == chosen))
      if trace.depth > 1 do
        assert trace.mode == "search"
        assert selected.searched == trace.score
        assert hd(selected.pv) == chosen
        assert length(selected.pv) <= trace.depth
        assert trace.root_checked > 0
      else
        assert trace.mode == "preselection"
        assert trace.score == selected.static
      end

      if trace.interrupted do
        assert trace.stop == "budget"
        assert trace.interrupted.depth > trace.depth
        assert trace.interrupted.checked <= trace.interrupted.total
      end
    end
  end

  # A real replay in which two Explorers reached the exit unchallenged.
  # Indexes are 0-based in engine actions, while reports show A1..J10.
  defp explorer_rush_replay(ply) do
    rows = "3344333445/3333333444/4433333444/4432233444/4433233444/4443323344/4443322344/4443333344/4443333333/5443334433"
    heights = rows |> String.split("/") |> Enum.map(fn row ->
      row |> String.graphemes() |> Enum.map(&String.to_integer/1)
    end)
    forests = for square <- ["D7", "D8", "E7", "E8", "F3", "F4", "G3", "G4"] do
      <<column::utf8, row::binary>> = square
      %{row: String.to_integer(row) - 1, col: column - ?A}
    end
    opening = [
      {"1-1", "C8"}, {"2-5", "H4"}, {"1-0", "B8"}, {"2-5", "H6"},
      {"1-2", "F8"}, {"2-5", "H7"}, {"1-2", "F5"}, {"2-0", "C3"},
      {"1-2", "I4"}, {"2-1", "D3"}, {"1-2", :exit}, {"2-2", "D4"},
      {"1-3", "J9"}, {"2-3", "E4"}, {"1-3", "J5"}
    ]

    Enum.reduce(Enum.take(opening, ply), %{Game.new(heights, "forests", "2626996510") | forests: forests}, fn {id, square}, state ->
      action = case square do
        :exit -> Enum.find(Game.legal(state, id), &(&1.kind == "exit"))
        <<column::utf8, row::binary>> ->
          r = String.to_integer(row) - 1
          c = column - ?A
          Enum.find(Game.legal(state, id), &(&1.row == r and &1.col == c))
      end
      assert action != nil, "#{id} -> #{inspect(square)} should be legal at move #{state.moves + 1}"
      Game.apply_action(state, action)
    end)
  end

  defp move_to(game, id, square) do
    <<column::utf8, row::binary>> = square
    action = Enum.find(Game.legal(game, id), &(&1.row == String.to_integer(row) - 1 and &1.col == column - ?A))
    assert action != nil, "#{id} -> #{square} must be legal"
    action
  end

  test "Explorer sprint at ply eight rewards a real interception, not passive development" do
    state = explorer_rush_replay(7)
    assert state.turn == 2
    defended = state |> Game.apply_action(move_to(state, "2-4", "H3"))
    passive = state |> Game.apply_action(move_to(state, "2-0", "C3"))
    arrival_defended = Game.apply_action(defended, move_to(defended, "1-2", "I4"))
    arrival_passive = Game.apply_action(passive, move_to(passive, "1-2", "I4"))
    assert Enum.any?(Game.legal(arrival_defended, "2-4"), fn action ->
      action.kind == "attack" and action.row == 3 and action.col == 8
    end)
    assert Bot.evaluate(arrival_defended, 2) > Bot.evaluate(arrival_passive, 2) + 400
  end

  test "after the first Explorer exit, depth-two horizons must detect the second winning exit" do
    state = explorer_rush_replay(15)
    assert state.turn == 2
    assert state.scores == [1, 0]
    unsafe = Game.apply_action(state, move_to(state, "2-4", "E3"))
    guard = Game.apply_action(state, move_to(state, "2-4", "I2"))
    about_to_win = Game.apply_action(unsafe, move_to(unsafe, "1-3", "I1"))
    assert Bot.evaluate(about_to_win, 2) < -500_000
    refute Enum.any?(Game.legal(guard, "1-3"), &(&1.row == 0 and &1.col == 8))
    guarded = Game.apply_action(guard, move_to(guard, "1-3", "J1"))
    assert Enum.any?(Game.legal(guarded, "2-4"), fn move ->
      move.kind == "attack" and move.row == 0 and move.col == 9
    end)
    assert Bot.evaluate(guarded, 2) > Bot.evaluate(about_to_win, 2) + 500_000

    # Check the actual decision, not a separately re-run post-choice diagnostic.
    {chosen, trace} = Bot.choose_with_trace(state, "hard")
    refute chosen.piece == "2-4" and chosen.row == 2 and chosen.col == 4,
      "hard should not abandon the exit corridor with E3"
    assert trace.chosen == chosen
  end

  test "every difficulty takes an immediate Sentinel victory" do
    state = %{game([piece("sentinel", 2, 9, 5, "s"), piece("sentinel", 1, 2, 5, "enemy")]) | turn: 2}
    for difficulty <- ["easy", "medium", "hard"] do
      move = Bot.choose(state, difficulty)
      assert move.kind == "exit"
      assert Game.apply_action(state, move).result.winner == 2
    end
  end

  test "anticipation prevents the opponent Sentinel's immediate win" do
    state = %{game([piece("sentinel", 2, 1, 5, "bot"), piece("sentinel", 1, 0, 5, "human"), piece("explorer", 1, 7, 7, "other")]) | turn: 2}
    for difficulty <- ["medium", "hard"] do
      move = Bot.choose(state, difficulty)
      assert move.kind == "attack" and move.row == 0 and move.col == 5
    end
    assert Bot.evaluate(%{state | result: %{winner: 1}}, 2) < -999_999
  end

  test "candidate ordering penalizes a genuinely capturable moved piece" do
    state = %{game([
      piece("vanguard", 2, 4, 4, "bot"),
      piece("sentinel", 1, 3, 6, "enemy"),
      piece("explorer", 1, 9, 9, "other")
    ]) | turn: 2}
    dangerous = Enum.find(Game.actions(state), &(&1.piece == "bot" and &1.row == 4 and &1.col == 5))
    safe = Enum.find(Game.actions(state), &(&1.piece == "bot" and &1.row == 5 and &1.col == 4))
    assert dangerous != nil and safe != nil
    ordered = Bot.improve_candidates([{dangerous, 100}, {safe, 100}], state, 12,
      System.monotonic_time(:millisecond) + 10_000)
    assert hd(ordered) |> elem(0) == safe
  end

  test "candidate ordering discourages returning to the previous own position" do
    initial = game([piece("sentinel", 2, 4, 4, "bot"), piece("explorer", 1, 9, 9, "other")])
    previous = %{initial | turn: 1}
    state = %{initial | turn: 2, pieces: [piece("sentinel", 2, 4, 5, "bot"), piece("explorer", 1, 9, 9, "other")],
      history: [Game.position(previous), Game.position(previous)]}
    reversal = Enum.find(Game.actions(state), &(&1.piece == "bot" and &1.row == 4 and &1.col == 4))
    forward = Enum.find(Game.actions(state), &(&1.piece == "bot" and &1.row == 4 and &1.col == 6))
    assert reversal != nil and forward != nil
    options = Bot.improve_candidates([{reversal, 100}, {forward, 100}], state, 12,
      System.monotonic_time(:millisecond) + 10_000)
    assert hd(options) |> elem(0) == forward
  end

  test "terminal and immobilized states produce no move" do
    state = %{Game.new(board()) | result: %{winner: 1, reason: "test"}}
    assert Bot.choose(state, "hard") == nil
  end

  test "equivalent exit columns do not crowd a defensive capture out of search" do
    state = %{game([piece("sentinel", 2, 1, 5, "bot"), piece("vanguard", 2, 9, 1, "runner"), piece("sentinel", 1, 0, 5, "human"), piece("explorer", 1, 7, 7, "other")]) | turn: 2}
    assert Enum.count(Game.actions(state), &(&1.piece == "runner" and &1.kind == "exit")) > 1
    assert Enum.count(Bot.ranked(state, 2), fn {move, _} -> move.piece == "runner" and move.kind == "exit" end) == 1
    greedy = Bot.choose(state, "easy")
    assert greedy.kind == "exit" and greedy.piece == "runner"
    assert Bot.immediate_win?(Game.apply_action(state, greedy))
    for difficulty <- ["medium", "hard"] do
      move = Bot.choose(state, difficulty)
      assert move.kind == "attack" and move.row == 0 and move.col == 5
      refute Bot.immediate_win?(Game.apply_action(state, move))
    end
  end

  test "hard finds a forced Sentinel finish beyond the medium horizon" do
    state = %{game([piece("sentinel", 2, 5, 1, "runner"), piece("vanguard", 2, 4, 7, "fighter"), piece("explorer", 1, 3, 7, "target"), piece("sentinel", 1, 8, 5, "other")]) | turn: 2}
    medium = Bot.choose(state, "medium")
    assert medium.kind == "attack" and medium.row == 3 and medium.col == 7
    hard = Bot.choose(state, "hard")
    assert hard.piece == "runner" and hard.kind == "move" and hard.row in [7, 8]
    next = Game.apply_action(state, hard)
    for reply <- Game.actions(next) do
      after_reply = Game.apply_action(next, reply)
      assert Enum.any?(Game.actions(after_reply), fn move ->
        result = Game.apply_action(after_reply, move).result
        result != nil and result.winner == 2
      end)
    end
  end

  test "terrain distances prefer the gap to crossing a ridge directly" do
    terrain_board = List.replace_at(board(), 4, List.replace_at(List.duplicate(2, 10), 2, 0))
    distances = Bot.terrain(terrain_board)[2]
    assert distances[{3, 3}] == 8
    assert distances[{3, 2}] == 7
    assert 3 + distances[{4, 3}] > distances[{3, 3}]
  end

  @tag timeout: 300_000
  test "medium and hard intercept a lateral Sentinel rush from the initial formation" do
    ridge = for row <- 0..9, do: for(col <- 0..9, do: if(row in [4, 5] and col not in [0, 9], do: 1, else: 0))
    # Reproducible generator outputs for seeds rush-0 and rush-1. The former
    # medium bot lost the right flank on rush-0 and both flanks on rush-1.
    varied = [[4, 4, 4, 5, 4, 4, 2, 3, 3, 3], [4, 5, 5, 4, 4, 4, 3, 2, 3, 2], [4, 4, 4, 3, 3, 2, 2, 2, 2, 1], [3, 2, 2, 4, 2, 2, 1, 1, 1, 0], [3, 2, 2, 2, 2, 2, 1, 2, 2, 2], [2, 2, 2, 1, 2, 2, 2, 2, 2, 3], [0, 1, 1, 1, 2, 2, 4, 2, 2, 3], [1, 2, 2, 2, 2, 3, 3, 4, 4, 4], [2, 3, 2, 3, 4, 4, 4, 5, 5, 4], [3, 3, 3, 2, 4, 4, 5, 4, 4, 4]]
    varied_two = [[1, 1, 2, 3, 3, 2, 1, 0, 2, 3], [1, 2, 3, 2, 1, 3, 2, 1, 1, 2], [1, 2, 3, 1, 2, 2, 2, 2, 1, 1], [3, 2, 1, 2, 2, 1, 2, 3, 2, 1], [4, 3, 1, 2, 2, 2, 3, 2, 2, 3], [3, 2, 2, 3, 2, 2, 2, 1, 3, 4], [1, 2, 3, 2, 1, 2, 2, 1, 2, 3], [1, 1, 2, 2, 2, 2, 1, 3, 2, 1], [2, 1, 1, 2, 3, 1, 2, 3, 2, 1], [3, 2, 0, 1, 2, 3, 3, 2, 1, 1]]
    for terrain <- [board(), ridge, varied, varied_two], side <- [0, 9], difficulty <- ["medium", "hard"], variant <- ["classic", "forests"],
        variant == "classic" or terrain in [board(), ridge] do
      initial = Game.new(terrain, variant, "sentinel-rush")
      id = if side == 0, do: "1-0", else: "1-5"
      final = Enum.reduce_while(1..10, initial, fn _, state ->
        runner = Enum.find(Game.active(state), &(&1.id == id))
        if state.result != nil or runner == nil do
          {:halt, state}
        else
          # Commit to a flank, then rush forward with legal moves on that flank.
          options = Game.legal(state, id)
          move = Enum.min_by(options, fn move ->
            {if(move.kind == "exit", do: -100, else: abs(move.col - side)), move.row, move.col}
          end, fn -> nil end)
          if move == nil do
            {:halt, state}
          else
            next = Game.apply_action(state, move)
            if next.result != nil do
              {:halt, next}
            else
              reply = Bot.choose(next, difficulty)
              assert reply in Game.actions(next)
              {:cont, Game.apply_action(next, reply)}
            end
          end
        end
      end)
      refute final.result != nil and final.result.winner == 1,
        "#{difficulty} lost the #{side} flank rush in #{variant} on #{inspect(terrain)}"
      runner = Enum.find(final.pieces, &(&1.id == id))
      assert runner.status == "captured" or final.result != nil or
        not Enum.any?(Game.legal(%{final | turn: 1}, id), &(&1.kind == "exit"))
    end
  end

  test "capture fields require legal strength, blockers and forest turns" do
    state = %{game([piece("sentinel", 1, 3, 0, "runner"), piece("sentinel", 2, 0, 0, "guard"), piece("explorer", 2, 0, 9, "weak")]) | turn: 2}
    assert Bot.capture_distances(state, "guard", "runner")[{0, 0}] == 1
    refute Map.has_key?(Bot.capture_distances(state, "weak", "runner"), {0, 9})
    wall = for col <- 0..9, do: piece("explorer", 2, 1, col, "wall-#{col}")
    blocked = %{state | pieces: state.pieces ++ wall}
    refute Map.has_key?(Bot.capture_distances(blocked, "guard", "runner"), {0, 0})
    forest = %{state | forests: [%{row: 1, col: 0}]}
    assert Bot.capture_distances(forest, "guard", "runner")[{0, 0}] > 1
  end


  test "a developed full formation retains a strong interceptor within the response budget" do
    initial = Game.new(board())
    pieces = Enum.map(initial.pieces, fn piece ->
      cond do
        piece.id == "1-0" -> %{piece | row: 6, col: 0}
        piece.id == "2-2" -> %{piece | row: 5, col: 0}
        piece.id == "2-3" -> %{piece | row: 6, col: 1}
        true -> piece
      end
    end)
    state = %{initial | pieces: pieces, turn: 2}
    fields = Bot.interceptions(state, Bot.terrain(state.board))
    assert Enum.any?(hd(fields).fields, fn {id, _turn, _distances} -> id in ["2-0", "2-5"] end)
    {elapsed, move} = :timer.tc(fn -> Bot.choose(state, "hard") end)
    assert move in Game.actions(state)
    assert elapsed < 3_000_000
  end


  test "an Explorer exit does not erase the opposing Sentinel's winning second exit" do
    exited = %{piece("explorer", 2, 9, 9, "scorer") | status: "exited"}
    state = %{game([piece("sentinel", 1, 3, 0, "runner"), piece("sentinel", 2, 0, 2, "guard"), exited]) |
      turn: 2, exited: ["scorer"], scores: [0, 1]}
    fields = Bot.interceptions(state, Bot.terrain(state.board))
    assert length(fields) == 1
    assert Bot.choose(state, "medium").piece == "guard"
    # The threat really is a loss after the first one-point exit.
    runner = Enum.find(state.pieces, &(&1.id == "runner"))
    near_exit = %{state | pieces: [%{runner | row: 0}, piece("sentinel", 2, 6, 9, "guard"), exited], turn: 1}
    move = Enum.find(Game.legal(near_exit, "runner"), &(&1.kind == "exit"))
    assert Game.apply_action(near_exit, move).result == %{winner: 1, reason: "two_exits"}
  end

end
