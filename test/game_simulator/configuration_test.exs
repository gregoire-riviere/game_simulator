defmodule GameSimulator.ConfigurationTest do
  use ExUnit.Case, async: false

  alias GameSimulator.Configuration

  @config_keys [:server, :logging, :auth, :llm, :start_http?]

  setup do
    previous = Map.new(@config_keys, &{&1, Application.get_env(:game_simulator, &1)})

    on_exit(fn ->
      Enum.each(previous, fn {key, value} ->
        if is_nil(value),
          do: Application.delete_env(:game_simulator, key),
          else: Application.put_env(:game_simulator, key, value)
      end)
    end)
  end

  test "test configuration uses an isolated temporary log directory" do
    %{directory: directory, console_level: console_level} = Configuration.logging!()

    assert directory =~ "game_simulator-test"
    assert console_level == :debug
    assert %{host: "127.0.0.1", port: 4000} = Configuration.server!()
    assert %{token_ttl_seconds: 86_400} = Configuration.auth!()
    assert is_nil(Configuration.llm_api_key())
    assert %{enabled: false, shadow_mode: true, interest_threshold: 4} = Configuration.llm!()
  end

  test "rejects an invalid server port" do
    Application.put_env(:game_simulator, :server, host: "127.0.0.1", port: 0)

    assert_raise ArgumentError, ~r/server port must be between 1 and 65535/, fn ->
      Configuration.validate!()
    end
  end

  test "rejects an invalid console log level" do
    Application.put_env(:game_simulator, :logging,
      directory: System.tmp_dir!(),
      console_level: :notice
    )

    assert_raise ArgumentError, ~r/console log level is invalid/, fn ->
      Configuration.validate!()
    end
  end

  test "rejects an invalid token TTL" do
    Application.put_env(:game_simulator, :auth,
      data_directory: System.tmp_dir!(),
      users_file: Path.join(System.tmp_dir!(), "game_simulator-users"),
      token_ttl_seconds: 0
    )

    assert_raise ArgumentError, ~r/token TTL must be greater than zero/, fn ->
      Configuration.validate!()
    end
  end

  test "writes info events to both configured log files" do
    %{directory: directory} = Configuration.logging!()
    message = "configuration-log-test-#{System.unique_integer([:positive])}"

    require Logger
    Logger.info(message)
    Logger.flush()

    assert File.read!(Path.join(directory, "info.log")) =~ message
    assert File.read!(Path.join(directory, "debug.log")) =~ message
  end

  test "writes debug events only to the debug log" do
    %{directory: directory} = Configuration.logging!()
    message = "configuration-debug-log-test-#{System.unique_integer([:positive])}"

    require Logger
    Logger.debug(message)
    Logger.flush()

    assert File.read!(Path.join(directory, "debug.log")) =~ message
    refute File.read!(Path.join(directory, "info.log")) =~ message
  end
end
