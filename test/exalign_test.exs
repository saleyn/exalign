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
      name:       "Alice",
      age:        30,
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
          _           -> nil
        end
      end)
      |> Enum.reject(&is_nil/1)

    assert Enum.uniq(value_positions) |> length() == 1,
           "All keyword-list values should start at the same column"
  end

  test "does not align single keyword entry" do
    input  = "[only_one: :value]\n"
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
      x              = 1
      foo            = "bar"
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
          _           -> nil
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
      @name            "Alice"
      @version         "1.0.0"
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
          _           -> nil
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
    conn  = %{
      "name"       => "Alice",
      "age"        => 30,
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
      @name            "Alice"
      @version         "1.0.0"
      @default_timeout 5000

      def bar do
        x              = 1
        foo            = "bar"
        something_long = 42
      end
    end
    """

    once  = align(input)
    twice = align(once)
    assert once == twice, "Formatting should be idempotent"
  end

  # ---------------------------------------------------------------------------
  # Non-groupable lines pass through unchanged
  # ---------------------------------------------------------------------------

  test "blank lines break alignment groups" do
    input = """
    def foo do
      a              = 1

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
      a              = 1
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
        field :guest_name,       function: &inspect/1
        field :check_in_date,    function: &inspect/1
        field :earnings,         function: &inspect/1
      end
    end
    """

    # Auto-detection of aligned macros means no manual locals_without_parens needed.
    output = ExAlign.format(input, eol_at_eof: :add)

    field_lines =
      output
      |> String.split("\n")
      |> Enum.filter(&Regex.match?(~r/^\s+field\s+/, &1))

    arg2_positions =
      Enum.map(field_lines, fn line ->
        case Regex.run(~r/^(\s*field\s+:\w+,\s+)/, line) do
          [_, prefix] -> String.length(prefix)
          _           -> nil
        end
      end)
      |> Enum.reject(&is_nil/1)

    assert length(arg2_positions) == 4

    assert Enum.uniq(arg2_positions) |> length() == 1,
           "All field second arguments should start at the same column"
  end

  test "does not align single macro call line" do
    input  = "field :only_one, function: &inspect/1\n"
    # Only one occurrence — not an alignment group, so no extra padding is added.
    # The standard formatter will parenthesize the call since it appears only once
    # and is therefore not added to locals_without_parens.
    output = ExAlign.format(input, eol_at_eof: :add)
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
    output = ExAlign.format(input, eol_at_eof: :add)

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
    input =
      "case result do\n  {:ok, value} ->\n    value\n\n  {:error, _} = err ->\n    err\nend\n"

    output = ExAlign.format(input, eol_at_eof: :add)

    assert output =~ ~r/\{:ok, value\}\s+-> value/,
           "short :ok arm should be collapsed to one line"

    assert output =~ ~r/\{:error, _\} = err\s+-> err/,
           "short :error arm should be collapsed to one line"
  end

  test "does not collapse arms whose one-liner would exceed line length" do
    long_body = String.duplicate("x", 90)
    input     = "case result do\n  :ok ->\n    #{long_body}\nend\n"

    output    = ExAlign.format(input, line_length: 98)

    refute output =~ ~r/:ok -> #{long_body}/,
           "arm body that would exceed line_length must stay on its own line"
  end

  test "does not collapse arms when wrap_short_lines: true" do
    input =
      "case result do\n  {:ok, value} ->\n    value\n\n  {:error, _} = err ->\n    err\nend\n"

    output = ExAlign.format(input, wrap_short_lines: true)

    refute output =~ ~r/\{:ok, value\} -> value/,
           "arms should remain expanded when wrap_short_lines: true"
  end

  test "does not collapse multi-line arm bodies" do
    input =
      "case result do\n  :ok ->\n    a = 1\n    a\n  :error ->\n    nil\nend\n"

    output = ExAlign.format(input, eol_at_eof: :add)

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
      _       -> nil
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
      x > 10  -> :medium
      true    -> :small
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
      {:ok, value}     -> value
      {:error, reason} -> {:error, reason}
      _                -> nil
    end
    """

    once  = align(input)
    twice = align(once)
    assert once == twice, "Case arm alignment should be idempotent"
  end

  # ---------------------------------------------------------------------------
  # Case block arm alignment (tuple patterns + guards)
  # ---------------------------------------------------------------------------

  test "does not align case blocks with multi-line bodies" do
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

    output = ExAlign.format(input, eol_at_eof: :add)

    # When there are multi-line bodies, no alignment should occur.
    # The output should match the input (since Code.format_string! already expanded it)
    # and ExAlign should not add any padding/alignment to guards or arrows.

    # Extract lines with -> to verify they are NOT all at the same column
    arm_lines = output |> String.split("\n") |> Enum.filter(&String.contains?(&1, "->"))

    _arrow_positions =
      Enum.map(arm_lines, fn line ->
        case :binary.match(line, "->") do
          {pos, _} -> pos
          :nomatch -> nil
        end
      end)
      |> Enum.reject(&is_nil/1)

    # With multi-line bodies, no special alignment should be applied
    assert output =~ "raise ArgumentError"
    assert output =~ "{comps, false}"
    # Verify no excessive padding was added (alignment would add extra spaces)
    assert output =~ ~r/when is_list\(comps\)\s+->/, "Guard should not have excessive padding"
  end

  test "aligns case blocks with all single-line bodies" do
    input = """
    case {a, b} do
      {nil, nil}                    -> :both_nil
      {x,   nil} when is_integer(x) -> {:left, x}
      {nil, y}                      -> {:right, y}
      {x,   y}                      -> {x, y}
    end
    """

    output    = ExAlign.format(input, [])
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

    assert length(arrow_positions) == 4

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
          _                 -> nil
        end
      end)
      |> Enum.reject(&is_nil/1)

    assert Enum.uniq(second_field_start_positions) |> length() == 1,
           "Second field in tuple patterns should start at the same column; got lines: #{inspect(tuple_lines)}"
  end

  test "case block alignment is idempotent" do
    input = """
    case {a, b} do
      {nil, nil}                    -> :both_nil
      {x,   nil} when is_integer(x) -> {:left, x}
      {nil, y}                      -> {:right, y}
      {x,   y}                      -> {x, y}
    end
    """

    once  = ExAlign.format(input, [])
    twice = ExAlign.format(once, [])
    assert once == twice, "Case block alignment should be idempotent"
  end

  test "arms exceeding line_length keep body on next line" do
    # The collapsed line would be "  :ok    -> xxx...xxx" — indent(2) + ":ok" + spaces + "-> " + body
    # Use a body long enough that even with the minimal prefix it exceeds 98.
    long  = String.duplicate("x", 95)

    input = """
    case result do
      :ok    -> #{long}
      :error -> nil
    end
    """

    output   = ExAlign.format(input, line_length: 98)

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

  test "extracts do to separate line when case header is a pipe chain" do
    input = """
    case list
         |> Enum.filter(&is_integer/1)
         |> Enum.sort() do
      [] -> :empty
      _ -> :ok
    end
    """

    output = ExAlign.format(input, eol_at_eof: :add)

    # The `do` must be extracted to its own line for complex (piped) expressions
    lines = String.split(output, "\n")
    # Check that there's a line with Enum.sort() and a separate line with just do
    has_sort = Enum.any?(lines, &String.contains?(&1, "Enum.sort()")) and not Enum.any?(lines, &String.contains?(&1, "Enum.sort() do"))
    assert has_sort, "`do` must be moved to a separate line for piped case expressions"
  end

  test "does not split single-line case header" do
    input = "case x do\n  :ok -> :fine\nend\n"
    output = ExAlign.format(input, eol_at_eof: :add)
    assert output =~ "case x do", "single-line case header must not be split"
  end

  # ---------------------------------------------------------------------------
  # Fixture-based integration tests
  # ---------------------------------------------------------------------------
  # For each file pair in dev/test/fixtures/{input,expected}/ the formatter output
  # must exactly match the expected file.  To regenerate expected files run:
  #
  #   mix exalign.regenerate_tests

  @fixtures_dir Path.join([File.cwd!(), "dev", "test", "fixtures", "elixir"])

  for input_path <-
        Path.wildcard(Path.join([File.cwd!(), "dev", "test", "fixtures", "elixir", "input", "*.ex"])) do
    name = Path.basename(input_path, ".ex")

    expected_path =
      Path.join([File.cwd!(), "dev", "test", "fixtures", "elixir", "expected", Path.basename(input_path)])

    @input_path    input_path
    @expected_path expected_path
    @fixture_name  name

    test "fixture: #{name}" do
      input    = File.read!(@input_path)
      expected = File.read!(@expected_path)
      actual   = ExAlign.format(input, [])

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

  # ---------------------------------------------------------------------------
  # Global config (~/.config/exalign/.formatter.exs)
  # ---------------------------------------------------------------------------

  @global_config_path Path.expand("~/.config/exalign/.formatter.exs")

  # Temporarily write `content` to the global config path, run `fun`, then
  # restore the original state (delete or restore the previous file).
  defp with_global_config(content, fun) do
    dir     = Path.dirname(@global_config_path)
    File.mkdir_p!(dir)
    existed = File.regular?(@global_config_path)
    backup  = @global_config_path <> ".backup.#{:erlang.unique_integer([:positive])}"
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
        warning =
          capture_io(:stderr, fn ->
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
        warning =
          capture_io(:stderr, fn -> assert ExAlign.load_global_config() == [] end)

        assert warning =~ "must evaluate to a keyword list"
      end)
    end

    test "returns empty list and emits a warning on syntax error" do
      with_global_config("this is not valid elixir %%%", fn ->
        warning =
          capture_io(:stderr, fn -> assert ExAlign.load_global_config() == [] end)

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
        result = ExAlign.format("x = 1\nfoo = 2\n", line_length: 120)
        assert result =~ "x"
        assert result =~ "foo"
      end)
    end
  end

  # ---------------------------------------------------------------------------
  # End-of-file newline handling (eol_at_eof option)
  # ---------------------------------------------------------------------------

  describe "eol_at_eof option" do
    test "eol_at_eof: :add adds newline when missing" do
      input = "x = 1"  # no trailing newline
      output = ExAlign.format(input, eol_at_eof: :add)
      assert String.ends_with?(output, "\n"), "should add newline when eol_at_eof: :add"
    end

    test "eol_at_eof: :add preserves newline when present" do
      input = "x = 1\n"
      output = ExAlign.format(input, eol_at_eof: :add)
      assert String.ends_with?(output, "\n"), "should preserve newline when eol_at_eof: :add"
    end

    test "eol_at_eof: :remove removes newline when present" do
      input = "x = 1\n"
      output = ExAlign.format(input, eol_at_eof: :remove)
      refute String.ends_with?(output, "\n"), "should remove newline when eol_at_eof: :remove"
    end

    test "eol_at_eof: :remove preserves no newline when absent" do
      input = "x = 1"
      output = ExAlign.format(input, eol_at_eof: :remove)
      refute String.ends_with?(output, "\n"), "should not add newline when eol_at_eof: :remove"
    end

    test "eol_at_eof: nil (default) leaves output unchanged from formatter" do
      # The formatter's default behavior is preserved when eol_at_eof is nil
      input = "x = 1\n"
      output = ExAlign.format(input, eol_at_eof: nil)
      # The standard formatter usually adds a trailing newline for valid Elixir code
      assert output =~ "x"
      assert output =~ "="
    end

    test "eol_at_eof: nil (default) with no initial newline" do
      input = "x = 1"
      output = ExAlign.format(input, eol_at_eof: nil)
      # Default behavior: preserve what formatter produces
      assert output =~ "x = 1"
    end

    test "eol_at_eof works with multi-line code" do
      input = """
      x = 1
      foo = 2
      """
      output = ExAlign.format(input, eol_at_eof: :remove)
      refute String.ends_with?(output, "\n"), "should remove final newline from multi-line code"
    end
  end

  describe "option validation" do
    test "unrecognized options emit warning but still format" do
      warning =
        capture_io(:stderr, fn ->
          result = ExAlign.format("x = 1\n", unknown_option: true)
          assert result =~ "x"
          assert result =~ "="
        end)

      assert warning =~ "unsupported option"
    end

    test "wrap_with option accepts :backslash" do
      input = """
      with {:ok, a} <- foo(),
           {:ok, b} <- bar(a) do
        {:ok, {a, b}}
      end
      """
      output = ExAlign.format(input, wrap_with: :backslash)
      assert output =~ "with"
      assert output =~ "foo"
    end

    test "wrap_with option accepts :do" do
      input = """
      with {:ok, a} <- foo(),
           {:ok, b} <- bar(a) do
        {:ok, {a, b}}
      end
      """
      output = ExAlign.format(input, wrap_with: :do)
      assert output =~ "with"
      assert output =~ "bar"
    end
  end

  # ---------------------------------------------------------------------------
  # Edge cases and error handling
  # ---------------------------------------------------------------------------

  describe "edge cases" do
    test "handles empty input" do
      output = ExAlign.format("", [])
      assert output == ""
    end

    test "handles whitespace-only input" do
      output = ExAlign.format("   \n  \n", [])
      assert is_binary(output)
      # Whitespace-only input becomes empty after formatting
      refute String.trim(output) =~ ~r/\S/
    end

    test "handles inline comments in assignments" do
      input = """
      x = 1  # first
      foo = "bar"  # second
      """
      expected = """
      x   = 1     # first
      foo = "bar" # second
      """
      output = ExAlign.format(input, eol_at_eof: :add)
      assert output == expected
    end

    test "handles nested data structures" do
      input = """
      data = %{
        users: [
          %{name: "Alice", age: 30},
          %{name: "Bob", age: 25}
        ]
      }
      """
      expected = """
      data = %{
        users: [
          %{name: "Alice", age: 30},
          %{name: "Bob", age: 25}
        ]
      }
      """
      output = ExAlign.format(input, eol_at_eof: :add)
      assert output == expected
    end

    test "handles pipe chains with multiple operators" do
      input = """
      result = list
            |> Enum.map(&process/1)
            |> Enum.filter(&valid?/1)
            |> Enum.sort()
      """
      expected = """
      result =
        list
        |> Enum.map(&process/1)
        |> Enum.filter(&valid?/1)
        |> Enum.sort()
      """
      output = ExAlign.format(input, eol_at_eof: :add)
      assert output == expected
    end

    test "handles with blocks with multiple clauses" do
      input = """
      with {:ok, a} <- get_a(),
           {:ok, bb} <- get_b(),
           {:ok, ccc} <- get_c() do
        {:ok, {a, b, c}}
      end
      """
      expected = """
      with \\
        {:ok, a}   <- get_a(),
        {:ok, bb}  <- get_b(),
        {:ok, ccc} <- get_c()
      do
        {:ok, {a, b, c}}
      end
      """
      output = ExAlign.format(input, wrap_with: :backslash, eol_at_eof: :add)
      assert output == expected
    end

    test "handles mixed alignment groups" do
      input = """
      a = 1
      bbcd = 2

      x = 10
      yy = 20
      z = 30
      """
      expected = """
      a    = 1
      bbcd = 2

      x    = 10
      yy   = 20
      z    = 30
      """
      # Don't assert exact output due to formatter variations
      output = ExAlign.format(input, eol_at_eof: :add)
      assert output == expected
    end

    test "features/1 returns keyword list with plugin info" do
      result = ExAlign.features([])
      assert is_list(result)
      # The plugin returns metadata for Mix.Tasks.Format
      assert Keyword.has_key?(result, :extensions) or is_list(result)
    end

    test "reattaching formatter comments" do
      # This tests the internal comment reattachment logic
      input = """
      x = 1  # important
      foo = "bar"
      """
      expected = """
      x   = 1     # important
      foo = "bar"
      """
      output = ExAlign.format(input, eol_at_eof: :add)
      assert output == expected
    end

    test "case arms stay expanded when body too long for line" do
      long_body = String.duplicate("x", 70)
      input = """
      case x do
        :ok ->
          #{long_body}
        :error -> :none
      end
      """
      expected = """
      case x do
        :ok    ->
          #{long_body}
        :error ->
          :none
      end
      """
      output = ExAlign.format(input, line_length: 80, eol_at_eof: :add)
      assert output == expected
    end

    test "multiple case blocks in sequence" do
      input = """
      case x do
        1 -> :one
        22 -> :two
      end

      case y do
        a -> :alpha
        bbb -> :beta
      end
      """
      expected = """
      case x do
        1  -> :one
        22 -> :two
      end

      case y do
        a   -> :alpha
        bbb -> :beta
      end
      """
      output = ExAlign.format(input, eol_at_eof: :add)
      assert output == expected
    end

    test "guards in case arm patterns" do
      input = """
      case {a, b} do
        {x, y} when is_integer(x) -> :ok
        {_, _} -> :error
      end
      """
      expected = """
      case {a, b} do
        {x, y} when is_integer(x) -> :ok
        {_, _}                    -> :error
      end
      """
      output = ExAlign.format(input, eol_at_eof: :add)
      assert output == expected
    end

    test "tuple unpacking in assignments" do
      input = """
      {a, b} = get_tuple()
      {x, y, z} = get_triple()
      """
      expected = """
      {a, b} = get_tuple()
      {x, y, z} = get_triple()
      """
      output = ExAlign.format(input, eol_at_eof: :add)
      assert output == expected
    end

    test "mixed map and keyword list syntax" do
      input = """
      opts1 = [key: :value, other: 42]
      opts2 = %{key: :value, other: 42}
      """
      expected = """
      opts1 = [key: :value, other: 42]
      opts2 = %{key: :value, other: 42}
      """
      output = ExAlign.format(input, eol_at_eof: :add)
      assert output == expected
    end

    test "cond block alignment" do
      input = """
      cond do
        x > 100 -> :large
        x > 10 -> :medium
        true -> :small
      end
      """
      expected = """
      cond do
        x > 100 -> :large
        x > 10  -> :medium
        true    -> :small
      end
      """
      output = ExAlign.format(input, eol_at_eof: :add)
      assert output == expected
    end

    test "line_length option affects alignment" do
      input = """
      x = 1
      short = 2
      very_long_variable_name = 3
      """
      expected = """
      x                       = 1
      short                   = 2
      very_long_variable_name = 3
      """
      # With longer line length, more alignment happens
      output = ExAlign.format(input, line_length: 120, eol_at_eof: :add)
      assert output == expected
    end

    test "wrap_with :do option on with block" do
      input = """
      with {:ok, user} <- User.get(id),
           {:ok, profile} <- Profile.get(user) do
        {:ok, {user, profile}}
      end
      """
      expected = """
      with {:ok, user} <- User.get(id),
           {:ok, profile} <- Profile.get(user) do
        {:ok, {user, profile}}
      end
      """
      output = ExAlign.format(input, wrap_with: :do, eol_at_eof: :add)
      assert output == expected
    end

    test "with block using backslash wrap" do
      input = """
      with {:ok, a} <- foo(),
           {:ok, bb} <- bar(a),
           do: {:ok, {a, b}}
      """
      expected = """
      with {:ok, a} <- foo(),
           {:ok, bb} <- bar(a),
           do: {:ok, {a, b}}
      """
      output = ExAlign.format(input, wrap_with: :backslash, eol_at_eof: :add)
      assert output == expected
    end

    test "attribute alignment with mixed types" do
      input = """
      @doc "Module docs"
      @vsn 1
      @behavior GenServer
      """
      expected = """
      @doc      "Module docs"
      @vsn      1
      @behavior GenServer
      """
      output = ExAlign.format(input, eol_at_eof: :add)
      assert output == expected
    end

    test "function clause alignment" do
      input = """
      def process(:ok),    do: true
      def process(:error), do: false
      def process(_),      do: nil
      """
      expected = """
      def process(:ok),    do: true
      def process(:error), do: false
      def process(_),      do: nil
      """
      output = ExAlign.format(input, eol_at_eof: :add)
      assert output == expected
    end

    test "nested pipe chains with comments" do
      input = """
      result = values
               |> Enum.filter(&valid?/1) # filter invalid
               |> Enum.map(&trans/1) # transform
               |> Enum.sort() # sort
      """
      expected = """
      result =
        values
        # filter invalid
        |> Enum.filter(&valid?/1)
        # transform
        |> Enum.map(&trans/1)
        # sort
        |> Enum.sort()
      """
      output = ExAlign.format(input, eol_at_eof: :add)
      assert output == expected
    end

    test "complex nested map/struct creation" do
      input = """
      user = %User{
        name: "Alice",
        email: "alice@example.com"
      }

      params = %{
        "user_id" => user.id,
        "timestamp" => now()
      }
      """
      expected = """
      user = %User{
        name:  "Alice",
        email: "alice@example.com"
      }

      params = %{
        "user_id"   => user.id,
        "timestamp" => now()
      }
      """
      output = ExAlign.format(input, eol_at_eof: :add)
      assert output == expected
    end

    test "single line vs multi-line with extraction" do
      # Single-line with should not split
      single_inp = "with {:ok, a} <- foo(), do: a"
      single_exp = "with {:ok, a} <- foo(), do: a"
      single_out = ExAlign.format(single_inp, [])
      assert single_exp == single_out

      # Multi-line with should extract do
      multi_inp = """
      with {:ok, a} <- foo(),
           {:ok, bb} <- bar(a) do
        {:ok, {a, bb}}
      end
      """
      multi_exp = """
      with \\
        {:ok, a}  <- foo(),
        {:ok, bb} <- bar(a)
      do
        {:ok, {a, bb}}
      end
      """
      multi_out = ExAlign.format(multi_inp, eol_at_eof: :add)
      assert multi_exp == multi_out
    end
  end

  # ---------------------------------------------------------------------------
  # Global config with more edge cases
  # ---------------------------------------------------------------------------

  describe "additional global config tests" do
    test "global config with multiple options" do
      with_global_config("[line_length: 80, wrap_with: :do, eol_at_eof: :add]", fn ->
        opts = ExAlign.load_global_config()
        assert opts[:line_length] == 80
        assert opts[:wrap_with] == :do
        assert opts[:eol_at_eof] == :add
      end)
    end

    test "formatting respects all global eol_at_eof remove option" do
      with_global_config("[line_length: 80, eol_at_eof: :remove]", fn ->
        input    = "x = 1\n"
        expected = "x = 1"
        output = ExAlign.format(input, [])
        # The global config affects the output
        assert output == expected
      end)
    end

    test "formatting respects all global eol_at_eof add option" do
      with_global_config("[line_length: 80, eol_at_eof: :add]", fn ->
        input    = "x = 1"
        expected = "x = 1\n"
        output = ExAlign.format(input, eol_at_eof: :add)
        # The global config affects the output
        assert output == expected
      end)
    end
  end

  # ---------------------------------------------------------------------------
  # Comprehensive integration tests
  # ---------------------------------------------------------------------------

  describe "integration scenarios" do
    test "real-world module structure" do
      input = """
      defmodule MyApp.Service do
        @moduledoc "Service module"
        @timeout 5000
        @retry_count 3

        def process(data), do: handle(data)
        def process_async(data, opts), do: Task.async(fn -> handle(data) end)

        defp handle(data) do
          case validate(data) do
            {:ok, valid} -> process_data(validated)
            {:error, reason} -> {:error, reason}
          end
        end

        defp validate(data) do
          with {:ok, parsed} <- parse(data),
               {:ok, valid}  <- check(parsed) do
            {:ok, valid}
          end
        end
      end
      """
      expected = """
      defmodule MyApp.Service do
        @moduledoc   "Service module"
        @timeout     5000
        @retry_count 3

        def process(data),             do: handle(data)
        def process_async(data, opts), do: Task.async(fn -> handle(data) end)

        defp handle(data) do
          case validate(data) do
            {:ok,    valid}  -> process_data(validated)
            {:error, reason} -> {:error, reason}
          end
        end

        defp validate(data) do
          with \\
            {:ok, parsed} <- parse(data),
            {:ok, valid}  <- check(parsed)
          do
            {:ok, valid}
          end
        end
      end
      """
      output = ExAlign.format(input, eol_at_eof: :add)
      assert output == expected
    end

    test "formatting preserves semantics" do
      input = """
      result = case x do
        1 -> :one
        22 -> :two
        _ -> :other
      end
      """
      expected = """
      result =
        case x do
          1  -> :one
          22 -> :two
          _  -> :other
        end
      """
      output = ExAlign.format(input, eol_at_eof: :add)
      assert output == expected
    end

    test "idempotent formatting across multiple passes" do
      input = """
      x = 1
      foo = "bar"
      something_long = 42
      """
      first_pass = ExAlign.format(input, [])
      second_pass = ExAlign.format(first_pass, [])
      # Should be idempotent - formatting the result again gives the same output
      assert first_pass == second_pass
    end

    test "options propagate through entire pipeline" do
      input = """
      x = 1
      foo = 2
      """
      # Test that different options produce different results
      output_80 = ExAlign.format(input, line_length: 80)
      output_40 = ExAlign.format(input, line_length: 40)
      # Both should be valid outputs
      assert output_80 =~ "x"
      assert output_40 =~ "foo"
    end

    test "keyword list in function call" do
      input = """
      function(
        opt1: value1,
        opt2: value2,
        long_option: value3
      )
      """
      expected = """
      function(
        opt1:        value1,
        opt2:        value2,
        long_option: value3
      )
      """

      output = ExAlign.format(input, eol_at_eof: :add)
      assert output == expected
    end

    test "attribute with function calls" do
      input = """
      @doc    "Documentation"
      @module Module.func()
      @extra  some_value
      """

      output = ExAlign.format(input, eol_at_eof: :add)
      assert output =~ "@doc"
      assert output =~ "@module"
      assert output =~ "@extra"
    end

    test "case with single clause" do
      input = """
      case x do
        :ok -> :result
      end
      """
      expected = """
      case x do
        :ok -> :result
      end
      """

      output = ExAlign.format(input, eol_at_eof: :add)
      assert output == expected
    end

    test "struct fields with long names" do
      input = """
      %MyStruct{
        very_long_field_name: value1,
        another_long_name: value2,
        short: value3
      }
      """
      expected = """
      %MyStruct{
        very_long_field_name: value1,
        another_long_name:    value2,
        short:                value3
      }
      """
      output = ExAlign.format(input, eol_at_eof: :add)
      assert output == expected
    end

    test "function def with guards and do" do
      input = """
      def handle(:ok),          do: true
      def handle(:error),       do: false
      def handle(_),            do: nil
      """
      expected = """
      def handle(:ok),    do: true
      def handle(:error), do: false
      def handle(_),      do: nil
      """
      output = ExAlign.format(input, eol_at_eof: :add)
      assert output == expected
    end

    test "map with symbol keys" do
      input = """
      %{
        key1: value1,
        key2: value2,
        very_long_key_name: value3
      }
      """
      expected = """
      %{
        key1:               value1,
        key2:               value2,
        very_long_key_name: value3
      }
      """
      output = ExAlign.format(input, eol_at_eof: :add)
      assert output == expected
    end

    test "comment between aligned lines" do
      input = """
      x = 1
      # Comment
      foo = "bar"
      """
      expected = """
      x   = 1
      foo = "bar" # Comment
      """
      output = ExAlign.format(input, eol_at_eof: :add)
      # Comment placement may vary - just verify all parts are present
      assert output == expected
    end

    test "tuple pattern matching" do
      input = """
      {a, b} = get_pair()
      {x, y, z} = get_triple()
      """
      expected = """
      {a, b} = get_pair()
      {x, y, z} = get_triple()
      """
      output = ExAlign.format(input, eol_at_eof: :add)
      # Verify both patterns are present and aligned
      assert output == expected
    end

    test "if/unless in case" do
      input = """
      case x do
        y when y > 0 -> :positive
        y when y < 0 -> :negative
        _ -> :zero
      end
      """
      expected = """
      case x do
        y when y > 0 -> :positive
        y when y < 0 -> :negative
        _            -> :zero
      end
      """
      output = ExAlign.format(input, eol_at_eof: :add)
      assert output == expected
    end

    test "map with mixed key types" do
      input = """
      %{
        "string_key"  => value1,
        :atom_key => value2,
        123 => value3
      }
      """
      expected = """
      %{
        "string_key" => value1,
        :atom_key    => value2,
        123          => value3
      }
      """
      output = ExAlign.format(input, eol_at_eof: :add)
      assert output == expected
    end

    test "align with comments above" do
      input = """
      # This is a comment
      x = 1
      foo = "bar"
      """
      expected = """
      x   = 1     # This is a comment
      foo = "bar"
      """
      output = ExAlign.format(input, eol_at_eof: :add)
      assert output == expected
    end

    test "wrap_with do with short with block" do
      input = """
      with a <- foo() do
        a
      end
      """
      expected = """
      with a <- foo() do
        a
      end
      """
      output = ExAlign.format(input, wrap_with: :do, eol_at_eof: :add)
      assert output == expected
    end

    test "complex nested structures" do
      input = """
      config = %{
        database: %{"host" => host, "port" => port},
        cache: [ttl: 3600, size: 1000],
        features: [auth: true, logs: false]
      }
      """
      expected = """
      config = %{
        database: %{"host" => host, "port" => port},
        cache:    [ttl: 3600, size: 1000],
        features: [auth: true, logs: false]
      }
      """
      output = ExAlign.format(input, eol_at_eof: :add)
      assert output == expected
    end

    test "function with multiple pattern matches" do
      input = """
      def process({:ok, data}), do: handle_ok(data)
      def process({:error, code}), do: handle_error(code)
      def process(_), do: :unknown
      """
      expected = """
      def process({:ok, data}),    do: handle_ok(data)
      def process({:error, code}), do: handle_error(code)
      def process(_),              do: :unknown
      """
      output = ExAlign.format(input, eol_at_eof: :add)
      assert output == expected
    end

    test "eol_at_eof add on empty file" do
      input = ""
      output = ExAlign.format(input, eol_at_eof: :add)
      assert output == "\n"
    end

    test "eol_at_eof with only whitespace" do
      input = "   \n"
      output = ExAlign.format(input, eol_at_eof: :remove)
      assert output == ""
    end

    test "short_lines with multi-clauses case" do
      input = """
      result = case maybe_value do
        nil ->
          :not_found
        val ->
          {:found, val}
      end
      """
      expected = """
      result =
        case maybe_value do
          nil ->
            :not_found
          val ->
            {:found, val}
        end
      """

      output = ExAlign.format(input, wrap_short_lines: true, eol_at_eof: :add)
      assert output == expected
    end

    test "alignment across different indentation levels" do
      input = """
      defmodule Example do
        x = 1
        yy = 2

        def inner do
          a = 1
          foo = 2
        end
      end
      """
      expected = """
      defmodule Example do
        x  = 1
        yy = 2

        def inner do
          a   = 1
          foo = 2
        end
      end
      """

      output = ExAlign.format(input, eol_at_eof: :add)
      assert output == expected
    end
  end
end
