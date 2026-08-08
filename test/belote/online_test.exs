defmodule Belote.OnlineTest do
  use ExUnit.Case, async: false

  setup do
    Belote.Online.leave("host")
    Belote.Online.leave("guest")
    on_exit(fn ->
      Belote.Online.leave("host")
      Belote.Online.leave("guest")
    end)
    :ok
  end

  test "host creates a code, another player joins as partner and host starts" do
    assert {:ok, lobby} = Belote.Online.create("host", "belote:classic", 1000)
    assert lobby.status == :waiting
    assert lobby.is_host
    assert lobby.player_count == 1
    assert String.length(lobby.code) == 5

    assert {:ok, guest_lobby} = Belote.Online.join("guest", String.downcase(lobby.code))
    assert guest_lobby.player_count == 2
    assert Enum.find(guest_lobby.players, & &1.self).seat == 2

    assert {:error, :host_required} = Belote.Online.start_game("guest")
    assert {:ok, game} = Belote.Online.start_game("host")
    assert game.status == :playing
    assert game.online

    assert {:ok, guest_game} = Belote.Online.state("guest")
    assert guest_game.seat == 2
    assert guest_game.hero_turn
    assert length(guest_game.actions) > 0
  end

  test "empty seats become bots when the host starts" do
    assert {:ok, _lobby} = Belote.Online.create("host", "belote:coinche", 501)
    assert {:ok, game} = Belote.Online.start_game("host")

    assert Enum.count(game.players, & &1.human) == 1
    assert Enum.count(game.players, &(not &1.human)) == 3
  end
end
