defmodule GameSimulatorWeb.EndpointTest do
  use ExUnit.Case, async: true

  import Plug.Conn
  import Plug.Test

  alias GameSimulatorWeb.{Auth, Endpoint}

  test "returns an authentication contract for login" do
    conn = conn(:post, "/api/auth/login", %{email: "user@example.com", password: "secret"})
    response = Endpoint.call(conn, Endpoint.init([]))

    assert response.status == 501
    assert %{"error" => "not_implemented"} = Poison.decode!(response.resp_body)
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
end
