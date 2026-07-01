defmodule GameSimulatorWeb.EndpointTest do
  use ExUnit.Case, async: false

  import Plug.Conn
  import Plug.Test

  alias GameSimulatorWeb.{Auth, Endpoint, Users}

  setup do
    previous_auth = Application.get_env(:game_simulator, :auth)
    data_directory = Path.join(System.tmp_dir!(), "game-simulator-endpoint-test-#{System.unique_integer([:positive])}")

    Application.put_env(:game_simulator, :auth,
      data_directory: data_directory,
      legacy_users_file: Path.join(data_directory, "legacy-users"),
      token_ttl_seconds: 86_400
    )

    on_exit(fn ->
      File.rm_rf(data_directory)
      Application.put_env(:game_simulator, :auth, previous_auth)
    end)

    {:ok, data_directory: data_directory}
  end

  test "authenticates a configured user" do
    user = "test-user-#{System.system_time(:nanosecond)}"
    assert :ok = Users.add(user, "a-long-test-password", ["poker"])

    conn = conn(:post, "/api/auth/login", %{user: user, password: "a-long-test-password"})
    response = Endpoint.call(conn, Endpoint.init([]))

    assert response.status == 200
    assert %{"token" => token, "user" => ^user, "exp" => expiration, "permissions" => ["poker"]} = Poison.decode!(response.resp_body)
    assert is_binary(token)
    assert is_integer(expiration)
  end

  test "rejects invalid login credentials" do
    conn = conn(:post, "/api/auth/login", %{user: "missing", password: "a-long-test-password"})
    response = Endpoint.call(conn, Endpoint.init([]))

    assert response.status == 401
    assert %{"error" => "invalid_credentials"} = Poison.decode!(response.resp_body)
  end

  test "locks login after five failures" do
    assert :ok = Users.add("test-user", "a-long-test-password", ["poker"])

    for _attempt <- 1..4 do
      response = Endpoint.call(conn(:post, "/api/auth/login", %{user: "test-user", password: "wrong-password"}), Endpoint.init([]))
      assert response.status == 401
    end

    response = Endpoint.call(conn(:post, "/api/auth/login", %{user: "test-user", password: "wrong-password"}), Endpoint.init([]))

    assert response.status == 423
    assert %{"error" => "locked", "locked_until" => locked_until} = Poison.decode!(response.resp_body)
    assert is_binary(locked_until)
  end

  test "rejects an authenticated endpoint without a token" do
    response = Endpoint.call(conn(:get, "/api/auth/me"), Endpoint.init([]))

    assert response.status == 401
    assert response.resp_body == "Missing token"
  end

  test "identifies the token user and current permissions" do
    assert :ok = Users.add("test-user", "a-long-test-password", ["admin"])
    {:ok, token, _expiration} = Auth.issue_token("test-user")

    response =
      conn(:get, "/api/auth/me")
      |> put_req_header("authorization", "Bearer #{token}")
      |> then(&Endpoint.call(&1, Endpoint.init([])))

    assert response.status == 200
    assert %{"user" => "test-user", "exp" => expiration, "permissions" => ["admin", "poker", "llm"]} = Poison.decode!(response.resp_body)
    assert is_integer(expiration)
  end

  test "changes the authenticated user's password" do
    assert :ok = Users.add("test-user", "a-long-test-password", ["poker"])
    {:ok, token, _expiration} = Auth.issue_token("test-user")

    response =
      conn(:post, "/api/auth/password", %{current_password: "a-long-test-password", new_password: "a-new-long-password"})
      |> put_req_header("authorization", "Bearer #{token}")
      |> then(&Endpoint.call(&1, Endpoint.init([])))

    assert response.status == 204
    assert {:ok, "test-user"} = Users.authenticate("test-user", "a-new-long-password")
  end

  test "returns explicit password change errors" do
    assert :ok = Users.add("test-user", "a-long-test-password", ["poker"])
    {:ok, token, _expiration} = Auth.issue_token("test-user")

    wrong_current =
      conn(:post, "/api/auth/password", %{current_password: "wrong-password", new_password: "a-new-long-password"})
      |> put_req_header("authorization", "Bearer #{token}")
      |> then(&Endpoint.call(&1, Endpoint.init([])))

    assert wrong_current.status == 422
    assert %{"error" => "invalid_current_password"} = Poison.decode!(wrong_current.resp_body)

    invalid_new =
      conn(:post, "/api/auth/password", %{current_password: "a-long-test-password", new_password: "short"})
      |> put_req_header("authorization", "Bearer #{token}")
      |> then(&Endpoint.call(&1, Endpoint.init([])))

    assert invalid_new.status == 422
    assert %{"error" => "invalid_new_password"} = Poison.decode!(invalid_new.resp_body)
  end

  test "requires admin permission for user management" do
    assert :ok = Users.add("player", "a-long-test-password", ["poker"])
    {:ok, token, _expiration} = Auth.issue_token("player")

    response =
      conn(:get, "/api/admin/users")
      |> put_req_header("authorization", "Bearer #{token}")
      |> then(&Endpoint.call(&1, Endpoint.init([])))

    assert response.status == 403
  end

  test "admin can create and update users" do
    assert :ok = Users.add("admin", "a-long-test-password", ["admin"])
    {:ok, token, _expiration} = Auth.issue_token("admin")

    create_response =
      conn(:post, "/api/admin/users", %{username: "player", password: "a-long-test-password", permissions: ["poker"]})
      |> put_req_header("authorization", "Bearer #{token}")
      |> then(&Endpoint.call(&1, Endpoint.init([])))

    assert create_response.status == 201

    update_response =
      conn(:put, "/api/admin/users/player", %{permissions: ["poker", "llm"], password: "a-new-long-password"})
      |> put_req_header("authorization", "Bearer #{token}")
      |> then(&Endpoint.call(&1, Endpoint.init([])))

    assert update_response.status == 200
    assert {:ok, %{permissions: ["poker", "llm"]}} = Users.get("player")
    assert {:ok, "player"} = Users.authenticate("player", "a-new-long-password")
  end

  test "admin can unlock users" do
    assert :ok = Users.add("admin", "a-long-test-password", ["admin"])
    assert :ok = Users.add("player", "a-long-test-password", ["poker"])
    {:ok, token, _expiration} = Auth.issue_token("admin")

    for _attempt <- 1..5 do
      _ = Users.authenticate("player", "wrong-password")
    end

    assert {:error, {:locked, _locked_until}} = Users.authenticate("player", "a-long-test-password")

    response =
      conn(:put, "/api/admin/users/player", %{permissions: ["poker"], unlock: true})
      |> put_req_header("authorization", "Bearer #{token}")
      |> then(&Endpoint.call(&1, Endpoint.init([])))

    assert response.status == 200
    assert {:ok, "player"} = Users.authenticate("player", "a-long-test-password")
  end

  test "admin cannot remove the last admin permission" do
    assert :ok = Users.add("admin", "a-long-test-password", ["admin"])
    {:ok, token, _expiration} = Auth.issue_token("admin")

    response =
      conn(:put, "/api/admin/users/admin", %{permissions: ["poker"]})
      |> put_req_header("authorization", "Bearer #{token}")
      |> then(&Endpoint.call(&1, Endpoint.init([])))

    assert response.status == 422
    assert %{"error" => "last_admin"} = Poison.decode!(response.resp_body)
  end

  test "creates and returns only the authenticated user's table" do
    user = "table-user-#{System.unique_integer([:positive])}"
    assert :ok = Users.add(user, "a-long-test-password", ["poker"])
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

  test "reports save status and resumes a saved table" do
    user = "save-user-#{System.unique_integer([:positive])}"
    assert :ok = Users.add(user, "a-long-test-password", ["poker"])
    {:ok, token, _expiration} = Auth.issue_token(user)

    no_save =
      conn(:get, "/api/table/save")
      |> put_req_header("authorization", "Bearer #{token}")
      |> then(&Endpoint.call(&1, Endpoint.init([])))

    assert no_save.status == 200
    assert %{"has_save" => false} = Poison.decode!(no_save.resp_body)

    created =
      conn(:post, "/api/table", %{})
      |> put_req_header("authorization", "Bearer #{token}")
      |> then(&Endpoint.call(&1, Endpoint.init([])))

    assert created.status == 201
    assert wait_until(fn -> match?({:ok, true}, GameSimulator.Tables.save_status(user)) end)

    stopped =
      conn(:delete, "/api/table")
      |> put_req_header("authorization", "Bearer #{token}")
      |> then(&Endpoint.call(&1, Endpoint.init([])))

    assert stopped.status == 204

    has_save =
      conn(:get, "/api/table/save")
      |> put_req_header("authorization", "Bearer #{token}")
      |> then(&Endpoint.call(&1, Endpoint.init([])))

    assert has_save.status == 200
    assert %{"has_save" => true} = Poison.decode!(has_save.resp_body)

    resumed =
      conn(:post, "/api/table/resume", %{})
      |> put_req_header("authorization", "Bearer #{token}")
      |> then(&Endpoint.call(&1, Endpoint.init([])))

    assert resumed.status == 200
    assert %{"hand_number" => 1, "players" => players} = Poison.decode!(resumed.resp_body)
    assert length(players) == 6
  end

  test "resume returns 404 without a save and never uses another user's save" do
    assert :ok = Users.add("owner", "a-long-test-password", ["poker"])
    assert :ok = Users.add("other", "a-long-test-password", ["poker"])
    {:ok, owner_token, _expiration} = Auth.issue_token("owner")
    {:ok, other_token, _expiration} = Auth.issue_token("other")

    created =
      conn(:post, "/api/table", %{})
      |> put_req_header("authorization", "Bearer #{owner_token}")
      |> then(&Endpoint.call(&1, Endpoint.init([])))

    assert created.status == 201
    assert wait_until(fn -> match?({:ok, true}, GameSimulator.Tables.save_status("owner")) end)

    missing =
      conn(:post, "/api/table/resume", %{})
      |> put_req_header("authorization", "Bearer #{other_token}")
      |> then(&Endpoint.call(&1, Endpoint.init([])))

    assert missing.status == 404
    assert %{"error" => "save_not_found"} = Poison.decode!(missing.resp_body)
  end

  test "requires poker permission for table endpoints" do
    assert :ok = Users.add("llm-user", "a-long-test-password", ["llm"])
    {:ok, token, _expiration} = Auth.issue_token("llm-user")

    response =
      conn(:post, "/api/table", %{})
      |> put_req_header("authorization", "Bearer #{token}")
      |> then(&Endpoint.call(&1, Endpoint.init([])))

    assert response.status == 403
  end

  test "requires llm permission for coaching" do
    user = "coaching-#{System.unique_integer([:positive])}"
    assert :ok = Users.add(user, "a-long-test-password", ["poker"])
    {:ok, token, _expiration} = Auth.issue_token(user)

    response =
      conn(:post, "/api/llm/coaching", %{})
      |> put_req_header("authorization", "Bearer #{token}")
      |> then(&Endpoint.call(&1, Endpoint.init([])))

    assert response.status == 403
  end

  test "requires llm permission for LLM endpoints" do
    user = "table-export-#{System.unique_integer([:positive])}"
    assert :ok = Users.add(user, "a-long-test-password", ["poker"])
    {:ok, token, _expiration} = Auth.issue_token(user)
    {:ok, _table} = GameSimulator.Tables.start(user)

    response =
      conn(:get, "/api/table/extract?n=5")
      |> put_req_header("authorization", "Bearer #{token}")
      |> then(&Endpoint.call(&1, Endpoint.init([])))

    assert response.status == 403
  end

  test "exports recent hands only for users with llm permission" do
    user = "table-export-#{System.unique_integer([:positive])}"
    assert :ok = Users.add(user, "a-long-test-password", ["poker", "llm"])
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

  test "stops the authenticated user's table" do
    user = "table-exit-#{System.unique_integer([:positive])}"
    assert :ok = Users.add(user, "a-long-test-password", ["poker"])
    {:ok, token, _expiration} = Auth.issue_token(user)
    {:ok, _table} = GameSimulator.Tables.start(user)

    response =
      conn(:delete, "/api/table")
      |> put_req_header("authorization", "Bearer #{token}")
      |> then(&Endpoint.call(&1, Endpoint.init([])))

    assert response.status == 204
    assert :error = GameSimulator.Tables.table(user)
  end

  def wait_until(fun), do: wait_until(fun, 20)

  def wait_until(fun, attempts) when attempts > 0 do
    if fun.() do
      true
    else
      Process.sleep(25)
      wait_until(fun, attempts - 1)
    end
  end

  def wait_until(_fun, 0), do: false
end
