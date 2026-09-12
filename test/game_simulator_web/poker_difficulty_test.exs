defmodule GameSimulatorWeb.PokerDifficultyTest do
  use ExUnit.Case, async: false

  import Plug.Conn
  import Plug.Test

  alias GameSimulatorWeb.{Auth, Endpoint, Users}

  setup do
    data_directory = Path.join(System.tmp_dir!(), "game-simulator-difficulty-test-#{System.unique_integer([:positive])}")
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

    user = "difficulty-#{System.unique_integer([:positive])}"
    assert :ok = Users.add(user, "a-long-test-password", ["poker"])
    {:ok, token, _expiration} = Auth.issue_token(user)
    %{token: token}
  end

  test "creates a standard table by default and exposes the selected table difficulty", %{token: token} do
    standard = request(token, %{})
    assert standard.status == 201
    assert %{"difficulty" => "standard", "blinds" => blinds, "players" => players} = Poison.decode!(standard.resp_body)

    cautious = request(token, %{difficulty: "cautious"})
    assert cautious.status == 201
    assert %{"difficulty" => "cautious", "blinds" => ^blinds, "players" => cautious_players} = Poison.decode!(cautious.resp_body)
    assert Enum.map(cautious_players, & &1["stack"]) == Enum.map(players, & &1["stack"])
  end

  test "rejects an unknown difficulty explicitly", %{token: token} do
    response = request(token, %{difficulty: "impossible"})

    assert response.status == 422
    assert %{"error" => "invalid_difficulty"} = Poison.decode!(response.resp_body)
  end

  def request(token, body) do
    conn(:post, "/api/table", body)
    |> put_req_header("authorization", "Bearer #{token}")
    |> then(&Endpoint.call(&1, Endpoint.init([])))
  end
end
