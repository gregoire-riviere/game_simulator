defmodule MrWhite.GameTest do
  use ExUnit.Case, async: true

  test "creates one role of each infiltrator and spreads Mr. White after the first position" do
    games =
      Enum.map(1..100, fn _ ->
        {:ok, game} =
          MrWhite.Game.new(["Alice", "Bob", "Chloé", "David"],
            word_pair: {"train", "bus"},
            roles: [:mr_white, :spy, :civil, :civil],
            order: [1, 2, 3, 4]
          )

        game
      end)

    game = hd(games)
    positions = Enum.map(games, fn game -> Enum.find_index(game.order, &(&1 == 1)) + 1 end)

    assert 1 not in positions
    assert Enum.sort(Enum.uniq(positions)) == [2, 3, 4]
    assert Enum.frequencies_by(game.players, & &1.role) == %{civil: 2, mr_white: 1, spy: 1}
  end

  test "only reveals the current word and does not identify the spy" do
    {:ok, game} = game([:spy, :mr_white, :civil, :civil])
    assert {:ok, %{name: "Alice", role: nil, word: "bus"}} = MrWhite.Game.secret(game)

    assert {:ok, game} = MrWhite.Game.act(game, :confirm_reveal)
    assert {:ok, %{name: "Bob", role: :mr_white, word: nil}} = MrWhite.Game.secret(game)
  end

  test "creates several spies sharing the same word" do
    assert {:ok, game} = MrWhite.Game.new(["Alice", "Bob", "Chloé", "David", "Emma"],
      spy_count: 2,
      word_pair: {"train", "bus"}
    )

    spies = Enum.filter(game.players, &(&1.role == :spy))
    assert length(spies) == 2
    assert Enum.all?(spies, &(MrWhite.Game.player_secret(&1, game).word == "bus"))
  end

  test "requires fewer spies than half of the players" do
    names = ["Alice", "Bob", "Chloé", "David", "Emma", "Fred"]
    assert {:ok, _game} = MrWhite.Game.new(names, spy_count: 2)
    assert {:error, :invalid_spy_count} = MrWhite.Game.new(names, spy_count: 3)
    assert {:error, :invalid_spy_count} = MrWhite.Game.new(names, spy_count: 0)
  end

  test "lets an active player review their word during the vote" do
    {:ok, game} = game([:mr_white, :spy, :civil, :civil])
    assert {:error, :invalid_phase} = MrWhite.Game.review_secret(game, 3)
    game = finish_reveals(game)

    assert {:ok, %{name: "Chloé", role: nil, word: "train"}} = MrWhite.Game.review_secret(game, 3)
    assert {:ok, game} = MrWhite.Game.act(game, {:eliminate, 3})
    assert {:ok, game} = MrWhite.Game.act(game, :next_round)
    assert {:error, :invalid_player} = MrWhite.Game.review_secret(game, 3)
  end

  test "ends as soon as both infiltrators are eliminated" do
    {:ok, game} = game([:civil, :mr_white, :spy, :civil, :civil])
    game = finish_reveals(game)

    assert {:ok, game} = MrWhite.Game.act(game, {:eliminate, 2})
    assert game.phase == :elimination
    assert {:ok, game} = MrWhite.Game.act(game, {:mr_white_guess, false})
    assert game.end_reason == nil
    assert {:ok, game} = MrWhite.Game.act(game, :next_round)
    assert {:ok, game} = MrWhite.Game.act(game, {:eliminate, 3})
    assert game.phase == :finished
    assert game.end_reason == :both_infiltrators_eliminated
  end

  test "ends without choosing a winner when only two players remain" do
    {:ok, game} = game([:civil, :mr_white, :spy, :civil])
    game = finish_reveals(game)

    assert {:ok, game} = MrWhite.Game.act(game, {:eliminate, 1})
    assert {:ok, game} = MrWhite.Game.act(game, :next_round)
    assert {:ok, game} = MrWhite.Game.act(game, {:eliminate, 4})

    public = MrWhite.Game.public_state(game)
    assert public.phase == :finished
    assert public.end_reason == :two_players_remaining
    assert Enum.all?(public.players, & &1.role)
    assert public.words == %{civil: "train", spy: "bus"}
  end

  test "lets the group validate Mr. White's proposal" do
    {:ok, game} = game([:civil, :mr_white, :spy, :civil])
    game = finish_reveals(game)

    assert {:ok, game} = MrWhite.Game.act(game, {:eliminate, 2})
    assert {:ok, game} = MrWhite.Game.act(game, {:mr_white_guess, true})
    assert game.phase == :finished
    assert game.end_reason == :mr_white_guess_accepted
  end

  test "validates the player list" do
    assert {:error, :invalid_players} = MrWhite.Game.new(["Alice", "alice", "Bob"])
    assert {:error, :invalid_players} = MrWhite.Game.new(["Alice", "Bob"])
    assert {:error, :invalid_players} = MrWhite.Game.new(["Alice", "", "Bob"])
  end

  def game(roles) do
    names = ["Alice", "Bob", "Chloé", "David", "Emma"] |> Enum.take(length(roles))

    MrWhite.Game.new(names,
      word_pair: {"train", "bus"},
      roles: roles,
      order: Enum.to_list(1..length(roles))
    )
  end

  def finish_reveals(game) do
    Enum.reduce(1..length(game.players), game, fn _step, state ->
      {:ok, state} = MrWhite.Game.act(state, :confirm_reveal)
      state
    end)
  end
end
