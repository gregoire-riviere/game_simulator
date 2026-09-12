defmodule GameSimulatorWeb.MrWhiteParticipantsTest do
  use ExUnit.Case, async: false

  import Plug.Conn
  import Plug.Test

  alias GameSimulatorWeb.{Auth, Endpoint, Users}

  setup do
    data_directory = Path.join(System.tmp_dir!(), "game-simulator-mr-white-test-#{System.unique_integer([:positive])}")
    previous_auth = Application.get_env(:game_simulator, :auth)

    Application.put_env(:game_simulator, :auth,
      data_directory: data_directory,
      legacy_users_file: Path.join(data_directory, "legacy-users"),
      token_ttl_seconds: 86_400
    )

    on_exit(fn ->
      File.rm_rf(data_directory)
      Application.put_env(:game_simulator, :auth, previous_auth)
    end)

    user = "mr-white-#{System.unique_integer([:positive])}"
    assert :ok = Users.add(user, "a-long-test-password", ["mr_white"])
    {:ok, token, _expiration} = Auth.issue_token(user)
    %{token: token}
  end

  test "accepts four, six and eight distinct participants without altering their names", %{token: token} do
    for players <- [
          ["Alice", "Bob", "Chloé", "David"],
          ["Alice", "Bob", "Chloé", "David", "Emma", "Farid"],
          ["Alice", "Bob", "Chloé", "David", "Emma", "Farid", "Gina", "Hugo"]
        ] do
      response = request(token, players)

      assert response.status == 201
      assert %{"players" => public_players} = Poison.decode!(response.resp_body)
      assert Enum.map(public_players, & &1["name"]) == players
    end
  end

  test "rejects counts outside four to eight and case-insensitive duplicate names", %{token: token} do
    for players <- [
          ["Alice", "Bob", "Chloé"],
          ["Alice", "Bob", "Chloé", "David", "Emma", "Farid", "Gina", "Hugo", "Inès"],
          ["Alice", "alice", "Chloé", "David"]
        ] do
      response = request(token, players)

      assert response.status == 422
      assert %{"error" => error} = Poison.decode!(response.resp_body)
      assert error in ["invalid_player_count", "duplicate_name"]
    end
  end

  def request(token, players) do
    conn(:post, "/api/mr-white", %{players: players, spy_count: 1})
    |> put_req_header("authorization", "Bearer #{token}")
    |> then(&Endpoint.call(&1, Endpoint.init([])))
  end
end
