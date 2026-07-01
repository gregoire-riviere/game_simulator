defmodule GameSimulatorWeb.Endpoint do
  @moduledoc """
  HTTP endpoint for the client application and its JSON authentication contract.

  Static pages are served by `HTMLHandler.Plug.OutputStatic`; SSR is deliberately
  not part of this pipeline.
  """

  use Plug.Router

  alias GameSimulatorWeb.{Auth, Users}

  plug(Plug.Logger)

  plug(Plug.Parsers,
    parsers: [:urlencoded, :multipart, :json],
    pass: ["application/json"],
    json_decoder: Poison
  )

  plug(:match)
  plug(:dispatch)

  post "/api/auth/register" do
    not_implemented(conn, "registration")
  end

  post "/api/auth/login" do
    # Le mot de passe n'est jamais transformé en token avant authentification locale.
    user = conn.body_params["user"]
    password = conn.body_params["password"]

    with {:ok, user} <- Users.authenticate(user, password),
         {:ok, account} <- Users.get(user),
         {:ok, token, expiration} <- Auth.issue_token(user) do
      send_json(conn, 200, %{token: token, user: user, exp: expiration, permissions: Users.effective_permissions(account.permissions)})
    else
      {:error, {:locked, locked_until}} -> send_json(conn, 423, %{error: "locked", locked_until: locked_until})
      {:error, :invalid_credentials} -> send_json(conn, 401, %{error: "invalid_credentials"})
      {:error, _reason} -> send_json(conn, 500, %{error: "authentication_unavailable"})
    end
  end

  post "/api/auth/refresh" do
    not_implemented(conn, "token refresh")
  end

  post "/api/auth/logout" do
    # Le token est stateless : le navigateur le supprime après cette réponse sans contenu.
    Plug.Conn.send_resp(conn, 204, "")
  end

  get "/api/auth/me" do
    authenticated(conn, :any, fn conn, account ->
      send_json(conn, 200, %{
        user: account.username,
        exp: conn.assigns.token_exp,
        permissions: account.effective_permissions
      })
    end)
  end

  post "/api/auth/password" do
    authenticated(conn, :any, fn conn, account ->
      case Users.change_password(account.username, conn.body_params["current_password"], conn.body_params["new_password"]) do
        :ok -> Plug.Conn.send_resp(conn, 204, "")
        {:error, :invalid_credentials} -> send_json(conn, 422, %{error: "invalid_credentials"})
        {:error, :missing_current_password} -> send_json(conn, 422, %{error: "missing_current_password"})
        {:error, :missing_new_password} -> send_json(conn, 422, %{error: "missing_new_password"})
        {:error, :invalid_new_password} -> send_json(conn, 422, %{error: "invalid_new_password"})
        {:error, :invalid_current_password} -> send_json(conn, 422, %{error: "invalid_current_password"})
        {:error, _reason} -> send_json(conn, 500, %{error: "password_update_failed"})
      end
    end)
  end

  get "/api/admin/users" do
    authenticated(conn, "admin", fn conn, _account ->
      case Users.list() do
        {:ok, users} -> send_json(conn, 200, %{users: Enum.map(users, &Users.public_user/1)})
        {:error, _reason} -> send_json(conn, 500, %{error: "users_unavailable"})
      end
    end)
  end

  post "/api/admin/users" do
    authenticated(conn, "admin", fn conn, _account ->
      with {:ok, permissions} <- parse_permissions(conn.body_params["permissions"]),
           :ok <- Users.create(conn.body_params["username"], conn.body_params["password"], permissions) do
        send_json(conn, 201, %{ok: true})
      else
        {:error, reason} -> user_error(conn, reason)
      end
    end)
  end

  put "/api/admin/users/:user" do
    authenticated(conn, "admin", fn conn, _account ->
      with {:ok, permissions} <- parse_permissions(conn.body_params["permissions"]),
           :ok <- Users.update(user, permissions),
           :ok <- maybe_admin_reset_password(user, conn.body_params["password"]),
           :ok <- maybe_unlock_user(user, conn.body_params["unlock"]) do
        send_json(conn, 200, %{ok: true})
      else
        {:error, reason} -> user_error(conn, reason)
      end
    end)
  end

  delete "/api/admin/users/:user" do
    authenticated(conn, "admin", fn conn, _account ->
      case Users.delete(user) do
        :ok -> Plug.Conn.send_resp(conn, 204, "")
        {:error, reason} -> user_error(conn, reason)
      end
    end)
  end


  get "/api/llm/credits" do
    authenticated(conn, "llm", fn conn, _account ->
      config = GameSimulator.Configuration.llm!()

      cond do
        not config.enabled ->
          send_json(conn, 200, %{available: false})

        config.provider == "openrouter" ->
          case Poker.Decision.LLMShadow.credits(config) do
            {:ok, credits} -> send_json(conn, 200, Map.put(credits, :available, true))
            {:error, _reason} -> send_json(conn, 200, %{available: true, error: "unavailable"})
          end
      end
    end)
  end

  get "/api/table/save" do
    authenticated(conn, "poker", fn conn, account ->
      case GameSimulator.Tables.save_status(account.username) do
        {:ok, has_save} -> send_json(conn, 200, %{has_save: has_save})
        {:error, _reason} -> send_json(conn, 500, %{error: "save_status_unavailable"})
      end
    end)
  end

  post "/api/table" do
    # Nouvelle partie : la sauvegarde unique sera écrasée par le premier snapshot.
    authenticated(conn, "poker", fn conn, account ->
      with {:ok, table} <- GameSimulator.Tables.start_new(account.username),
           {:ok, state} <- GameSimulator.Table.state(table, account.username) do
        send_table_json(conn, 201, state, account)
      else
        {:error, reason} -> table_error(conn, reason)
      end
    end)
  end

  post "/api/table/resume" do
    authenticated(conn, "poker", fn conn, account ->
      with {:ok, table} <- GameSimulator.Tables.resume(account.username),
           {:ok, state} <- GameSimulator.Table.state(table, account.username) do
        send_table_json(conn, 200, state, account)
      else
        {:error, :not_found} -> send_json(conn, 404, %{error: "save_not_found"})
        {:error, reason} -> table_error(conn, reason)
      end
    end)
  end

  get "/api/table" do
    authenticated(conn, "poker", fn conn, account ->
      case GameSimulator.Tables.table(account.username) do
        {:ok, table} ->
          case GameSimulator.Table.state(table, account.username) do
            {:ok, state} -> send_table_json(conn, 200, state, account)
            {:error, reason} -> table_error(conn, reason)
          end

        :error -> send_json(conn, 404, %{error: "table_not_found"})
      end
    end)
  end

  get "/api/table/extract" do
    authenticated(conn, "llm", fn conn, account ->
      conn = Plug.Conn.fetch_query_params(conn)

      with {:ok, table} <- table_for(account.username),
           {:ok, count} <- parse_count(conn.query_params["n"]),
           {:ok, extract} <- GameSimulator.Table.extract(table, account.username, count) do
        send_json(conn, 200, extract)
      else
        {:error, reason} -> table_error(conn, reason)
      end
    end)
  end

  post "/api/table/action" do
    # Les montants bruts du navigateur sont toujours revalidés par `Poker.Game`.
    authenticated(conn, "poker", fn conn, account ->
      with {:ok, table} <- table_for(account.username),
           {:ok, action} <- parse_action(conn.body_params),
           {:ok, state} <- GameSimulator.Table.act(table, account.username, action) do
        send_table_json(conn, 200, state, account)
      else
        {:error, reason} -> table_error(conn, reason)
      end
    end)
  end

  post "/api/table/advance-bot" do
    authenticated(conn, "poker", fn conn, account ->
      with {:ok, table} <- table_for(account.username),
           {:ok, state} <- GameSimulator.Table.advance_bot(table, account.username) do
        send_table_json(conn, 200, state, account)
      else
        {:error, reason} -> table_error(conn, reason)
      end
    end)
  end

  post "/api/table/next-hand" do
    authenticated(conn, "poker", fn conn, account ->
      with {:ok, table} <- table_for(account.username),
           {:ok, state} <- GameSimulator.Table.next_hand(table, account.username) do
        send_table_json(conn, 200, state, account)
      else
        {:error, reason} -> table_error(conn, reason)
      end
    end)
  end

  post "/api/table/llm-mode" do
    authenticated(conn, "llm", fn conn, account ->
      with {:ok, table} <- table_for(account.username),
           {:ok, mode} <- parse_llm_mode(conn.body_params["mode"]),
           {:ok, state} <- GameSimulator.Table.set_llm_mode(table, account.username, mode) do
        send_table_json(conn, 200, state, account)
      else
        {:error, reason} -> table_error(conn, reason)
      end
    end)
  end

  delete "/api/table" do
    authenticated(conn, "poker", fn conn, account ->
      case GameSimulator.Tables.stop(account.username) do
        :ok -> Plug.Conn.send_resp(conn, 204, "")
        {:error, _reason} -> send_json(conn, 500, %{error: "table_stop_failed"})
      end
    end)
  end

  match "/api/*path" do
    send_json(conn, 404, %{error: "not_found"})
  end

  match _ do
    HTMLHandler.Plug.OutputStatic.call(conn,
      output: static_directory(),
      routes: %{"/" => "index.html"},
      token_api: false
    )
  end

  def static_directory do
    Application.app_dir(:game_simulator, "priv/static")
  end

  def not_implemented(conn, feature) do
    send_json(conn, 501, %{
      error: "not_implemented",
      message: "Authentication #{feature} is not configured yet"
    })
  end

  def send_json(conn, status, body) do
    conn
    |> Plug.Conn.put_resp_content_type("application/json")
    |> Plug.Conn.send_resp(status, Poison.encode!(body))
  end

  def send_table_json(conn, status, state, account) do
    send_json(conn, status, scrub_llm(state, account))
  end

  def authenticated(conn, permission, fun) do
    # Aucun endpoint protégé ne fait confiance aux droits contenus côté navigateur.
    conn = Auth.verify(conn)

    if conn.halted do
      conn
    else
      case Users.get(conn.assigns.token_user) do
        {:ok, account} ->
          account = Map.put(account, :effective_permissions, Users.effective_permissions(account.permissions))

          if permission == :any or permission in account.effective_permissions do
            fun.(conn, account)
          else
            send_json(conn, 403, %{error: "forbidden"})
          end

        {:error, _reason} ->
          send_json(conn, 401, %{error: "invalid_credentials"})
      end
    end
  end

  def table_for(user) do
    case GameSimulator.Tables.table(user) do
      {:ok, table} -> {:ok, table}
      :error -> {:error, :table_not_found}
    end
  end

  def scrub_llm(state, account) do
    if "llm" in account.effective_permissions do
      state
    else
      state
      |> Map.put(:llm_available, false)
      |> Map.put(:llm_mode, :off)
      |> Map.update(:recent_actions, [], fn actions -> Enum.map(actions, &scrub_llm_action/1) end)
      |> Map.update(:hand_actions, [], fn actions -> Enum.map(actions, &scrub_llm_action/1) end)
    end
  end

  def scrub_llm_action(action) do
    action
    |> Map.delete(:llm_shadow)
    |> Map.delete(:llm_applied)
    |> Map.delete(:played_action)
  end

  def parse_action(%{"action" => action}) when action in ["fold", "check", "call", "all_in"] do
    {:ok, String.to_existing_atom(action)}
  end

  def parse_action(%{"action" => "bet", "amount" => amount}) when is_integer(amount) and amount > 0, do: {:ok, {:bet, amount}}
  def parse_action(%{"action" => "raise_to", "amount" => amount}) when is_integer(amount) and amount > 0, do: {:ok, {:raise_to, amount}}
  def parse_action(_params), do: {:error, :invalid_action}

  def parse_count(nil), do: {:ok, 10}

  def parse_count(value) when is_binary(value) do
    case Integer.parse(value) do
      {count, ""} when count in 1..50 -> {:ok, count}
      _other -> {:error, :invalid_extract_count}
    end
  end

  def parse_count(_value), do: {:error, :invalid_extract_count}

  def parse_llm_mode("llm"), do: {:ok, :llm}
  def parse_llm_mode("shadow"), do: {:ok, :shadow}
  def parse_llm_mode("off"), do: {:ok, :off}
  def parse_llm_mode(_value), do: {:error, :invalid_llm_mode}

  def parse_permissions(permissions), do: Users.validate_permissions(permissions)

  def maybe_admin_reset_password(_user, password) when password in [nil, ""], do: :ok
  def maybe_admin_reset_password(user, password), do: Users.admin_reset_password(user, password)

  def maybe_unlock_user(user, true), do: Users.unlock(user)
  def maybe_unlock_user(_user, _unlock), do: :ok

  def table_error(conn, :table_not_found), do: send_json(conn, 404, %{error: "table_not_found"})
  def table_error(conn, :forbidden), do: send_json(conn, 403, %{error: "forbidden"})
  def table_error(conn, reason), do: send_json(conn, 422, %{error: Atom.to_string(reason)})

  def user_error(conn, :already_exists), do: send_json(conn, 409, %{error: "already_exists"})
  def user_error(conn, :not_found), do: send_json(conn, 404, %{error: "not_found"})
  def user_error(conn, :last_admin), do: send_json(conn, 422, %{error: "last_admin"})
  def user_error(conn, :invalid_permissions), do: send_json(conn, 422, %{error: "invalid_permissions"})
  def user_error(conn, :invalid_credentials), do: send_json(conn, 422, %{error: "invalid_credentials"})
  def user_error(conn, _reason), do: send_json(conn, 500, %{error: "users_unavailable"})
end
