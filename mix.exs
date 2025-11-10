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
      ],
      releases: releases()
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

      # HTTP client
      {:req, "~> 0.5"},

      # JSON parsing
      {:jason, "~> 1.4"},

      # Process management
      {:muontrap, "~> 1.5"},

      # Portable executable builder
      {:burrito, "~> 1.0", only: :prod},

      # Code quality and testing
      {:quokka, "~> 2.11", only: [:dev, :test], runtime: false},
      {:mimic, "~> 1.11", only: :test}
    ]
  end

  defp releases do
    # Use Burrito only when explicitly building portable binaries
    # For Docker/standard releases, use Mix's default release process
    steps =
      if System.get_env("USE_BURRITO") == "true" do
        [:assemble, &Burrito.wrap/1]
      else
        [:assemble]
      end

    [
      nimbus: [
        steps: steps,
        burrito: [
          targets: [
            macos_aarch64: [os: :darwin, cpu: :aarch64],
            macos_x86_64: [os: :darwin, cpu: :x86_64],
            linux_x86_64: [os: :linux, cpu: :x86_64],
            linux_aarch64: [os: :linux, cpu: :aarch64],
            windows_x86_64: [os: :windows, cpu: :x86_64]
          ]
        ]
      ]
    ]
  end
end
