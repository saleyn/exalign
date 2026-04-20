defmodule FunClauses.Test do
  def elixirc_paths(:prod), do: ["lib"]
  def elixirc_paths(_), do: ["lib", "examples"]

  defp priv_elixirc_paths(:prod), do: ["lib"]
  defp priv_elixirc_paths(_), do: ["lib", "examples"]

  # Some more tests after comments
  def paths(:prod), do: ["lib"]
  def paths(_), do: ["lib", "examples"]

  def another_fun(arg) do
    IO.inspect(arg)
  end
end
