defmodule Morpion.GameTest do
  use ExUnit.Case, async: true

  alias Morpion.Game

  test "starts a 3 by 3 game with the selected human mark and lets X play first" do
    assert {:ok, state} = Game.new(:x)
    assert state.board == List.duplicate(nil, 9)
    assert state.turn == :human
    assert state.human_mark == :x

    assert {:ok, state} = Game.new(:o)
    assert state.turn == :bot
    assert state.human_mark == :o
  end

  test "accepts only empty cells on the human turn and follows a valid move with one bot move" do
    {:ok, state} = Game.new(:x)

    assert {:ok, state} = Game.play(state, 0)
    assert Enum.count(state.board, &(&1 == :x)) == 1
    assert Enum.count(state.board, &(&1 == :o)) == 1

    board_before = state.board
    assert {:error, :illegal_move} = Game.play(state, 0)
    assert state.board == board_before
  end

  test "reports a draw and replay clears the completed board" do
    state = Game.from_board([:x, :o, :x, :x, :o, :o, :o, :x, :x], human_mark: :x)

    assert %{status: :draw} = Game.public_state(state)
    assert {:ok, replayed} = Game.replay(state)
    assert replayed.board == List.duplicate(nil, 9)
  end
end
