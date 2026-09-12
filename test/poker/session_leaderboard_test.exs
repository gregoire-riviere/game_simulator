defmodule Poker.SessionLeaderboardTest do
  use ExUnit.Case, async: true

  test "ranks players by current stack and exposes their session profit or loss" do
    {:ok, game} = Poker.Game.start_link(small_blind: 1, big_blind: 2)
    {:ok, _player} = Poker.Game.join(game, :alice, 100, 1)
    {:ok, _player} = Poker.Game.join(game, :bob, 100, 2)
    {:ok, _state} = Poker.Game.start_hand(game)
    {:ok, _state} = Poker.Game.act(game, :alice, :fold)

    assert {:ok, leaderboard} = Poker.Game.session_leaderboard(game)

    assert leaderboard == [
             %{rank: 1, player_id: :bob, seat: 2, stack: 101, profit_loss: 1, status: :active},
             %{rank: 2, player_id: :alice, seat: 1, stack: 99, profit_loss: -1, status: :active}
           ]
  end

  test "keeps tied stacks in seat order and identifies eliminated players" do
    {:ok, game} = Poker.Game.start_link(small_blind: 1, big_blind: 2)
    {:ok, _player} = Poker.Game.join(game, :alice, 100, 2)
    {:ok, _player} = Poker.Game.join(game, :bob, 100, 1)
    {:ok, _player} = Poker.Game.join(game, :charlie, 0, 3)

    assert {:ok, leaderboard} = Poker.Game.session_leaderboard(game)

    assert leaderboard == [
             %{rank: 1, player_id: :bob, seat: 1, stack: 100, profit_loss: 0, status: :active},
             %{rank: 2, player_id: :alice, seat: 2, stack: 100, profit_loss: 0, status: :active},
             %{rank: 3, player_id: :charlie, seat: 3, stack: 0, profit_loss: 0, status: :eliminated}
           ]
  end
end
