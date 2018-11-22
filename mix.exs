defmodule VowpalKingpin.MixProject do
  use Mix.Project

  def project do
    [
      app: :vowpal_kingpin,
      version: "0.1.0",
      elixir: "~> 1.7",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger, :plug_cowboy, :xandra, :vowpal_fleet],
      mod: {VowpalKingpin.Application, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:plug_cowboy, "~> 2.0"},
      {:xandra, "~> 0.10"},
      {:dialyxir, "~> 1.0.0-rc.4", only: [:dev], runtime: false},
      {:vowpal_fleet, "~> 0.1.4"}
    ]
  end
end
