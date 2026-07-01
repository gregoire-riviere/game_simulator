defmodule GameSimulator.MixProject do
  use Mix.Project

  def project do
    [
      app: :game_simulator,
      version: "0.1.0",
      elixir: "~> 1.19",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
	  warning_as_errors: true
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger],
      mod: {GameSimulator.Application, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:llm_composer, "~> 0.19.5"},
      {:poison, "~> 5.0"},
      {:plug_cowboy, "~> 2.8"},
      {:exqlite, "~> 0.33"},
      {:logger_file_backend, "~> 0.0.14"},
      {:logger_backends, "~> 1.0"},
      {:dotenvy, "~> 1.1"},
      {:html_handler,
       git: "https://github.com/gregoire-riviere/html_handler.git",
       ref: "3fa137885b3f68915574c1d476d7eedf5e77aadc"}
    ]
  end
end
