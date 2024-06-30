defmodule Hop.MixProject do
  use Mix.Project

  @source_url "https://github.com/seanmor5/hop"
  @version "0.1.0"

  def project do
    [
      app: :hop,
      version: "0.1.0",
      elixir: "~> 1.15",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      docs: docs(),
      package: package(),
      preferred_cli_env: [
        docs: :docs,
        "hex.publish": :docs
      ],
      description: "A tiny web crawling framework for Elixir"
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp elixirc_paths(:test), do: ~w(lib test/support)
  defp elixirc_paths(_), do: ~w(lib)

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:req, "~> 0.5"},
      {:floki, ">= 0.30.0"},
      {:req_crawl, "~> 0.2.0"},
      {:bandit, "~> 1.0", only: :test},
      {:plug, "~> 1.16", only: :test},
      {:temple, "~> 0.12", only: :test},
      {:ex_doc, "~> 0.23", only: :docs}
    ]
  end

  defp package do
    [
      maintainers: ["Sean Moriarity"],
      licenses: ["Apache-2.0"],
      links: %{"GitHub" => @source_url}
    ]
  end

  defp docs do
    [
      main: "Hop",
      source_ref: "v#{@version}",
      source_url: @source_url,
      groups_for_docs: [
        Builders: &(&1[:type] == :builder),
        Execution: &(&1[:type] == :execution),
        Configuration: &(&1[:type] == :configuration),
        Validators: &(&1[:type] == :validator),
        "HTML Helpers": &(&1[:type] == :html),
        "State Manipulation": &(&1[:type] == :state)
      ]
    ]
  end
end
