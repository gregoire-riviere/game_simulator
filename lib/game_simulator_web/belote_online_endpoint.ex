defmodule GameSimulatorWeb.BeloteOnlineEndpoint do
  @moduledoc """
  API HTTP des salons de belote en ligne.
  """

  use Plug.Router

  plug(Plug.Parsers,
    parsers: [:urlencoded, :multipart, :json],
    pass: ["application/json"],
    json_decoder: Poison
  )

  plug(:match)
  plug(:dispatch)

  post "/create" do
    authenticated(conn, fn conn, account ->
      with {:ok, game_key} <- GameSimulatorWeb.Endpoint.parse_belote_game_key(conn.body_params["game_key"]),
           {:ok, target_score} <- GameSimulatorWeb.Endpoint.parse_belote_target(conn.body_params["target_score"]),
           {:ok, state} <- Belote.Online.create(account.username, game_key, target_score) do
        send_json(conn, 201, state)
      else
        {:error, reason} -> error(conn, reason)
      end
    end)
  end

  post "/join" do
    authenticated(conn, fn conn, account ->
      case Belote.Online.join(account.username, conn.body_params["code"]) do
        {:ok, state} -> send_json(conn, 200, state)
        {:error, reason} -> error(conn, reason)
      end
    end)
  end

  get "/state" do
    authenticated(conn, fn conn, account ->
      case Belote.Online.state(account.username) do
        {:ok, state} -> send_json(conn, 200, state)
        {:error, reason} -> error(conn, reason)
      end
    end)
  end

  post "/start" do
    authenticated(conn, fn conn, account ->
      case Belote.Online.start_game(account.username) do
        {:ok, state} -> send_json(conn, 200, state)
        {:error, reason} -> error(conn, reason)
      end
    end)
  end

  post "/action" do
    authenticated(conn, fn conn, account ->
      with {:ok, action} <- GameSimulatorWeb.Endpoint.parse_belote_action(conn.body_params),
           {:ok, state} <- Belote.Online.act(account.username, action) do
        send_json(conn, 200, state)
      else
        {:error, reason} -> error(conn, reason)
      end
    end)
  end

  post "/next-deal" do
    authenticated(conn, fn conn, account ->
      case Belote.Online.next_deal(account.username) do
        {:ok, state} -> send_json(conn, 200, state)
        {:error, reason} -> error(conn, reason)
      end
    end)
  end

  delete "/leave" do
    authenticated(conn, fn conn, account ->
      :ok = Belote.Online.leave(account.username)
      Plug.Conn.send_resp(conn, 204, "")
    end)
  end

  match _ do
    send_json(conn, 404, %{error: "not_found"})
  end

  def authenticated(conn, fun), do: GameSimulatorWeb.Endpoint.authenticated(conn, "belote", fun)
  def send_json(conn, status, body), do: GameSimulatorWeb.Endpoint.send_json(conn, status, body)

  def error(conn, :lobby_not_found), do: send_json(conn, 404, %{error: "lobby_not_found"})
  def error(conn, :forbidden), do: send_json(conn, 403, %{error: "forbidden"})
  def error(conn, :host_required), do: send_json(conn, 403, %{error: "host_required"})
  def error(conn, reason), do: send_json(conn, 422, %{error: Atom.to_string(reason)})
end
