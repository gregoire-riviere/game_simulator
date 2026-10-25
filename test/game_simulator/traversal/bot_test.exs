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
    for terrain <- [board(), ridge], side <- [0, 9], difficulty <- ["medium", "hard"], variant <- ["classic", "forests"] do
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
    refute Map.has_key?(Bot.capture_distances(state, "weak", "runner"), {0, 0})
    forest = %{state | forests: [%{row: 1, col: 0}]}
    assert Bot.capture_distances(forest, "guard", "runner")[{0, 0}] > 1
  end

end
