defmodule Example.Keywords do
  def build_user do
    %{
      name:       "Alice",
      age:        30,
      occupation: "developer",
      active:     true,
      debug:      false
    }
  end

  def build_opts do
    [
      timeout:  5000,
      retries:  3,
      base_url: "https://example.com",
      debug:    false
    ]
  end
end