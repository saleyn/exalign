defmodule Example.PipeChain do
  def process(list) do
    case list
         |> Enum.filter(&is_integer/1)
         |> Enum.map(fn x -> x * 2 end)
         |> Enum.sort() do
      [] -> :empty
      result -> {:ok, result}
    end
  end

  def flat_fields(components) do
    all_fields =
      components
      |> Enum.flat_map(fn component -> component.fields()
      end)
      |> Enum.into(%{})

    all_fields
  end
end
