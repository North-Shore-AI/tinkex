defmodule Tinkex.MixProject do
  use Mix.Project

  def project do
    [
      app: :tinkex,
      version: "0.1.0",
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      escript: [main_module: Tinkex.CLI],
      deps: deps()
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
      {:dialyxir, "~> 1.4", only: :dev, runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:ex_doc, "~> 0.30", only: :dev, runtime: false},

      # Testing
      {:mox, "~> 1.0", only: :test},
      {:bypass, "~> 2.1", only: :test},
      {:supertester, "~> 0.3.1", only: :test}
    ]
  end
end
