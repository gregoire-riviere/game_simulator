import Config
import Dotenvy

# Les variables système priment sur le fichier dotenv, pour les déploiements et secrets.
environment = config_env()
release_root = System.get_env("RELEASE_ROOT") || File.cwd!()

default_env_file =
  case environment do
    :test -> Path.join(File.cwd!(), ".env.test")
    :prod -> Path.join(release_root, ".env")
    _ -> Path.join(File.cwd!(), ".env")
  end

env_file = System.get_env("GAME_SIMULATOR_ENV_FILE") || default_env_file

source!([env_file, System.get_env()])

default_host = if environment == :prod, do: "0.0.0.0", else: "127.0.0.1"
host = env!("GAME_SIMULATOR_HOST", :string!, default_host)
port = env!("GAME_SIMULATOR_PORT", :integer, 4000)

unless port in 1..65_535 do
  raise ArgumentError, "GAME_SIMULATOR_PORT must be between 1 and 65535, got: #{inspect(port)}"
end

console_log_level =
  case env!("GAME_SIMULATOR_LOG_LEVEL", :string, "debug") |> String.downcase() do
    "debug" ->
      :debug

    "info" ->
      :info

    "warning" ->
      :warning

    "error" ->
      :error

    value ->
      raise ArgumentError,
            "GAME_SIMULATOR_LOG_LEVEL must be debug, info, warning, or error, got: #{inspect(value)}"
  end

default_log_dir =
  if environment == :test do
    Path.join(System.tmp_dir!(), "game_simulator-test")
  else
    Path.join(release_root, "log")
  end

log_dir = env!("GAME_SIMULATOR_LOG_DIR", :string!, default_log_dir)

log_dir =
  if Path.type(log_dir) == :relative, do: Path.expand(log_dir, release_root), else: log_dir

default_data_dir =
  if environment == :test do
    Path.join(System.tmp_dir!(), "game_simulator-test-data")
  else
    Path.join(release_root, "data")
  end

data_dir = env!("GAME_SIMULATOR_DATA_DIR", :string!, default_data_dir)

data_dir =
  if Path.type(data_dir) == :relative, do: Path.expand(data_dir, release_root), else: data_dir

default_legacy_users_file = Path.join(data_dir, "users")
legacy_users_file = env!("GAME_SIMULATOR_USERS_FILE", :string!, default_legacy_users_file)

legacy_users_file =
  if Path.type(legacy_users_file) == :relative, do: Path.expand(legacy_users_file, release_root), else: legacy_users_file

token_ttl_seconds = env!("GAME_SIMULATOR_TOKEN_TTL_SECONDS", :integer, 86_400)

unless token_ttl_seconds > 0 do
  raise ArgumentError,
        "GAME_SIMULATOR_TOKEN_TTL_SECONDS must be greater than zero, got: #{inspect(token_ttl_seconds)}"
end

llm_timeout_ms = env!("GAME_SIMULATOR_LLM_TIMEOUT_MS", :integer, 1_500)

unless llm_timeout_ms > 0 do
  raise ArgumentError,
        "GAME_SIMULATOR_LLM_TIMEOUT_MS must be greater than zero, got: #{inspect(llm_timeout_ms)}"
end

llm_interest_threshold = env!("GAME_SIMULATOR_LLM_INTEREST_THRESHOLD", :integer, 4)

unless llm_interest_threshold > 0 do
  raise ArgumentError,
        "GAME_SIMULATOR_LLM_INTEREST_THRESHOLD must be greater than zero, got: #{inspect(llm_interest_threshold)}"
end

llm_audit_file = env!("GAME_SIMULATOR_LLM_AUDIT_FILE", :string!, "data/llm_shadow_audit.ndjson")

llm_audit_file =
  if Path.type(llm_audit_file) == :relative, do: Path.expand(llm_audit_file, release_root), else: llm_audit_file

config :game_simulator,
  server: [host: host, port: port],
  logging: [directory: log_dir, console_level: console_log_level],
  auth: [data_directory: data_dir, legacy_users_file: legacy_users_file, token_ttl_seconds: token_ttl_seconds],
  llm: [
    enabled: env!("GAME_SIMULATOR_LLM_ENABLED", :boolean, false),
    shadow_mode: env!("GAME_SIMULATOR_LLM_SHADOW_MODE", :boolean, true),
    mode: String.to_existing_atom(env!("GAME_SIMULATOR_LLM_MODE", :string!, "shadow")),
    provider: env!("GAME_SIMULATOR_LLM_PROVIDER", :string!, "openrouter"),
    api_key: env!("GAME_SIMULATOR_LLM_API_KEY", :string, nil),
    base_url: env!("GAME_SIMULATOR_LLM_BASE_URL", :string!, "https://openrouter.ai/api/v1"),
    decision_model: env!("GAME_SIMULATOR_LLM_DECISION_MODEL", :string!, "deepseek/deepseek-v4-flash"),
    timeout_ms: llm_timeout_ms,
    audit_file: llm_audit_file,
    http_referer: env!("GAME_SIMULATOR_LLM_HTTP_REFERER", :string, nil),
    x_title: env!("GAME_SIMULATOR_LLM_X_TITLE", :string!, "game_simulator"),
    interest_threshold: llm_interest_threshold
  ]

# Keep the primary logger at :debug so debug.log always contains every event.
config :logger, level: :debug
config :logger, :default_handler, level: console_log_level

config :logger, :info_log,
  path: Path.join(log_dir, "info.log"),
  level: :info

config :logger, :debug_log,
  path: Path.join(log_dir, "debug.log"),
  level: :debug
