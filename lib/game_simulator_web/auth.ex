defmodule GameSimulatorWeb.Auth do
  @moduledoc """
  Token helpers used by authenticated HTTP endpoints.

  Token issuance is intentionally kept server-side: call `issue_token/1` only
  after a future credential provider has authenticated the user.
  """

  alias GameSimulator.Configuration

  @spec issue_token(String.t()) :: {:ok, String.t(), integer()}
  def issue_token(user) when is_binary(user) and byte_size(user) > 0 do
    # La clé de signature vit dans le répertoire de données, pas dans le code source.
    %{data_directory: data_directory, token_ttl_seconds: ttl} = Configuration.auth!()
    HTMLHandler.Token.issue(user, ttl, data_dir: data_directory)
  end

  @spec verify(Plug.Conn.t()) :: Plug.Conn.t()
  def verify(conn) do
    # Le plug rejette la requête avant toute action si le token est absent ou invalide.
    %{data_directory: data_directory} = Configuration.auth!()

    HTMLHandler.Plug.Token.call(conn,
      required: true,
      data_dir: data_directory
    )
  end
end
