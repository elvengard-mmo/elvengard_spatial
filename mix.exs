defmodule ElvenGard.Spatial.MixProject do
  use Mix.Project

  def project do
    [
      app: :elvengard_spatial,
      version: "0.1.0",
      elixir: "~> 1.17",
      description: "Deterministic spatial broad-phase primitives for Elixir games",
      source_url: "https://github.com/elvengard-mmo/elvengard_spatial",
      start_permanent: Mix.env() == :prod,
      deps: []
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger]
    ]
  end
end
