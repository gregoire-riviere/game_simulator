defmodule GameSimulator.Configuration do
  @moduledoc """
  Accessors and startup validation for the runtime application configuration.
  """

  @type server :: %{host: String.t(), port: pos_integer()}
  @type logging :: %{directory: String.t(), console_level: Logger.level()}
  @type auth :: %{data_directory: String.t(), users_file: String.t(), token_ttl_seconds: pos_integer()}
  @type llm :: %{
          enabled: boolean(),
          mode: :off | :shadow | :llm,
          provider: String.t(),
          api_key: String.t() | nil,
          base_url: String.t(),
          decision_model: String.t(),
          timeout_ms: pos_integer(),
          audit_file: String.t(),
          http_referer: String.t() | nil,
          x_title: String.t(),
          interest_threshold: pos_integer(),
          client: module()
        }

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
    # La clé reste facultative tant que le shadow mode LLM n'est pas activé.
    Application.fetch_env!(:game_simulator, :llm)
    |> Keyword.fetch!(:api_key)
  end

  @spec llm!() :: llm()
  def llm! do
    config = Application.fetch_env!(:game_simulator, :llm)
    enabled = Keyword.get(config, :enabled, false)
    shadow_mode = Keyword.get(config, :shadow_mode, true)
    mode = Keyword.get(config, :mode, if(shadow_mode, do: :shadow, else: :off))
    provider = Keyword.get(config, :provider, "openrouter")
    api_key = Keyword.get(config, :api_key)
    base_url = Keyword.get(config, :base_url, "https://openrouter.ai/api/v1")
    decision_model = Keyword.get(config, :decision_model, "google/gemini-2.5-flash")
    timeout_ms = Keyword.get(config, :timeout_ms, 1_500)
    audit_file = Keyword.get(config, :audit_file, "data/llm_shadow_audit.ndjson")
    http_referer = Keyword.get(config, :http_referer)
    x_title = Keyword.get(config, :x_title, "game_simulator")
    interest_threshold = Keyword.get(config, :interest_threshold, 4)
    client = Keyword.get(config, :client, Poker.Decision.LLMShadow)

    unless is_boolean(enabled) and is_boolean(shadow_mode) and mode in [:off, :shadow, :llm] do
      raise ArgumentError, "game_simulator llm enabled/shadow_mode/mode configuration is invalid"
    end

    unless provider == "openrouter" do
      raise ArgumentError, "game_simulator llm provider must be openrouter"
    end

    if enabled and (not is_binary(api_key) or api_key == "") do
      raise ArgumentError, "game_simulator llm api key must be configured when LLM is enabled"
    end

    unless is_binary(base_url) and String.starts_with?(base_url, "https://") do
      raise ArgumentError, "game_simulator llm base_url must be a non-empty https URL"
    end

    unless is_binary(decision_model) and decision_model != "" do
      raise ArgumentError, "game_simulator llm decision_model must be a non-empty string"
    end

    unless is_integer(timeout_ms) and timeout_ms > 0 do
      raise ArgumentError, "game_simulator llm timeout_ms must be greater than zero"
    end

    unless is_binary(audit_file) and audit_file != "" do
      raise ArgumentError, "game_simulator llm audit_file must be a non-empty string"
    end

    unless is_integer(interest_threshold) and interest_threshold > 0 do
      raise ArgumentError, "game_simulator llm interest_threshold must be greater than zero"
    end

    %{
      enabled: enabled,
      shadow_mode: shadow_mode,
      mode: mode,
      provider: provider,
      api_key: api_key,
      base_url: base_url,
      decision_model: decision_model,
      timeout_ms: timeout_ms,
      audit_file: audit_file,
      http_referer: http_referer,
      x_title: x_title,
      interest_threshold: interest_threshold,
      client: client
    }
  end

  @spec validate!() :: :ok
  def validate! do
    _ = server!()
    _ = logging!()
    _ = auth!()
    _ = llm!()
    :ok
  end
end
