defmodule GameSimulator.Traversal.ForestTest do
  use ExUnit.Case, async: true
  alias GameSimulator.Traversal.{Game, Variant, Bot, Session}

  def board, do: List.duplicate(List.duplicate(0, 10), 10)
  def piece(type, player, row, col, id), do: Map.merge(Game.stats(type), %{id: id, type: type, player: player, row: row, col: col, status: "active"})
  def game(pieces, cells), do: %{Game.new(board()) | pieces: pieces, forests: Enum.map(cells, fn {r, c} -> %{row: r, col: c} end), variant: "forests"}
  def at(moves, row, col), do: Enum.find(moves, &(&1.row == row and &1.col == col))

  test "server layouts are exactly two disjoint rotational 2x2 patches, reproducible and interior" do
    layouts = for seed <- 1..100 do
      cells = Variant.forests("forests", "seed-#{seed}")
      assert cells == Variant.forests("forests", "seed-#{seed}")
      assert length(Enum.uniq(cells)) == 8
      assert Enum.all?(cells, &(&1.row in 1..8 and &1.col in 1..8))
      assert Enum.all?(cells, fn p -> %{row: 9 - p.row, col: 9 - p.col} in cells end)
      for patch <- Enum.chunk_every(cells, 4) do
        row = patch |> Enum.map(& &1.row) |> Enum.min()
        col = patch |> Enum.map(& &1.col) |> Enum.min()
        assert MapSet.new(patch) == MapSet.new(for dr <- 0..1, dc <- 0..1, do: %{row: row + dr, col: col + dc})
      end
      cells
    end
    assert length(Enum.uniq(layouts)) > 10
    assert Variant.forests("classic", nil) == []
    refute Variant.valid?("unknown", "seed")
    refute Variant.valid?("forests", nil)
    refute Variant.valid?("forests", "")
    refute Variant.valid?("forests", String.duplicate("s", 81))
    refute Variant.valid?("forests", 123)
  end

  test "entering forest ends the turn, with no walking through it even toward exit" do
    s = piece("sentinel", 1, 3, 5, "s")
    state = game([s], [{2, 5}])
    moves = Game.legal(state, "s")
    assert at(moves, 2, 5).cost == 1
    refute at(moves, 1, 5)
    {:ok, next} = Game.play(state, "s", 2, 5)
    assert next.turn == 2
    state = game([%{s | row: 1}], [{0, 5}])
    assert at(Game.legal(state, "s"), 0, 5)
    refute at(Game.legal(state, "s"), -1, 5)
  end

  test "starting forest permits one ordinary step with normal relief, capture and support" do
    s = piece("sentinel", 1, 4, 4, "s")
    enemy = piece("sentinel", 2, 4, 5, "enemy")
    state = game([s, enemy], [{4, 4}])
    moves = Game.legal(state, "s")
    assert at(moves, 4, 5).kind == "attack"
    assert at(moves, 3, 4)
    refute at(moves, 2, 4)
    refute at(moves, 3, 5)
    hills = List.update_at(board(), 3, &List.replace_at(&1, 4, 2))
    assert at(Game.legal(%{state | board: hills}, "s"), 3, 4).cost == 3
    ally = piece("explorer", 1, 3, 5, "ally")
    assert Game.combat(game([s, enemy, ally], [{4, 4}]), s, enemy, 1) == Game.combat(game([s, enemy, ally], []), s, enemy, 1)
    v = piece("vanguard", 1, 4, 4, "v")
    refute at(Game.legal(game([v, enemy], [{4, 4}]), "v"), 4, 5)
    assert at(Game.legal(game([%{s | row: 1}], [{1, 4}]), "s"), 0, 4)
    refute at(Game.legal(game([%{s | row: 1}], [{1, 4}]), "s"), -1, 4)
    assert at(Game.legal(game([%{s | row: 0}], [{0, 4}]), "s"), -1, 4)
  end

  test "Explorer retains diagonal, jump, capture and exit from forests; only pieces block jumps" do
    e = piece("explorer", 1, 4, 4, "e")
    state = game([e], [{4, 4}, {3, 4}, {3, 3}])
    moves = Game.legal(state, "e")
    assert at(moves, 3, 3).special
    assert at(moves, 2, 4).special
    refute at(moves, 1, 4)
    enemy = piece("explorer", 2, 3, 3, "enemy")
    assert at(Game.legal(%{state | pieces: [e, enemy]}, "e"), 3, 3).kind == "attack"
    for player <- [1, 2] do
      blocker = piece("explorer", player, 3, 4, "block")
      refute at(Game.legal(%{state | pieces: [e, blocker]}, "e"), 2, 4)
    end
    # From outside, a forest in the middle is still not a jump obstacle.
    blockers = for {r, c} <- [{4, 3}, {4, 5}, {5, 4}], do: piece("sentinel", 1, r, c, "block-#{r}-#{c}")
    assert at(Game.legal(game([e | blockers], [{3, 4}]), "e"), 2, 4).special
    assert at(Game.legal(game([%{e | row: 1}], [{1, 4}, {0, 4}]), "e"), -1, 4).special
    assert at(Game.legal(game([%{e | row: 0}], [{0, 4}]), "e"), -1, 3).special
    assert length(Enum.filter(Game.legal(game([e], []), "e"), &(&1.row == 3 and &1.col == 3))) == 1
  end

  test "forest routes never manufacture a charge when a cheaper ordinary capture exists" do
    v = piece("vanguard", 1, 5, 3, "v")
    s = piece("sentinel", 2, 5, 5, "s")
    refute at(Game.legal(game([v, s], [{4, 4}]), "v"), 5, 5)
    assert at(Game.legal(game([%{v | col: 1}, s], [{4, 4}]), "v"), 5, 5).cost == 4
  end

  test "three bot levels only choose authoritative forest actions and estimate stop cost" do
    s = piece("sentinel", 1, 4, 4, "s")
    enemy = piece("vanguard", 2, 7, 7, "enemy")
    state = game([s, enemy], [{4, 4}, {3, 4}])
    for difficulty <- ["easy", "medium", "hard"] do
      assert Bot.choose(state, difficulty) in Game.actions(state)
    end
    classic = Bot.terrain(board())
    wooded = Bot.terrain(board(), Enum.map(0..9, &%{row: 3, col: &1}))
    assert wooded[1][{4, 4}] > classic[1][{4, 4}]
  end

  test "sessions validate variant and bounded seed, persist server forests and keep classic defaults" do
    user = "forest-test-#{System.unique_integer([:positive])}"
    {:ok, pid} = Session.server(user)
    on_exit(fn -> if Process.alive?(pid), do: DynamicSupervisor.terminate_child(GameSimulator.TableSupervisor, pid) end)
    for {variant, seed} <- [{"oops", "seed"}, {"forests", nil}, {"forests", ""}, {"forests", String.duplicate("a", 81)}, {"forests", %{}}] do
      assert {:error, :invalid_game} = Session.request(user, {:new, board(), "easy", seed, variant})
    end
    {:ok, wooded} = Session.request(user, {:new, board(), "easy", "seed", "forests"})
    assert wooded.game.variant == "forests"
    assert wooded.game.forests == Variant.forests("forests", "seed")
    {:ok, resumed} = Session.request(user, :get)
    assert resumed == wooded
    {:ok, classic} = Session.request(user, {:new, board(), "easy"})
    assert classic.game.variant == "classic"
    assert classic.game.forests == []
    assert Game.actions(Map.delete(classic.game, :forests)) == classic.legal
  end
end
