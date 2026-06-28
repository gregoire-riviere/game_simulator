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
         {:ok, token, expiration} <- Auth.issue_token(user) do
      send_json(conn, 200, %{token: token, user: user, exp: expiration})
    else
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
    conn = Auth.verify(conn)

    if conn.halted do
      conn
    else
      send_json(conn, 200, %{user: conn.assigns.token_user, exp: conn.assigns.token_exp})
    end
  end


  get "/api/llm/credits" do
    authenticated(conn, fn conn, _user ->
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

  post "/api/table" do
    # Une seule table temporaire est associée à chaque utilisateur authentifié.
    authenticated(conn, fn conn, user ->
      with {:ok, table} <- GameSimulator.Tables.start(user),
           {:ok, state} <- GameSimulator.Table.state(table, user) do
        send_json(conn, 201, state)
      else
        {:error, reason} -> table_error(conn, reason)
      end
    end)
  end

  get "/api/table" do
    authenticated(conn, fn conn, user ->
      case GameSimulator.Tables.table(user) do
        {:ok, table} ->
          case GameSimulator.Table.state(table, user) do
            {:ok, state} -> send_json(conn, 200, state)
            {:error, reason} -> table_error(conn, reason)
          end

        :error -> send_json(conn, 404, %{error: "table_not_found"})
      end
    end)
  end

  get "/api/table/extract" do
    authenticated(conn, fn conn, user ->
      conn = Plug.Conn.fetch_query_params(conn)

      with {:ok, table} <- table_for(user),
           {:ok, count} <- parse_count(conn.query_params["n"]),
           {:ok, extract} <- GameSimulator.Table.extract(table, user, count) do
        send_json(conn, 200, extract)
      else
        {:error, reason} -> table_error(conn, reason)
      end
    end)
  end

  post "/api/table/action" do
    # Les montants bruts du navigateur sont toujours revalidés par `Poker.Game`.
    authenticated(conn, fn conn, user ->
      with {:ok, table} <- table_for(user),
           {:ok, action} <- parse_action(conn.body_params),
           {:ok, state} <- GameSimulator.Table.act(table, user, action) do
        send_json(conn, 200, state)
      else
        {:error, reason} -> table_error(conn, reason)
      end
    end)
  end

  post "/api/table/advance-bot" do
    authenticated(conn, fn conn, user ->
      with {:ok, table} <- table_for(user),
           {:ok, state} <- GameSimulator.Table.advance_bot(table, user) do
        send_json(conn, 200, state)
      else
        {:error, reason} -> table_error(conn, reason)
      end
    end)
  end

  post "/api/table/next-hand" do
    authenticated(conn, fn conn, user ->
      with {:ok, table} <- table_for(user),
           {:ok, state} <- GameSimulator.Table.next_hand(table, user) do
        send_json(conn, 200, state)
      else
        {:error, reason} -> table_error(conn, reason)
      end
    end)
  end

  post "/api/table/llm-mode" do
    authenticated(conn, fn conn, user ->
      with {:ok, table} <- table_for(user),
           {:ok, mode} <- parse_llm_mode(conn.body_params["mode"]),
           {:ok, state} <- GameSimulator.Table.set_llm_mode(table, user, mode) do
        send_json(conn, 200, state)
      else
        {:error, reason} -> table_error(conn, reason)
      end
    end)
  end

  delete "/api/table" do
    authenticated(conn, fn conn, user ->
      case GameSimulator.Tables.stop(user) do
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

  def authenticated(conn, fun) do
    # Aucun endpoint de table ne fait confiance à un identifiant fourni par le navigateur.
    conn = Auth.verify(conn)
    if conn.halted, do: conn, else: fun.(conn, conn.assigns.token_user)
  end

  def table_for(user) do
    case GameSimulator.Tables.table(user) do
      {:ok, table} -> {:ok, table}
      :error -> {:error, :table_not_found}
    end
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

  def table_error(conn, :table_not_found), do: send_json(conn, 404, %{error: "table_not_found"})
  def table_error(conn, :forbidden), do: send_json(conn, 403, %{error: "forbidden"})
  def table_error(conn, reason), do: send_json(conn, 422, %{error: Atom.to_string(reason)})
end
