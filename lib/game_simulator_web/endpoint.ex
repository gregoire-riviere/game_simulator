defmodule GameSimulatorWeb.Endpoint do
  @moduledoc """
  HTTP endpoint for the client application and its JSON authentication contract.

  Static pages are served by `HTMLHandler.Plug.OutputStatic`; SSR is deliberately
  not part of this pipeline.
  """

  use Plug.Router

  alias GameSimulatorWeb.Auth

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
    not_implemented(conn, "login")
  end

  post "/api/auth/refresh" do
    not_implemented(conn, "token refresh")
  end

  post "/api/auth/logout" do
    not_implemented(conn, "logout")
  end

  get "/api/auth/me" do
    conn = Auth.verify(conn)

    if conn.halted do
      conn
    else
      send_json(conn, 200, %{user: conn.assigns.token_user, exp: conn.assigns.token_exp})
    end
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

  defp static_directory do
    Application.app_dir(:game_simulator, "priv/static")
  end

  defp not_implemented(conn, feature) do
    send_json(conn, 501, %{
      error: "not_implemented",
      message: "Authentication #{feature} is not configured yet"
    })
  end

  defp send_json(conn, status, body) do
    conn
    |> Plug.Conn.put_resp_content_type("application/json")
    |> Plug.Conn.send_resp(status, Poison.encode!(body))
  end
end
