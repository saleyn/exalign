defmodule Example.CaseArms do
  def classify(result) do
    case result do
      {:ok, value} -> value
      {:error, reason} -> {:error, reason}
      _ -> nil
    end
  end

  def classify_tuple({a, b}) do
    case {a, b} do
      {nil, nil} ->
        :both_nil
      {x, nil} when is_integer(x) ->
        {:left, x}
      {nil, y} ->
        {:right, y}
      {x, y} ->
        {x, y}
    end
  end

  def more_complex_case(text, components) do
    components
    |> Enum.reduce_while(%{}, fn component, acc ->
      component_text = maybe_preprocess(text, component.__preprocess__())

      case component.__fields__()
            |> Enum.map(fn {name, field} ->
                {name, Field.extract(field, component_text)}
              end)
            |> Enum.reject(fn {_k, v} -> is_nil(v) end)
            |> Enum.into(%{})
            |> maybe_postprocess(component) do
        {:error, _} = err -> {:halt, err}
        fields -> {:cont, Map.merge(acc, fields)}
      end
    end)
  end
end
