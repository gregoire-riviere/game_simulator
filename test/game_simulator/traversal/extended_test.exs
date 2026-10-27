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
    refute Enum.any?(g.forests, &(&1.row == 6))
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
    cannon = piece("cannon", 1, 7, 4, "c")
    target = piece("explorer", 2, 4, 4, "t")
    g = %{Game.new(board(12), "extended+bridge") | pieces: [cannon, target], moves: 2, bridge_open: false}
    assert action(g, "c", 4, 4).kind == "attack"
    refute Game.crossing?(g, 7, 4, 6, 4)
    assert Game.crossing?(g, 7, 7, 6, 7)
    refute Game.crossing?(g, 7, 2, 5, 2, true)
    blocker = piece("vanguard", 1, 6, 4, "v")
    assert Game.next_bridge(%{g | pieces: [blocker, target]}).bridge_open
    assert not Game.next_bridge(g).bridge_open
    assert Game.next_bridge(%{g | moves: 4}).bridge_open
    refute Game.position(g) == Game.position(%{g | moves: 3})
  end

  test "river occupies one whole row, except its two bridges" do
    for size <- [10, 12] do
      mid = div(size, 2)
      explorer = piece("explorer", 1, mid + 1, mid - 2, "e")
      target = piece("sentinel", 2, 0, 0, "t")
      g = %{Game.new(board(size), "bridge") | pieces: [explorer, target]}
      assert action(g, "e", mid, mid - 2)
      assert action(g, "e", mid - 1, mid - 2)
      refute action(%{g | bridge_open: false}, "e", mid, mid - 2)
      refute action(%{g | bridge_open: false}, "e", mid - 1, mid - 2)
      for col <- 0..(size - 1), col not in [mid - 2, mid + 1] do
        refute Game.crossing?(g, mid + 1, col, mid, col)
        refute Game.crossing?(g, mid + 1, col, mid - 1, col)
      end
      assert Game.crossing?(%{g | bridge_open: false}, mid + 1, mid + 1, mid, mid + 1)
    end
  end

  test "forest layouts stay symmetric and never overlap the river" do
    for size <- [10, 12], seed <- 1..100 do
      cells = Variant.forests("forests+bridge", "seed-#{seed}", size)
      assert length(cells) == 8
      refute Enum.any?(cells, &(&1.row == div(size, 2)))
      assert Enum.all?(cells, fn p -> %{row: size - 1 - p.row, col: size - 1 - p.col} in cells end)
    end
  end

  test "occupied bridge stays open until the piece leaves during a closed phase" do
    bridge_piece = piece("vanguard", 1, 6, 4, "v")
    ally = piece("explorer", 1, 10, 0, "a")
    enemy = piece("explorer", 2, 1, 0, "t")
    g = %{Game.new(board(12), "extended+bridge") | pieces: [bridge_piece, ally, enemy], moves: 1}
    {:ok, held} = Game.play(g, "a", 9, 0)
    assert held.bridge_open
    held = %{held | turn: 1}
    {:ok, left} = Game.play(held, "v", 5, 4)
    refute left.bridge_open
  end

  test "bot evaluates a bridge that opens after its distance fields were built" do
    explorer = piece("explorer", 1, 7, 4, "e")
    enemy = piece("sentinel", 2, 2, 8, "s")
    closed = %{Game.new(board(12), "extended+bridge") | pieces: [explorer, enemy], moves: 3, turn: 2, bridge_open: false}
    fields = Bot.terrain(closed.board, [], closed)
    refute Map.has_key?(Bot.terrain_for(closed, fields, 1), {6, 4})

    opened = %{closed | moves: 4, turn: 1, bridge_open: true}
    assert Map.has_key?(Bot.terrain_for(opened, fields, 1), {6, 4})
    {:ok, on_bridge} = Game.play(opened, "e", 6, 4)
    assert is_integer(Bot.evaluate(on_bridge, 2, fields))

    for difficulty <- ["medium", "hard"] do
      {move, trace} = Bot.choose_with_trace(closed, difficulty)
      assert move in Game.actions(closed)
      assert trace.chosen == move
    end
  end

  test "an immediate sentinel exit takes priority over a tactical capture" do
    heights = ["000001100011", "111111111112", "222211112222", "333322222333",
      "444332233344", "544333334445", "544433333445", "443332233444",
      "333222223333", "222211112222", "211111111111", "110001100000"]
      |> Enum.map(fn row -> row |> String.graphemes() |> Enum.map(&String.to_integer/1) end)
    moves = [{"1-3", 9, 5}, {"2-0", 1, 8}, {"1-3", 8, 5}, {"2-0", 3, 8},
      {"1-3", 8, 7}, {"2-0", 4, 7}, {"1-3", 8, 8}, {"2-0", 7, 7},
      {"1-3", 8, 10}, {"2-0", 7, 5}, {"1-3", 8, 8}, {"2-0", 9, 5}, {"1-0", 10, 3}]
    state = Enum.reduce(moves, Game.new(heights, "extended+forests+bridge", "1115841654"), fn {id, row, col}, game ->
      {:ok, next} = Game.play(game, id, row, col)
      next
    end)
    assert Enum.any?(Game.legal(state, "2-0"), &(&1.kind == "attack"))
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
    g = %{Game.new(board(12), "extended+bridge+forests", "seed") | pieces: [cannon, enemy]}
    for level <- ["easy", "medium", "hard"], do: assert(Bot.choose(g, level) in Game.actions(g))
  end
end
