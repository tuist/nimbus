defmodule Nimbus.MixProject do
  use Mix.Project

  alias Nimbus.Provider.AWS
  alias Nimbus.Provider.Azure
  alias Nimbus.Provider.GCP
  alias Nimbus.Provider.Hetzner

  def project do
    [
      app: :nimbus,
      version: "0.1.0",
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      elixirc_paths: elixirc_paths(Mix.env()),
      elixirc_options: [
        warnings_as_errors: true,
        # Ignore undefined function warnings for providers that are not yet implemented (Phase 2)
        no_warn_undefined: [
          AWS,
          Hetzner,
          GCP,
          Azure
        ]
      ]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      # Telemetry
      {:telemetry, "~> 1.2"},

      # Process management
      {:muontrap, "~> 1.5"},

      # Code quality and testing
      {:quokka, "~> 2.11", only: [:dev, :test], runtime: false},
      {:mimic, "~> 1.11", only: :test}
    ]
  end
end
