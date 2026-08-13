defmodule ElvenGard.Spatial.MixProject do
  use Mix.Project

  @version "0.1.0"
  @source_url "https://github.com/elvengard-mmo/elvengard_spatial"

  ## Mix.Project callbacks

  def project() do
    [
      app: :elvengard_spatial,
      version: @version,
      elixir: "~> 1.15",
      description: "Deterministic spatial broad-phase primitives for Elixir games",
      source_url: @source_url,
      start_permanent: Mix.env() == :prod,
      elixirc_options: [warnings_as_errors: true],
      aliases: aliases(),
      elixirc_paths: elixirc_paths(Mix.env()),
      deps: deps()
    ]
  end

  def cli() do
    [preferred_envs: [precommit: :test]]
  end

  ## Private functions

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_environment), do: ["lib"]

  defp deps() do
    [
      {:elvengard_ecs, github: "elvengard-mmo/elvengard_ecs", branch: "main", optional: true}
    ]
  end

  defp aliases() do
    [
      precommit: [
        "format --check-formatted",
        "compile --force --warnings-as-errors",
        "test --warnings-as-errors --cover"
      ]
    ]
  end
end
