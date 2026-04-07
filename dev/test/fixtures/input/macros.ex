defmodule Example.Macros do
  defmacro field(name, type, opts \\ []) do
    quote do
      @fields {unquote(name), unquote(type), unquote(opts)}
    end
  end

  defmacro validate(field, rule) do
    quote do
      @validations {unquote(field), unquote(rule)}
    end
  end

  defmodule Schema do
    import Example.Macros

    field :id, :integer, primary_key: true
    field :name, :string, required: true
    field :email, :string, required: true
    field :age, :integer, default: nil
    field :active, :boolean, default: true

    validate :name, :presence
    validate :email, :format
    validate :age, :numericality
  end
end
