defmodule GameSimulator.Configuration do
  @moduledoc """
  Accessors and startup validation for the runtime application configuration.
  """

  @type server :: %{host: String.t(), port: pos_integer()}
  @type logging :: %{directory: String.t(), console_level: Logger.level()}
  @type auth :: %{data_directory: String.t(), users_file: String.t(), token_ttl_seconds: pos_integer()}

  @spec server!() :: server()
  def server! do
    # La configuration est validée tôt pour échouer clairement au démarrage.
    config = Application.fetch_env!(:game_simulator, :server)
    host = Keyword.fetch!(config, :host)
    port = Keyword.fetch!(config, :port)

    unless is_binary(host) and host != "" do
      raise ArgumentError, "game_simulator server host must be a non-empty string"
    end

    unless is_integer(port) and port in 1..65_535 do
      raise ArgumentError, "game_simulator server port must be between 1 and 65535"
    end

    %{host: host, port: port}
  end

  @spec logging!() :: logging()
  def logging! do
    config = Application.fetch_env!(:game_simulator, :logging)
    directory = Keyword.fetch!(config, :directory)
    console_level = Keyword.fetch!(config, :console_level)

    unless is_binary(directory) and directory != "" do
      raise ArgumentError, "game_simulator log directory must be a non-empty string"
    end

    unless console_level in [:debug, :info, :warning, :error] do
      raise ArgumentError, "game_simulator console log level is invalid"
    end

    %{directory: directory, console_level: console_level}
  end

  @spec auth!() :: auth()
  def auth! do
    config = Application.fetch_env!(:game_simulator, :auth)
    data_directory = Keyword.fetch!(config, :data_directory)
    users_file = Keyword.fetch!(config, :users_file)
    token_ttl_seconds = Keyword.fetch!(config, :token_ttl_seconds)

    unless is_binary(data_directory) and data_directory != "" do
      raise ArgumentError, "game_simulator auth data directory must be a non-empty string"
    end

    unless is_binary(users_file) and users_file != "" do
      raise ArgumentError, "game_simulator auth users file must be a non-empty string"
    end

    unless is_integer(token_ttl_seconds) and token_ttl_seconds > 0 do
      raise ArgumentError, "game_simulator token TTL must be greater than zero"
    end

    %{data_directory: data_directory, users_file: users_file, token_ttl_seconds: token_ttl_seconds}
  end

  @spec http_server?() :: boolean()
  def http_server? do
    Application.fetch_env!(:game_simulator, :start_http?)
  end

  @spec llm_api_key() :: String.t() | nil
  def llm_api_key do
    # La clé est facultative en V1 : le moteur local ne fait aucun appel LLM.
    Application.fetch_env!(:game_simulator, :llm)
    |> Keyword.fetch!(:api_key)
  end

  @spec validate!() :: :ok
  def validate! do
    _ = server!()
    _ = logging!()
    _ = auth!()
    :ok
  end
end
