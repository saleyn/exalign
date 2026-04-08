defmodule ExAlign.MixProject do
  use Mix.Project

  def project do
    [
      app: :ex_align,
      version: "0.1.1",
      elixir: "~> 1.13",
      start_permanent: Mix.env() == :prod,
      description: "A Mix formatter plugin that column-aligns Elixir code",
      elixirc_paths: elixirc_paths(Mix.env()),
      test_load_filters: [~r/_test\.exs$/],
      package: package(),
      deps: deps(),
      test_coverage: [output: ".cover"],
      escript: escript(),
      docs: docs()
    ]
  end

  defp docs do
    [
      main: "readme",
      extras: ["README.md", "LICENSE"]
    ]
  end

  defp escript do
    [main_module: ExAlign.CLI, name: "exalign"]
  end

  defp elixirc_paths(:dev), do: ["lib"] ++ Path.wildcard("dev/mix/**/*.ex")
  defp elixirc_paths(_), do: ["lib"]

  defp package do
    [
      files: ~w(lib dev .formatter.exs mix.* Makefile README* LICENSE*),
      licenses: ["MIT"],
      maintainers: ["Serge Aleynikov"],
      links: %{"GitHub" => "https://github.com/saleyn/exalign"}
    ]
  end

  def application do
    [extra_applications: [:logger]]
  end

  defp deps do
    [
      {:ex_doc, ">= 0.0.0", only: :dev, runtime: false}
    ]
  end
end
