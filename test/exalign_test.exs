defmodule ExAlignTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  # Helper: strip the leading newline from heredocs and feed directly to
  # align_columns/1 (bypassing Code.format_string! so tests are deterministic).
  # We test format/2 separately for integration cases.
  defp align(code), do: ExAlign.format(code, [])

  # ---------------------------------------------------------------------------
  # Keyword list alignment
  # ---------------------------------------------------------------------------

  test "aligns keyword list entries by the colon" do
    input = """
    %{
      name: "Alice",
      age: 30,
      occupation: "developer"
    }
    """

    output = align(input)

    assert output =~ ~r/name:\s+"Alice"/
    assert output =~ ~r/age:\s+30/
    assert output =~ ~r/occupation: "developer"/

    # All VALUES must start at the same column (gofmt-style: value is aligned, not the separator)
    kw_lines =
      output
      |> String.split("\n")
      |> Enum.filter(&Regex.match?(~r/^\s+\w+:\s+/, &1))

    value_positions =
      kw_lines
      |> Enum.map(fn line ->
        case Regex.run(~r/^(\s*\w+:\s+)/, line) do
          [_, prefix] -> String.length(prefix)
          _ -> nil
        end
      end)
      |> Enum.reject(&is_nil/1)

    assert Enum.uniq(value_positions) |> length() == 1,
           "All keyword-list values should start at the same column"
  end

  test "does not align single keyword entry" do
    input = "[only_one: :value]\n"
    output = align(input)
    # No extra spaces should be added for a lone entry
    assert output =~ "only_one: :value"
    refute output =~ "only_one:  "
  end

  # ---------------------------------------------------------------------------
  # Variable assignment alignment
  # ---------------------------------------------------------------------------

  test "aligns consecutive variable assignments" do
    input = """
    def foo do
      x = 1
      foo = "bar"
      something_long = 42
    end
    """

    output = align(input)

    # The = signs must be at the same column for the three assignment lines
    assignment_lines =
      output
      |> String.split("\n")
      |> Enum.filter(&Regex.match?(~r/^\s+\w+\s+=\s+/, &1))

    eq_positions =
      Enum.map(assignment_lines, fn line ->
        case Regex.run(~r/^(\s*\w+\s*)=/, line) do
          [_, prefix] -> String.length(prefix)
          _ -> nil
        end
      end)
      |> Enum.reject(&is_nil/1)

    assert Enum.uniq(eq_positions) |> length() == 1,
           "All assignment = signs should be at the same column"
  end

  test "does not treat def/if/case as assignments" do
    input = """
    def foo do
      if bar do
        :ok
      end
    end
    """

    output = align(input)
    # Structural keywords should remain untouched
    assert output =~ "def foo do"
    assert output =~ "if bar do"
  end

  # ---------------------------------------------------------------------------
  # Module attribute alignment
  # ---------------------------------------------------------------------------

  test "aligns module attributes" do
    input = """
    defmodule Example do
      @name "Alice"
      @version "1.0.0"
      @default_timeout 5000
    end
    """

    output = align(input)

    attr_lines =
      output
      |> String.split("\n")
      |> Enum.filter(&Regex.match?(~r/^\s+@\w+\s+/, &1))

    value_positions =
      Enum.map(attr_lines, fn line ->
        case Regex.run(~r/^(\s*@\w+\s+)/, line) do
          [_, prefix] -> String.length(prefix)
          _ -> nil
        end
      end)
      |> Enum.reject(&is_nil/1)

    assert Enum.uniq(value_positions) |> length() == 1,
           "All module attribute values should start at the same column"
  end

  # ---------------------------------------------------------------------------
  # Map arrow alignment
  # ---------------------------------------------------------------------------

  test "aligns map fat-arrow entries" do
    input = """
    conn = %{
      "name" => "Alice",
      "age" => 30,
      "occupation" => "developer"
    }
    """

    output = align(input)

    arrow_lines =
      output
      |> String.split("\n")
      |> Enum.filter(&String.contains?(&1, "=>"))

    # Check that the => symbol itself starts at the same byte offset in every line
    arrow_positions =
      Enum.map(arrow_lines, fn line ->
        case :binary.match(line, "=>") do
          {pos, _} -> pos
          :nomatch -> nil
        end
      end)
      |> Enum.reject(&is_nil/1)

    assert Enum.uniq(arrow_positions) |> length() == 1,
           "All => operators should be at the same column"
  end

  # ---------------------------------------------------------------------------
  # Idempotency
  # ---------------------------------------------------------------------------

  test "formatting is idempotent" do
    input = """
    defmodule Foo do
      @name "Alice"
      @version "1.0.0"
      @default_timeout 5000

      def bar do
        x = 1
        foo = "bar"
        something_long = 42
      end
    end
    """

    once = align(input)
    twice = align(once)
    assert once == twice, "Formatting should be idempotent"
  end

  # ---------------------------------------------------------------------------
  # Non-groupable lines pass through unchanged
  # ---------------------------------------------------------------------------

  test "blank lines break alignment groups" do
    input = """
    def foo do
      a = 1

      very_long_name = 2
    end
    """

    output = align(input)
    # The blank line separates the two assignments, so they are NOT aligned together.
    # `very_long_name` should still appear — just not padded to match `a`.
    assert output =~ "very_long_name = 2"
  end

  test "comments break alignment groups" do
    input = """
    def foo do
      a = 1
      # comment
      very_long_name = 2
    end
    """

    output = align(input)
    assert output =~ "# comment"
    assert output =~ "very_long_name = 2"
  end

  # ---------------------------------------------------------------------------
  # Macro call with atom first arg alignment
  # ---------------------------------------------------------------------------

  test "aligns macro calls with atom first argument" do
    input = """
    defmodule Example do
      typedstruct do
        field :reservation_code, function: &inspect/1
        field :guest_name, function: &inspect/1
        field :check_in_date, function: &inspect/1
        field :earnings, function: &inspect/1
      end
    end
    """

    # Auto-detection of aligned macros means no manual locals_without_parens needed.
    output = ExAlign.format(input, [])

    field_lines =
      output
      |> String.split("\n")
      |> Enum.filter(&Regex.match?(~r/^\s+field\s+/, &1))

    arg2_positions =
      Enum.map(field_lines, fn line ->
        case Regex.run(~r/^(\s*field\s+:\w+,\s+)/, line) do
          [_, prefix] -> String.length(prefix)
          _ -> nil
        end
      end)
      |> Enum.reject(&is_nil/1)

    assert length(arg2_positions) == 4
    assert Enum.uniq(arg2_positions) |> length() == 1,
           "All field second arguments should start at the same column"
  end

  test "does not align single macro call line" do
    input = "field :only_one, function: &inspect/1\n"
    # Only one occurrence — not an alignment group, so no extra padding is added.
    # The standard formatter will parenthesize the call since it appears only once
    # and is therefore not added to locals_without_parens.
    output = ExAlign.format(input, [])
    # No alignment padding (no double-space after the comma)
    refute output =~ ~r/field.+,  /
  end

  test "does not group macro calls of different macro names" do
    input = """
    defmodule Example do
      field :short, function: &inspect/1
      other :very_long_name, function: &inspect/1
    end
    """

    # field and other each appear once so neither is added to locals_without_parens;
    # Code.format_string! will parenthesize them.  What matters is that they are
    # NOT grouped together (different macro names) and NOT given alignment padding.
    output = ExAlign.format(input, [])

    # Neither line should have alignment padding (double space after comma)
    refute output =~ ~r/field.+,  /, "field line must not be over-padded"
    refute output =~ ~r/other.+,  /, "other line must not be over-padded"
    # Both calls must still be present
    assert output =~ ~r/field.*:short/, "field line must be present"
    assert output =~ ~r/other.*:very_long_name/, "other line must be present"
  end

  # ---------------------------------------------------------------------------
  # One-liner arrow clause preservation
  # ---------------------------------------------------------------------------

  test "collapses expanded case arms to one line" do
    # Feed already-expanded (formatter-style) arms and expect them collapsed.
    # Arms are also column-aligned, so there may be extra spaces before "->".
    input = "case result do\n  {:ok, value} ->\n    value\n\n  {:error, _} = err ->\n    err\nend\n"

    output = ExAlign.format(input, [])

    assert output =~ ~r/\{:ok, value\}\s+-> value/,
           "short :ok arm should be collapsed to one line"

    assert output =~ ~r/\{:error, _\} = err\s+-> err/,
           "short :error arm should be collapsed to one line"
  end

  test "does not collapse arms whose one-liner would exceed line length" do
    long_body = String.duplicate("x", 90)
    input = "case result do\n  :ok ->\n    #{long_body}\nend\n"

    output = ExAlign.format(input, line_length: 98)

    refute output =~ ~r/:ok -> #{long_body}/,
           "arm body that would exceed line_length must stay on its own line"
  end

  test "does not collapse arms when wrap_short_lines: true" do
    input = "case result do\n  {:ok, value} ->\n    value\n\n  {:error, _} = err ->\n    err\nend\n"

    output = ExAlign.format(input, wrap_short_lines: true)

    refute output =~ ~r/\{:ok, value\} -> value/,
           "arms should remain expanded when wrap_short_lines: true"
  end

  test "does not collapse multi-line arm bodies" do
    input =
      "case result do\n  :ok ->\n    a = 1\n    a\n  :error ->\n    nil\nend\n"

    output = ExAlign.format(input, [])

    # :ok arm has two body lines — must NOT be collapsed
    refute output =~ ~r/:ok -> a = 1/
    # When any arm has a multi-line body, the whole block stays expanded —
    # :error arm stays on its own line too (consistent style)
    assert output =~ ~r/:error ->/
    assert output =~ "nil"
  end

  # ---------------------------------------------------------------------------
  # Case arm -> alignment
  # ---------------------------------------------------------------------------

  test "aligns -> in case arms" do
    input = """
    case Regex.run(pattern, text) do
      [value] -> transform.(value)
      _ -> nil
    end
    """

    output = align(input)

    arm_lines =
      output
      |> String.split("\n")
      |> Enum.filter(&String.contains?(&1, "->"))

    arrow_positions =
      Enum.map(arm_lines, fn line ->
        case :binary.match(line, "->") do
          {pos, _} -> pos
          :nomatch -> nil
        end
      end)
      |> Enum.reject(&is_nil/1)

    assert length(arrow_positions) == 2
    assert Enum.uniq(arrow_positions) |> length() == 1,
           "All -> operators in case arms should be at the same column"
  end

  test "aligns -> in cond arms" do
    input = """
    cond do
      x > 100 -> :large
      x > 10 -> :medium
      true -> :small
    end
    """

    output = align(input)

    arm_lines =
      output
      |> String.split("\n")
      |> Enum.filter(&String.contains?(&1, "->"))

    arrow_positions =
      Enum.map(arm_lines, fn line ->
        case :binary.match(line, "->") do
          {pos, _} -> pos
          :nomatch -> nil
        end
      end)
      |> Enum.reject(&is_nil/1)

    assert length(arrow_positions) == 3
    assert Enum.uniq(arrow_positions) |> length() == 1,
           "All -> operators in cond arms should be at the same column"
  end

  test "case arm alignment is idempotent" do
    input = """
    case result do
      {:ok, value} -> value
      {:error, reason} -> {:error, reason}
      _ -> nil
    end
    """

    once = align(input)
    twice = align(once)
    assert once == twice, "Case arm alignment should be idempotent"
  end

  # ---------------------------------------------------------------------------
  # Case block arm alignment (tuple patterns + guards)
  # ---------------------------------------------------------------------------

  test "aligns tuple patterns, guards, and -> across case arms" do
    input = """
    case {Keyword.get(opts, :components), Keyword.get(opts, :structs)} do
      {nil, nil} ->
        raise ArgumentError, "must pass either :components or :structs"
      {comps, nil} when is_list(comps) ->
        {comps, false}
      {_, structs} when is_list(structs) ->
        {structs, true}
      {comps, true} when is_list(comps) ->
        {comps, true}
      {comps, false} when is_list(comps) ->
        {comps, false}
      {_, _} ->
        raise ArgumentError, ":components must be a list or :structs must be a list"
    end
    """

    output = ExAlign.format(input, [])
    arm_lines = output |> String.split("\n") |> Enum.filter(&String.contains?(&1, "->"))

    # All -> must be at the same column
    arrow_positions =
      Enum.map(arm_lines, fn line ->
        case :binary.match(line, "->") do
          {pos, _} -> pos
          :nomatch -> nil
        end
      end)
      |> Enum.reject(&is_nil/1)

    assert length(arrow_positions) == 6
    assert Enum.uniq(arrow_positions) |> length() == 1,
           "All -> operators should be at the same column; got: #{inspect(arm_lines)}"

    # Tuple second-field should be column-aligned
    tuple_lines = Enum.filter(arm_lines, &Regex.match?(~r/^\s+\{/, &1))

    # In the comma-then-pad style, the second field starts at a fixed column.
    # We check that the char immediately after the first comma+spaces is at the same column.
    second_field_start_positions =
      Enum.map(tuple_lines, fn line ->
        case Regex.run(~r/^\s+\{[^,]+,\s*/, line, return: :index) do
          [{_, prefix_len}] -> prefix_len
          _ -> nil
        end
      end)
      |> Enum.reject(&is_nil/1)

    assert Enum.uniq(second_field_start_positions) |> length() == 1,
           "Second field in tuple patterns should start at the same column; got lines: #{inspect(tuple_lines)}"
  end

  test "case block alignment is idempotent" do
    input = """
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
    """

    once = ExAlign.format(input, [])
    twice = ExAlign.format(once, [])
    assert once == twice, "Case block alignment should be idempotent"
  end

  test "arms exceeding line_length keep body on next line" do
    # The collapsed line would be "  :ok    -> xxx...xxx" — indent(2) + ":ok" + spaces + "-> " + body
    # Use a body long enough that even with the minimal prefix it exceeds 98.
    long = String.duplicate("x", 95)

    input = """
    case result do
      :ok ->
        #{long}
      :error ->
        nil
    end
    """

    output = ExAlign.format(input, line_length: 98)

    # The :ok arm body is too long to inline — must stay on its own line.
    # Check that no single line contains both ":ok ->" and the long body.
    ok_lines = output |> String.split("\n") |> Enum.filter(&String.contains?(&1, ":ok"))
    assert Enum.all?(ok_lines, fn line -> not String.contains?(line, long) end),
           ":ok arm should NOT be inlined when body exceeds line_length"

    # :error arm is short — may be inlined
    assert output =~ ~r/:error\s+-> nil/
  end

  # ---------------------------------------------------------------------------
  # multi-line block header: `do` moved to its own line
  # ---------------------------------------------------------------------------

  test "moves do to its own line when case header is a pipe chain" do
    input = """
    case list
         |> Enum.filter(&is_integer/1)
         |> Enum.sort() do
      [] -> :empty
      _ -> :ok
    end
    """

    output = ExAlign.format(input, [])

    # The `do` must be on its own line, not tacked onto the last pipe
    refute output =~ ~r/Enum\.sort\(\) do/,
           "`do` must not remain at end of last pipe"

    lines = String.split(output, "\n")

    do_line = Enum.find(lines, &(String.trim(&1) == "do"))
    assert do_line, "a bare `do` line must exist"

    # do must be at the same indentation as `case`
    case_line = Enum.find(lines, &String.starts_with?(String.trim_leading(&1), "case "))
    assert get_indent(do_line) == get_indent(case_line),
           "`do` must be indented to match `case`"
  end

  test "does not split single-line case header" do
    input = "case x do\n  :ok -> :fine\nend\n"
    output = ExAlign.format(input, [])
    assert output =~ "case x do", "single-line case header must not be split"
  end

  # ---------------------------------------------------------------------------
  # Fixture-based integration tests
  # ---------------------------------------------------------------------------
  # For each file pair in dev/test/fixtures/{input,expected}/ the formatter output
  # must exactly match the expected file.  To regenerate expected files run:
  #
  #   mix fmt.regenerate_tests

  @fixtures_dir Path.join([File.cwd!(), "dev", "test", "fixtures"])

  for input_path <- Path.wildcard(Path.join([File.cwd!(), "dev", "test", "fixtures", "input", "*.ex"])) do
    name = Path.basename(input_path, ".ex")
    expected_path = Path.join([File.cwd!(), "dev", "test", "fixtures", "expected", Path.basename(input_path)])

    @input_path input_path
    @expected_path expected_path
    @fixture_name name

    test "fixture: #{name}" do
      input = File.read!(@input_path)
      expected = File.read!(@expected_path)
      actual = ExAlign.format(input, [])

      assert actual == expected,
             """
             Fixture #{@fixture_name} did not match expected output.

             --- expected ---
             #{expected}
             --- actual ---
             #{actual}
             """
    end
  end

  _ = @fixtures_dir

  defp get_indent(line) do
    String.length(line) - String.length(String.trim_leading(line))
  end

  # ---------------------------------------------------------------------------
  # Global config (~/.config/exalign/.formatter.exs)
  # ---------------------------------------------------------------------------

  @global_config_path Path.expand("~/.config/exalign/.formatter.exs")

  # Temporarily write `content` to the global config path, run `fun`, then
  # restore the original state (delete or restore the previous file).
  defp with_global_config(content, fun) do
    dir = Path.dirname(@global_config_path)
    File.mkdir_p!(dir)
    existed = File.regular?(@global_config_path)
    backup = @global_config_path <> ".backup.#{:erlang.unique_integer([:positive])}"
    existed && File.rename!(@global_config_path, backup)

    File.write!(@global_config_path, content)

    try do
      fun.()
    after
      File.rm(@global_config_path)
      existed && File.rename!(backup, @global_config_path)
    end
  end

  describe "load_global_config/0" do
    test "returns empty list when global config file does not exist" do
      backup  = @global_config_path <> ".#{:erlang.unique_integer([:positive])}.backup"
      existed = File.regular?(@global_config_path)
      if existed, do: File.rename!(@global_config_path, backup)

      try do
        assert ExAlign.load_global_config() == []
      after
        if existed, do: File.rename!(backup, @global_config_path)
      end
    end

    test "returns recognised options from a valid global config" do
      with_global_config("[line_length: 120, wrap_short_lines: true]", fn ->
        opts = ExAlign.load_global_config()
        assert opts[:line_length] == 120
        assert opts[:wrap_short_lines] == true
      end)
    end

    test "strips unrecognised keys and emits a warning" do
      with_global_config("[line_length: 100, unknown_opt: :bad]", fn ->
        warning = capture_io(:stderr, fn ->
          opts = ExAlign.load_global_config()
          assert opts[:line_length] == 100
          refute Keyword.has_key?(opts, :unknown_opt)
        end)
        assert warning =~ "unsupported option"
        assert warning =~ ":unknown_opt"
      end)
    end

    test "returns empty list and emits a warning when config is not a keyword list" do
      with_global_config(":not_a_keyword_list", fn ->
        warning = capture_io(:stderr, fn ->
          assert ExAlign.load_global_config() == []
        end)
        assert warning =~ "must evaluate to a keyword list"
      end)
    end

    test "returns empty list and emits a warning on syntax error" do
      with_global_config("this is not valid elixir %%%", fn ->
        warning = capture_io(:stderr, fn ->
          assert ExAlign.load_global_config() == []
        end)
        assert warning =~ "could not load"
      end)
    end
  end

  describe "global config applied to format/2" do
    test "global line_length is used as default in format/2" do
      # Write a global config with a very short line length; local opts are empty
      # so the global value must be picked up.
      with_global_config("[line_length: 40]", fn ->
        opts = ExAlign.load_global_config()
        assert opts[:line_length] == 40
      end)
    end

    test "local opts override global config in format/2" do
      with_global_config("[line_length: 40]", fn ->
        # Passing line_length: 120 locally must win over the global 40
        result = ExAlign.format("x = 1\nfoo = 2\n", [line_length: 120])
        assert is_binary(result)
      end)
    end
  end
end
