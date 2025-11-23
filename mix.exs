defmodule Tinkex.MixProject do
  use Mix.Project

  @version "0.1.2"
  @source_url "https://github.com/North-Shore-AI/tinkex"
  @docs_url "https://hexdocs.pm/tinkex"

  def version, do: @version

  def project do
    [
      app: :tinkex,
      version: @version,
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      escript: [main_module: Tinkex.CLI],
      deps: deps(),
      docs: docs(),
      description: description(),
      package: package(),
      name: "Tinkex",
      source_url: @source_url,
      homepage_url: @source_url,
      preferred_cli_env: [
        dialyzer: :test
      ]
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      mod: {Tinkex.Application, []},
      extra_applications: [:logger]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      # HTTP/2 client
      {:finch, "~> 0.18"},

      # JSON encoding/decoding
      {:jason, "~> 1.4"},

      # Numerical computing (tensor operations)
      {:nx, "~> 0.7"},

      # Tokenization (HuggingFace models)
      {:tokenizers, "~> 0.5"},

      # Telemetry
      {:telemetry, "~> 1.2"},

      # Development
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:ex_doc, "~> 0.30", only: :dev, runtime: false},

      # Testing
      {:mox, "~> 1.0", only: :test},
      {:bypass, "~> 2.1", only: :test},
      {:supertester, "~> 0.3.1", only: :test}
    ]
  end

  defp description do
    """
    Elixir SDK for Tinker: LoRA training, sampling, and future-based workflows with telemetry and HTTP/2.
    """
  end

  defp docs do
    [
      main: "overview",
      source_ref: "v#{@version}",
      source_url: @source_url,
      homepage_url: @docs_url,
      assets: %{"assets" => "assets"},
      extras: [
        {"README.md", [filename: "overview", title: "Overview"]},
        {"CHANGELOG.md", [filename: "changelog", title: "Changelog"]},
        {"LICENSE", [filename: "license", title: "License"]},
        {"examples/README.md", [filename: "examples", title: "Examples"]},
        "docs/guides/getting_started.md",
        "docs/guides/api_reference.md",
        "docs/guides/troubleshooting.md",
        "docs/guides/training_loop.md",
        "docs/guides/tokenization.md"
      ],
      groups_for_extras: [
        Guides: [
          "docs/guides/getting_started.md",
          "docs/guides/api_reference.md",
          "docs/guides/troubleshooting.md",
          "docs/guides/training_loop.md",
          "docs/guides/tokenization.md"
        ]
      ]
    ]
  end

  defp package do
    [
      name: "tinkex",
      licenses: ["Apache-2.0"],
      links: %{
        "GitHub" => @source_url,
        "Docs" => @docs_url
      },
      files: ~w(lib mix.exs README.md CHANGELOG.md LICENSE assets docs/guides examples)
    ]
  end
end
