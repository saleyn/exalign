defmodule MixProject do
  use Mix.Project

  def project do
    [
      app: :some_app,
      version: "0.1.2",
      elixir: "~> 1.15",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      test_paths: ["test"],
      package: package(),

      # Docs
      name:         "Some App",
      homepage_url: "http://github.com/some/repo",
      authors:      ["Some Author"],
      docs:         [
        main:   "readme",
        extras: ["README.md", "API.md"]
      ]
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp deps do
    [
      {:timex, "~> 3.7", only: :test},
      {:ex_doc, ">= 0.0.0", only: :dev, runtime: false}
    ]
  end

  defp package() do
    [
      # These are the default files included in the package
      licenses: ["MIT"],
      links:    %{"GitHub" => "https://github.com/some/repo"}
    ]
  end
end
