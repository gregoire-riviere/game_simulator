defmodule GameSimulatorWeb.RootEndpoint do
  @moduledoc """
  Routeur léger qui isole l'API de belote en ligne de l'endpoint historique.
  """

  use Plug.Router

  plug(:match)
  plug(:dispatch)

  forward "/api/belote-online", to: GameSimulatorWeb.BeloteOnlineEndpoint

  match _ do
    GameSimulatorWeb.Endpoint.call(conn, [])
  end
end
