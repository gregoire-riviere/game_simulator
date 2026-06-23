defmodule GameSimulator.Application do
  @moduledoc false
  use Application

  @impl true
  def start(_type, _args) do
    :ok = GameSimulator.Configuration.validate!()
    %{directory: log_directory} = GameSimulator.Configuration.logging!()
    %{data_directory: data_directory} = GameSimulator.Configuration.auth!()
    File.mkdir_p!(log_directory)
    File.mkdir_p!(data_directory)

    with {:ok, _pid} <- LoggerBackends.add({LoggerFileBackend, :info_log}),
         {:ok, _pid} <- LoggerBackends.add({LoggerFileBackend, :debug_log}) do
      Supervisor.start_link(children(), strategy: :one_for_one, name: GameSimulator.Supervisor)
    end
  end

  defp children do
    if GameSimulator.Configuration.http_server?() do
      %{host: host, port: port} = GameSimulator.Configuration.server!()

      [
        {Plug.Cowboy,
         scheme: :http,
         plug: GameSimulatorWeb.Endpoint,
         options: [ip: parse_ip!(host), port: port]}
      ]
    else
      []
    end
  end

  defp parse_ip!(host) do
    case :inet.parse_address(String.to_charlist(host)) do
      {:ok, address} -> address
      {:error, _reason} -> raise ArgumentError, "game_simulator server host must be an IP address"
    end
  end
end
