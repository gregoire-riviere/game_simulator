defmodule GameSimulator.Traversal.ExtendedTest do
  use ExUnit.Case, async: true
  alias GameSimulator.Traversal.{Game, Variant, Bot}

  def board(size), do: List.duplicate(List.duplicate(0, size), size)
  def piece(type, player, row, col, id), do: Map.merge(Game.stats(type), %{id: id, type: type, player: player, row: row, col: col, status: "active"})
  def action(game, id, row, col), do: Enum.find(Game.legal(game, id), &(&1.row == row and &1.col == col))

  test "extended setup and composable variants are symmetric and reproducible" do
    g = Game.new(board(12), "extended+forests+bridge", "seed")
    assert Game.valid_board?(g.board)
    assert length(g.pieces) == 14
    assert length(g.forests) == 8
    assert g.forests == Variant.forests("extended+forests+bridge", "seed", 12)
    for p <- Enum.filter(g.pieces, &(&1.player == 1)) do
      assert Enum.any?(g.pieces, &(&1.player == 2 and &1.type == p.type and &1.row == 11 - p.row and &1.col == 11 - p.col))
    end
    assert Variant.valid?(g.variant, "seed")
  end

  test "legacy game states without a variant retain the classic rules" do
    g = Game.new(board(10)) |> Map.delete(:variant) |> Map.delete(:bridge_open)
    refute Game.bridge?(g)
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

  test "bridge cycle, occupied delay, river crossing and firing over closed bridge" do
    cannon = piece("cannon", 1, 7, 6, "c")
    target = piece("explorer", 2, 4, 6, "t")
    g = %{Game.new(board(12), "extended+bridge") | pieces: [cannon, target], moves: 2, bridge_open: false}
    assert action(g, "c", 4, 6).kind == "attack"
    assert Game.crossing?(g, 6, 6, 5, 6) == false
    assert Game.crossing?(g, 6, 1, 5, 1)
    assert not Game.crossing?(g, 6, 4, 5, 4, true)
    blocker = piece("vanguard", 1, 6, 6, "v")
    assert Game.next_bridge(%{g | pieces: [blocker, target]}).bridge_open
    assert not Game.next_bridge(g).bridge_open
    assert Game.next_bridge(%{g | moves: 4}).bridge_open
    refute Game.position(g) == Game.position(%{g | moves: 3})
  end

  test "bots choose legal actions in combined variant" do
    cannon = piece("cannon", 1, 7, 6, "c")
    enemy = piece("explorer", 2, 4, 6, "t")
    g = %{Game.new(board(12), "extended+bridge+forests", "seed") | pieces: [cannon, enemy]}
    for level <- ["easy", "medium", "hard"], do: assert(Bot.choose(g, level) in Game.actions(g))
  end
end
