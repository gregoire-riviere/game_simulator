defmodule GameSimulatorWeb.EndpointTest do
  use ExUnit.Case, async: true

  import Plug.Conn
  import Plug.Test

  alias GameSimulatorWeb.{Auth, Endpoint, Users}

  test "authenticates a configured user" do
    user = "test-user-#{System.system_time(:nanosecond)}"
    assert :ok = Users.add(user, "a-long-test-password")

    conn = conn(:post, "/api/auth/login", %{user: user, password: "a-long-test-password"})
    response = Endpoint.call(conn, Endpoint.init([]))

    assert response.status == 200
    assert %{"token" => token, "user" => ^user, "exp" => expiration} = Poison.decode!(response.resp_body)
    assert is_binary(token)
    assert is_integer(expiration)
  end

  test "rejects invalid login credentials" do
    conn = conn(:post, "/api/auth/login", %{user: "missing", password: "a-long-test-password"})
    response = Endpoint.call(conn, Endpoint.init([]))

    assert response.status == 401
    assert %{"error" => "invalid_credentials"} = Poison.decode!(response.resp_body)
  end

  test "rejects an authenticated endpoint without a token" do
    response = Endpoint.call(conn(:get, "/api/auth/me"), Endpoint.init([]))

    assert response.status == 401
    assert response.resp_body == "Missing token"
  end

  test "identifies the token user on an authenticated endpoint" do
    {:ok, token, _expiration} = Auth.issue_token("test-user")

    response =
      conn(:get, "/api/auth/me")
      |> put_req_header("authorization", "Bearer #{token}")
      |> then(&Endpoint.call(&1, Endpoint.init([])))

    assert response.status == 200
    assert %{"user" => "test-user", "exp" => expiration} = Poison.decode!(response.resp_body)
    assert is_integer(expiration)
  end

  test "creates and returns only the authenticated user's table" do
    user = "table-user-#{System.unique_integer([:positive])}"
    {:ok, token, _expiration} = Auth.issue_token(user)

    response =
      conn(:post, "/api/table", %{})
      |> put_req_header("authorization", "Bearer #{token}")
      |> then(&Endpoint.call(&1, Endpoint.init([])))

    assert response.status == 201
    assert %{"players" => players} = Poison.decode!(response.resp_body)
    assert length(players) == 6
    assert Enum.all?(Enum.reject(players, &(&1["id"] == "hero")), &(&1["cards"] == "hidden"))
  end

  test "stops the authenticated user's table" do
    user = "table-exit-#{System.unique_integer([:positive])}"
    {:ok, token, _expiration} = Auth.issue_token(user)
    {:ok, _table} = GameSimulator.Tables.start(user)

    response =
      conn(:delete, "/api/table")
      |> put_req_header("authorization", "Bearer #{token}")
      |> then(&Endpoint.call(&1, Endpoint.init([])))

    assert response.status == 204
    assert :error = GameSimulator.Tables.table(user)
  end

  test "exports recent hands only for the authenticated user's table" do
    user = "table-export-#{System.unique_integer([:positive])}"
    {:ok, token, _expiration} = Auth.issue_token(user)
    {:ok, _table} = GameSimulator.Tables.start(user)

    response =
      conn(:get, "/api/table/extract?n=5")
      |> put_req_header("authorization", "Bearer #{token}")
      |> then(&Endpoint.call(&1, Endpoint.init([])))

    assert response.status == 200
    assert %{"count" => 0, "format" => "markdown", "text" => text} = Poison.decode!(response.resp_body)
    assert text =~ "Export table NL2"
  end
end
