import Config
import Dotenvy

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

default_users_file = Path.join(data_dir, "users")
users_file = env!("GAME_SIMULATOR_USERS_FILE", :string!, default_users_file)

users_file =
  if Path.type(users_file) == :relative, do: Path.expand(users_file, release_root), else: users_file

token_ttl_seconds = env!("GAME_SIMULATOR_TOKEN_TTL_SECONDS", :integer, 3600)

unless token_ttl_seconds > 0 do
  raise ArgumentError,
        "GAME_SIMULATOR_TOKEN_TTL_SECONDS must be greater than zero, got: #{inspect(token_ttl_seconds)}"
end

config :game_simulator,
  server: [host: host, port: port],
  logging: [directory: log_dir, console_level: console_log_level],
  auth: [data_directory: data_dir, users_file: users_file, token_ttl_seconds: token_ttl_seconds],
  llm: [api_key: env!("GAME_SIMULATOR_LLM_API_KEY", :string, nil)]

# Keep the primary logger at :debug so debug.log always contains every event.
config :logger, level: :debug
config :logger, :default_handler, level: console_log_level

config :logger, :info_log,
  path: Path.join(log_dir, "info.log"),
  level: :info

config :logger, :debug_log,
  path: Path.join(log_dir, "debug.log"),
  level: :debug
