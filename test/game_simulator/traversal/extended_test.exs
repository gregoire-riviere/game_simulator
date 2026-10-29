defmodule GameSimulator.Traversal.ExtendedTest do
  use ExUnit.Case, async: true
  alias GameSimulator.Traversal.{Game, Variant, Bot}

  def board(size), do: List.duplicate(List.duplicate(0, size), size)
  def piece(type, player, row, col, id), do: Map.merge(Game.stats(type), %{id: id, type: type, player: player, row: row, col: col, status: "active"})
  def action(game, id, row, col), do: Enum.find(Game.legal(game, id), &(&1.row == row and &1.col == col))

  test "extended setup and composable variants are symmetric and reproducible" do
    g = Game.new(board(12), "extended+forests", "seed")
    assert Game.valid_board?(g.board)
    assert length(g.pieces) == 14
    assert length(g.forests) == 8
    assert g.forests == Variant.forests("extended+forests", "seed", 12)
    for p <- Enum.filter(g.pieces, &(&1.player == 1)) do
      assert Enum.any?(g.pieces, &(&1.player == 2 and &1.type == p.type and &1.row == 11 - p.row and &1.col == 11 - p.col))
    end
    assert Variant.valid?(g.variant, "seed")
  end

  test "legacy game states without a variant retain the classic rules" do
    g = Game.new(board(10)) |> Map.delete(:variant)
    refute Map.has_key?(g, :variant)
    assert Game.actions(g) != []
    assert Game.apply_action(g, hd(Game.actions(g))).moves == 1
  end

  test "cannon fires only at distance, does not move and obeys blockers and forest" do
    cannon = piece("cannon", 1, 7, 4, "c")
    target = piece("explorer", 2, 4, 4, "t")
    g = %{Game.new(board(12), "extended") | pieces: [cannon, target]}
    shot = action(g, "c", 4, 4)
    assert shot && shot.kind == "attack"
    next = Game.apply_action(g, shot)
    assert Game.occupant(next, 7, 4).id == "c"
    assert Game.occupant(next, 4, 4) == nil
    assert Enum.find(next.pieces, &(&1.id == "t")).status == "captured"
    assert action(%{g | pieces: [cannon, %{target | row: 6}]}, "c", 6, 4) == nil
    block = piece("explorer", 1, 6, 4, "b")
    assert action(%{g | pieces: [cannon, block, target]}, "c", 4, 4) == nil
    assert action(%{g | forests: [%{row: 7, col: 4}]}, "c", 4, 4) == nil
    high = List.update_at(g.board, 4, &List.replace_at(&1, 4, 1))
    assert action(%{g | board: high}, "c", 4, 4) == nil
  end

  test "bridge variants are rejected" do
    for variant <- ["bridge", "extended+bridge", "forests+bridge", "extended+forests+bridge"] do
      refute Variant.valid?(variant, "seed")
    end
    assert Variant.valid?("classic", nil)
    assert Variant.valid?("extended", nil)
    assert Variant.valid?("forests", "seed")
    assert Variant.valid?("extended+forests", "seed")
  end

  test "central rows are accessible in both board sizes" do
    for size <- [10, 12] do
      mid = div(size, 2)
      runner = piece("explorer", 1, mid + 1, 3, "runner")
      target = piece("sentinel", 2, 0, 0, "target")
      g = %{Game.new(board(size), if(size == 12, do: "extended", else: "classic")) | pieces: [runner, target]}
      assert action(g, "runner", mid, 3)
      assert action(g, "runner", mid - 1, 3)
      assert Map.has_key?(Bot.terrain_for(g, Bot.terrain(g.board, [], g), 1), {mid, 3})
    end
  end

  test "forest layouts remain symmetric and reproducible" do
    for size <- [10, 12], seed <- 1..100 do
      cells = Variant.forests("forests", "seed-#{seed}", size)
      assert length(cells) == 8
      assert cells == Variant.forests("forests", "seed-#{seed}", size)
      assert Enum.all?(cells, fn p -> %{row: size - 1 - p.row, col: size - 1 - p.col} in cells end)
    end
  end

  test "an immediate sentinel exit takes priority over a tactical capture" do
    winner = piece("sentinel", 2, 11, 5, "winner")
    attacker = piece("vanguard", 2, 8, 7, "attacker")
    victim = piece("explorer", 1, 7, 7, "victim")
    opponent = piece("sentinel", 1, 0, 0, "opponent")
    state = %{Game.new(board(12), "extended") | pieces: [winner, attacker, victim, opponent], turn: 2}
    assert action(state, "attacker", 7, 7).kind == "attack"
    assert Enum.any?(Game.legal(state, "winner"), &(&1.kind == "exit"))
    for difficulty <- ["easy", "medium", "hard"] do
      {move, trace} = Bot.choose_with_trace(state, difficulty)
      assert move.kind == "exit"
      assert Game.apply_action(state, move).result.winner == 2
      assert trace.chosen == move
    end
  end

  test "bots choose legal actions in combined variant" do
    cannon = piece("cannon", 1, 7, 6, "c")
    enemy = piece("explorer", 2, 4, 6, "t")
    g = %{Game.new(board(12), "extended+forests", "seed") | pieces: [cannon, enemy]}
    for level <- ["easy", "medium", "hard"], do: assert(Bot.choose(g, level) in Game.actions(g))
  end
end
