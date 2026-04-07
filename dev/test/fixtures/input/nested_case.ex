defmodule Example.NestedCase do
  def handle(conn, params) do
    case conn.method do
      "GET" ->
        case Map.get(params, "id") do
          nil -> {:error, :missing_id}
          id -> {:ok, id}
        end

      "POST" ->
        case Map.get(params, "body") do
          nil -> {:error, :missing_body}
          body -> {:ok, body}
        end

      _ ->
        {:error, :unsupported_method}
    end
  end

  def classify_triple({a, b, c}) do
    case {a, b, c} do
      {nil, nil, nil} -> :all_nil
      {x, nil, nil} when is_integer(x) -> {:one, x}
      {x, y, nil} when is_integer(x) and is_integer(y) -> {:two, x, y}
      {x, y, z} when is_integer(x) and is_integer(y) and is_integer(z) -> {:three, x, y, z}
      _ -> :mixed
    end
  end
end
