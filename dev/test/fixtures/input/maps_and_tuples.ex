defmodule Maps.Test do
  def test_map do
    [
      %{
        "status" => "premium",
        "age" => 35,
        "tv_brand" => "Samsung"
      },
      %{
        "status" => "active",
        "age" => 22,
        "tv_brand" => "LG"
      },
      %{
        "status" => "pending",
        "age" => 45,
        "tv_brand" => "Sony"
      }
    ]
  end

  def test_map2 do
    [
      %{
        status: "inactive",
        age!: 30,
        tv_brand: "Panasonic"
      },
      %{
        status: "pending",
        age!: 30,
        tv_brand: "LG"
      }
    ]
  end

  @dialyzer {:no_return,
    [
      {:new, 0},
      {:insert, 3},
      {:insert!, 3},
      {:remove, 2},
      {:match, 2},
      {:match, 3},
      {:all_items, 1},
      {:count, 1},
      {:clear, 1},
      {:empty, 1},
      {:exists, 2}
    ]
  }

  def test_tuple do
    [
      {:new, 0},
      {:insert_items, 3},
      {:insert!, 3},
      {:remove, 2}
    ]
  end

end
