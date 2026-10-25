defmodule GameSimulator.Traversal.GameTest do
  use ExUnit.Case, async: true
  alias GameSimulator.Traversal.Game

  def board(height \\ 0), do: List.duplicate(List.duplicate(height, 10), 10)
  def piece(type, player, row, col, id), do: Map.merge(Game.stats(type), %{id: id, type: type, player: player, row: row, col: col, status: "active"})
  def game(pieces, heights \\ board()), do: %{Game.new(heights) | pieces: pieces}
  def destination?(moves, row, col), do: Enum.any?(moves, &(&1.row == row and &1.col == col))
  def at(heights, row, col, height), do: List.update_at(heights, row, &List.replace_at(&1, col, height))

  test "official setup, terrain bounds, symmetry and slopes" do
    game = Game.new(board())
    assert length(game.pieces) == 12
    assert Enum.map(Enum.take(game.pieces, 6), & &1.type) == ["sentinel", "vanguard", "explorer", "explorer", "vanguard", "sentinel"]
    assert Enum.map(Enum.take(game.pieces, 6), &{&1.row, &1.col}) == Enum.map(2..7, &{9, &1})
    assert Game.valid_board?(board())
    refute Game.valid_board?(board(6))
    refute Game.valid_board?([[0]])
    refute Game.valid_board?(at(board(), 2, 2, 1))
    refute Game.valid_board?(board() |> at(2, 2, 3) |> at(7, 7, 3))
  end

  test "normal movement turns corners, charges both ascent and descent, cannot cross pieces" do
    mover = piece("vanguard", 1, 5, 5, "v")
    heights = board() |> at(5, 6, 2)
    moves = Game.legal(game([mover], heights), "v")
    assert Enum.find(moves, &(&1.row == 5 and &1.col == 6)).cost == 3
    assert destination?(moves, 4, 6)
    refute destination?(moves, 5, 9)
    blockers = for {r, c} <- Game.neighbours(5, 5), do: piece("sentinel", 1, r, c, "b#{r}-#{c}")
    assert Game.legal(game([mover | blockers]), "v") == []
    descending = game([%{mover | row: 5, col: 6}], heights)
    assert Enum.find(Game.legal(descending, "v"), &(&1.row == 5 and &1.col == 5)).cost == 3
  end

  test "only legal captures shown, capture ends movement and cannot cross enemy" do
    attacker = piece("sentinel", 1, 5, 5, "s")
    enemy = piece("sentinel", 2, 5, 6, "enemy")
    state = game([attacker, enemy])
    assert Enum.find(Game.legal(state, "s"), &(&1.row == 5 and &1.col == 6)).kind == "attack"
    refute destination?(Game.legal(state, "s"), 5, 7)
    {:ok, next} = Game.play(state, "s", 5, 6)
    assert Enum.find(next.pieces, &(&1.id == "enemy")).status == "captured"
    assert next.moves == 1
    assert next.turn == 2
    assert {:error, :illegal_move} = Game.play(state, "s", 5, 7)
    weak = game([piece("explorer", 1, 5, 5, "e"), enemy])
    refute destination?(Game.legal(weak, "e"), 5, 6)
  end

  test "height compares original square, support sums base forces and excludes attacker" do
    attacker = piece("sentinel", 1, 5, 4, "a")
    target = piece("vanguard", 2, 5, 6, "d")
    ally = piece("vanguard", 1, 4, 6, "support")
    defender = piece("explorer", 2, 6, 6, "guard")
    state = game([attacker, target, ally, defender], board() |> at(5, 4, 2) |> at(5, 5, 1))
    assert Game.combat(state, attacker, target, 4) == %{attack: 6, defence: 3}
    adjacent = %{attacker | col: 5}
    assert Game.combat(game([adjacent, target]), adjacent, target, 1) == %{attack: 3, defence: 2}
    uphill = game([adjacent, target], at(board(), 5, 6, 2))
    assert Game.combat(uphill, adjacent, target, 3).attack == 2
  end

  test "Vanguard charge uses minimum cost exactly four, never a detour" do
    v = piece("vanguard", 1, 5, 1, "v")
    s = piece("sentinel", 2, 5, 5, "s")
    assert destination?(Game.legal(game([v, s]), "v"), 5, 5)
    refute destination?(Game.legal(game([%{v | col: 3}, s]), "v"), 5, 5)
    refute destination?(Game.legal(game([%{v | col: 4}, s]), "v"), 5, 5)
  end

  test "Explorer standalone special ignores height, cannot combine with normal or jump occupants" do
    e = piece("explorer", 1, 5, 5, "e")
    heights = board(5) |> at(5, 5, 0) |> at(4, 4, 0) |> at(3, 5, 0)
    moves = Game.legal(game([e], heights), "e")
    assert Enum.find(moves, &(&1.row == 4 and &1.col == 4)).special
    assert destination?(moves, 3, 5)
    refute destination?(moves, 3, 4)
    for player <- [1, 2] do
      blocker = piece("sentinel", player, 4, 5, "b")
      refute destination?(Game.legal(game([e, blocker], heights), "e"), 3, 5)
    end
  end

  test "Explorer special can capture and offers no duplicate normal destination" do
    e = piece("explorer", 1, 5, 5, "e")
    enemy = piece("explorer", 2, 4, 4, "enemy")
    state = game([e, enemy], board(5) |> at(5, 5, 0) |> at(4, 4, 0))
    move = Enum.find(Game.legal(state, "e"), &(&1.row == 4 and &1.col == 4))
    assert move.kind == "attack" and move.special
    assert length(Enum.filter(Game.legal(game([e]), "e"), &(&1.row == 4 and &1.col == 4))) == 1
  end

  test "normal exit needs one spare PM and Explorer can exit by diagonal or jump" do
    s = piece("sentinel", 1, 2, 5, "s")
    assert destination?(Game.legal(game([s]), "s"), -1, 5)
    refute destination?(Game.legal(game([%{s | row: 3}]), "s"), -1, 5)
    e = piece("explorer", 1, 1, 5, "e")
    heights = board(5) |> at(1, 5, 0)
    assert destination?(Game.legal(game([e], heights), "e"), -1, 5)
    blocker = piece("sentinel", 2, 0, 5, "b")
    refute destination?(Game.legal(game([e, blocker], heights), "e"), -1, 5)
    assert destination?(Game.legal(game([%{e | row: 0}]), "e"), -1, 4)
  end

  test "first Sentinel wins immediately and all actions close at game over" do
    state = game([piece("sentinel", 1, 0, 5, "s"), piece("vanguard", 2, 8, 4, "enemy")])
    {:ok, next} = Game.play(state, "s", -1, 5)
    assert next.result == %{winner: 1, reason: "first_sentinel"}
    assert Game.actions(next) == []
  end

  test "two total exits decide on strength, including an equal-score draw" do
    for {type, expected} <- [{"explorer", 0}, {"sentinel", 2}] do
      old = %{piece("explorer", 1, 0, 5, "old") | status: "exited"}
      state = %{game([old, piece(type, 2, 9, 5, "next"), piece("sentinel", 1, 4, 4, "live")]) | exited: ["old"], scores: [1, 0], turn: 2}
      {:ok, next} = Game.play(state, "next", 10, 5)
      assert next.result == %{winner: expected, reason: "two_exits"}
    end
  end

  test "no active pieces adds maximum surviving force to exited scores" do
    old = %{piece("vanguard", 1, 0, 5, "old") | status: "exited"}
    state = %{game([old, piece("explorer", 1, 5, 5, "last"), piece("sentinel", 2, 5, 6, "s")]) | exited: ["old"], scores: [2, 0], turn: 2}
    {:ok, next} = Game.play(state, "s", 5, 5)
    assert next.scores == [2, 3]
    assert next.result == %{winner: 2, reason: "no_active_pieces"}
  end

  test "200 individual moves: score then closest rank then force then draw" do
    assert Game.move_limit(%{Game.new(board()) | scores: [1, 0]}).result.winner == 1
    assert Game.move_limit(game([piece("explorer", 1, 1, 1, "a"), piece("sentinel", 2, 7, 1, "b")])).result.winner == 1
    assert Game.move_limit(game([piece("explorer", 1, 1, 1, "a"), piece("sentinel", 2, 8, 1, "b")])).result.winner == 2
    assert Game.move_limit(game([piece("sentinel", 1, 1, 1, "a"), piece("sentinel", 2, 8, 1, "b")])).result.winner == 0
    state = %{Game.new(board()) | moves: 199}
    [move | _] = Game.actions(state)
    assert Game.apply_action(state, move).result != nil
  end

  test "repetition is three complete even sequences, not scattered position occurrences" do
    assert Game.repeated?([:a, :b, :a, :b, :a, :b])
    assert Game.repeated?([:x, :a, :b, :c, :d, :a, :b, :c, :d, :a, :b, :c, :d])
    refute Game.repeated?([:a, :b, :a, :c, :a, :d])
    refute Game.repeated?([:a, :b, :a, :b])
  end
end
