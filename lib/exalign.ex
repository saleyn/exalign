defmodule ExAlign do
  @moduledoc """
  A Mix formatter plugin that column-aligns Elixir code, similar to how
  Go's `gofmt` aligns struct fields and variable groups.

  ## Patterns aligned

    - **Keyword list entries** - `key: value` aligns after the colon
    - **Variable assignments** - `var = value` aligns the `=`
    - **Map arrow entries** - `key => value` aligns the `=>`
    - **Module attributes** - `@attr value` aligns the value

  ## Usage

  Add to your project's `.formatter.exs`:

      [
        plugins: [ExAlign],
        inputs: ["{mix,.formatter}.exs", "{config,lib,test}/**/*.{ex,exs}"]
      ]

  And add `exalign` to your `mix.exs` dependencies.
  """

  @behaviour Mix.Tasks.Format

  # Elixir keywords / macros that begin expressions - never treat as assignments
  @elixir_keywords ~w[
    def defp defmacro defmacrop defguard defguardp
    defmodule defprotocol defimpl defstruct defdelegate defexception
    defoverridable defcallback defmacrocallback
    if unless case cond with for receive
    try after rescue catch raise reraise
    import require use alias
    quote unquote unquote_splicing
    do end fn
  ]

  @impl Mix.Tasks.Format
  def features(_opts) do
    [extensions: [".ex", ".exs"]]
  end

  @impl Mix.Tasks.Format
  @doc """
  Formats the given Elixir source `contents` string, applying column alignment
  on top of the standard `Code.format_string!` pass.

  `opts` may include any standard formatter options plus the ExAlign-specific
  keys `:wrap_short_lines`, `:wrap_with`, and `:line_length`.
  """
  def format(contents, opts) do
    # Before running the standard formatter, detect any macro names that appear in
    # aligned groups (e.g. `field :name, opts`).  We add them to
    # `locals_without_parens` so Code.format_string! leaves them paren-free, and
    # we raise `line_length` to the longest such line so the formatter does not
    # break aligned one-liners into multi-line form.
    formatting_opts = build_formatting_opts(opts, contents)

    formatted =
      contents
      |> Code.format_string!(formatting_opts)
      |> IO.iodata_to_binary()

    line_length = Keyword.get(opts, :line_length, 98)

    if Keyword.get(opts, :wrap_short_lines, false) do
      formatted
      |> extract_do_to_own_line(opts)
      |> realign_pipe_chains()
      |> align_case_blocks(line_length)
      |> align_columns()
    else
      formatted
      |> collapse_one_liners(opts)
      |> extract_do_to_own_line(opts)
      |> realign_pipe_chains()
      |> collapse_one_liners(opts)
      |> align_case_blocks(line_length)
      |> align_columns()
    end
  end

  # Build Code.format_string! opts that prevent it from adding parens to or
  # breaking up lines that are part of aligned macro-call groups.
  defp build_formatting_opts(opts, contents) do
    aligned_macros = detect_aligned_macros(contents)

    existing_lwp = Keyword.get(opts, :locals_without_parens, [])

    new_lwp =
      aligned_macros
      |> Enum.map(&{&1, :*})
      |> Kernel.++(existing_lwp)
      |> Enum.uniq_by(&elem(&1, 0))

    # Find the longest line that looks like a macro-arg-aligned call so we can
    # ensure Code.format_string! does not break it.
    max_aligned_len =
      contents
      |> String.split("\n")
      |> Enum.filter(fn line ->
        stripped = String.trim_leading(line)
        Regex.match?(~r/^[a-z_]\w*\s+:\w+,\s+\S/, stripped)
      end)
      |> Enum.map(&String.length/1)
      |> case do
        [] -> 0
        lengths -> Enum.max(lengths)
      end

    effective_line_length = max(Keyword.get(opts, :line_length, 98), max_aligned_len)

    opts
    |> Keyword.put(:locals_without_parens, new_lwp)
    |> Keyword.put(:line_length, effective_line_length)
  end

  # Return the atom names of macros that appear 2+ times in the source with
  # the shape `macro :atom, rest` (potential alignment group members).
  defp detect_aligned_macros(code) do
    code
    |> String.split("\n")
    |> Enum.flat_map(fn line ->
      stripped = String.trim_leading(line)

      case Regex.run(~r/^([a-z_]\w*)\s+:\w+,\s+\S/, stripped) do
        [_, macro] when macro not in @elixir_keywords -> [macro]
        _ -> []
      end
    end)
    |> Enum.frequencies()
    |> Enum.filter(fn {_name, count} -> count >= 2 end)
    |> Enum.map(fn {name, _} -> String.to_atom(name) end)
  end

  # ---------------------------------------------------------------------------
  # Collapse short one-liner arrow clauses (case/cond/fn/with-else arms)
  # ---------------------------------------------------------------------------

  defp collapse_one_liners(code, opts) do
    line_length = Keyword.get(opts, :line_length, 98)

    code
    |> String.split("\n")
    |> do_collapse(line_length, [])
    |> Enum.join("\n")
  end

  defp do_collapse([], _ll, acc), do: Enum.reverse(acc)
  defp do_collapse([line], _ll, acc), do: Enum.reverse([line | acc])

  defp do_collapse([line_a, line_b | rest], ll, acc) do
    indent_a = get_indent(line_a)
    indent_b = get_indent(line_b)

    next_indent =
      case rest do
        [next | _] -> get_indent(next)
        [] -> 0
      end

    arrow_head? =
      String.ends_with?(String.trim_trailing(line_a), " ->") and
        indent_b == indent_a + 2 and
        (rest == [] or next_indent <= indent_a)

    # An inline lambda body followed by an orphaned `end` / `end)` / `end,` at the
    # same indent level.  This arises after collapsing `fn x ->\n  body\nend)` to
    # `fn x -> body\nend)` - we need one more step to pull `end)` onto the same line.
    orphan_end? =
      not arrow_head? and
        indent_b == indent_a and
        String.contains?(line_a, " -> ") and
        String.match?(String.trim_leading(line_b), ~r/^end[\s),|>]*$/) and
        not String.ends_with?(String.trim_trailing(line_a), " ->")

    # When the line after the body is an orphan `end)/end,` at `indent_a`, we must
    # either collapse the full form `fn -> body end)` in one go, or not collapse at
    # all — a partial collapse (body inline, `end)` on next line) is malformed.
    next_is_orphan_end? =
      case rest do
        [l | _] ->
          String.match?(String.trim_leading(l), ~r/^end[\s),]*$/) and
            get_indent(l) == indent_a

        _ ->
          false
      end

    cond do
      arrow_head? and next_is_orphan_end? ->
        # Attempt full collapse: `fn -> body end)`
        body_part = String.trim_trailing(line_a) <> " " <> String.trim_leading(line_b)
        end_part = String.trim_leading(hd(rest))
        collapsed = body_part <> " " <> end_part

        if String.length(collapsed) <= ll do
          # Skip the orphan `end)` line too
          do_collapse(tl(rest), ll, acc, collapsed)
        else
          # Full form doesn't fit — leave expanded (don't partial-collapse)
          do_collapse([line_b | rest], ll, [line_a | acc])
        end

      arrow_head? ->
        collapsed = String.trim_trailing(line_a) <> " " <> String.trim_leading(line_b)

        if String.length(collapsed) <= ll do
          do_collapse([collapsed | rest], ll, acc)
        else
          do_collapse([line_b | rest], ll, [line_a | acc])
        end

      orphan_end? ->
        collapsed = String.trim_trailing(line_a) <> " " <> String.trim_leading(line_b)

        if String.length(collapsed) <= ll do
          do_collapse([collapsed | rest], ll, acc)
        else
          do_collapse([line_b | rest], ll, [line_a | acc])
        end

      true ->
        do_collapse([line_b | rest], ll, [line_a | acc])
    end
  end

  # Variant that injects an already-collapsed line as next to process.
  defp do_collapse(rest, ll, acc, collapsed_line) do
    do_collapse([collapsed_line | rest], ll, acc)
  end

  # ---------------------------------------------------------------------------
  # Re-indent pipe chains that follow block keywords
  # ---------------------------------------------------------------------------
  # Code.format_string! aligns `|>` continuations directly under the expression
  # that follows the keyword, e.g. `case ` (5 chars) -> pipes at kw_indent+5.
  # We normalise them to kw_indent+2.  All sub-lines (fn bodies, end)) inside
  # the chain are shifted by the same delta.

  defp realign_pipe_chains(code) do
    lines = String.split(code, "\n")
    do_realign_pipes(lines, []) |> Enum.join("\n")
  end

  defp do_realign_pipes([], acc), do: Enum.reverse(acc)

  defp do_realign_pipes([line | rest], acc) do
    stripped = String.trim_leading(line)
    kw_indent = get_indent(line)

    is_block_kw? =
      case Regex.run(~r/^(case|if|cond|with|for|receive|try|unless)\b/, stripped) do
        [_, _] -> true
        _ -> false
      end

    if is_block_kw? do
      case rest do
        [next | _] ->
          next_stripped = String.trim_leading(next)
          next_indent = get_indent(next)
          desired = kw_indent + 2

          if String.starts_with?(next_stripped, "|>") and next_indent > desired do
            delta = desired - next_indent
            {block, after_block} = collect_pipe_block(rest, next_indent, kw_indent)
            realigned = Enum.map(block, &reindent_by(&1, delta))
            do_realign_pipes(after_block, Enum.reverse(realigned) ++ [line | acc])
          else
            do_realign_pipes(rest, [line | acc])
          end

        [] ->
          Enum.reverse([line | acc])
      end
    else
      do_realign_pipes(rest, [line | acc])
    end
  end

  # Collect lines belonging to the pipe-chain expression: all lines at indent
  # >= pipe_indent (including fn bodies, end) etc.), stopping before the bare
  # `do` line at kw_indent or any line shallower than pipe_indent.
  defp collect_pipe_block([], _pipe_indent, _kw_indent), do: {[], []}

  defp collect_pipe_block([line | rest] = all, pipe_indent, kw_indent) do
    stripped = String.trim_leading(line)
    line_indent = get_indent(line)

    cond do
      stripped == "" ->
        {[], all}

      line_indent == kw_indent and String.trim(line) == "do" ->
        {[], all}

      line_indent >= pipe_indent ->
        {block, after_block} = collect_pipe_block(rest, pipe_indent, kw_indent)
        {[line | block], after_block}

      true ->
        {[], all}
    end
  end

  defp reindent_by(line, delta) do
    if String.trim(line) == "" do
      line
    else
      new_indent = max(0, get_indent(line) + delta)
      String.duplicate(" ", new_indent) <> String.trim_leading(line)
    end
  end

  # ---------------------------------------------------------------------------
  # Move "do" to its own line when the block header spans multiple lines
  # ---------------------------------------------------------------------------
  # Code.format_string! writes e.g.:
  #
  #   case expr
  #        |> foo()
  #        |> bar() do
  #
  # We transform that to:
  #
  #   case expr
  #     |> foo()
  #     |> bar()
  #   do
  #
  # The `do` is placed at the indentation of the enclosing block keyword.
  #
  # A line is a "continuation do-line" when:
  #   - it ends with " do" (after trimming trailing whitespace), AND
  #   - it does NOT start (after trimming leading whitespace) with one of the
  #     block keywords (case/if/cond/with/for/receive/try/unless), meaning the
  #     `do` was tacked onto a continuation expression rather than the
  #     keyword-head line itself.

  @block_keywords ~w[case if cond with for receive try unless]

  defp extract_do_to_own_line(code, opts) do
    wrap_with = Keyword.get(opts, :wrap_with, :backslash)
    lines = String.split(code, "\n")
    lines |> do_extract_do(wrap_with, [], []) |> Enum.join("\n")
  end

  # We accumulate lines into `buf` (newest-first) looking for a multi-line
  # block header. When we see a ` do` terminus, we scan `buf` backwards to find
  # the keyword line that opened the expression.
  defp do_extract_do([], _swd, _buf, acc), do: Enum.reverse(acc)

  defp do_extract_do([line | rest], wrap_with, _buf, acc) do
    trimmed = String.trim_trailing(line)

    if String.ends_with?(trimmed, " do") and is_continuation_do_line?(trimmed, acc, wrap_with) do
      # Strip " do" from this line
      body = String.slice(trimmed, 0..(String.length(trimmed) - 4))
      body_line = if String.trim(body) == "", do: nil, else: body

      # Find the keyword indentation by scanning backward through acc for the
      # block-keyword line that this expression belongs to.
      kw_indent = find_keyword_indent(acc, get_indent(line))

      do_line = String.duplicate(" ", kw_indent) <> "do"

      {new_lines, new_acc} =
        if wrap_with == :backslash and is_with_clause_line?(trimmed, acc) do
          # Rewrite: replace `with FIRST_CLAUSE,` line with `with \` + re-indented
          # first clause; re-indent all subsequent clause lines to kw_indent+2.
          clause_indent = String.duplicate(" ", kw_indent + 2)

          {rewritten_acc, _found} =
            Enum.map_reduce(acc, false, fn l, done ->
              if not done and String.match?(String.trim_leading(l), ~r/^with\b/) do
                # Strip the first clause off the `with` line and emit just `with \`
                with_prefix = String.duplicate(" ", get_indent(l)) <> "with \\"
                first_clause_stripped = Regex.replace(~r/^(\s*)with\s+/, l, "")
                first_clause_line = clause_indent <> String.trim_leading(first_clause_stripped)
                # Return a two-element list — map_reduce expects one element per input,
                # so we collect them as a tagged tuple and flatten after.
                {{:split, with_prefix, first_clause_line}, true}
              else
                old_ind = get_indent(l)
                if not done and old_ind > kw_indent do
                  {clause_indent <> String.trim_leading(l), false}
                else
                  {l, done}
                end
              end
            end)

          # Flatten {:split, ...} tuples back to individual lines.
          # acc is newest-first, so first_clause_line must precede with_prefix
          # in the list so that with_prefix appears first after Enum.reverse.
          flat_acc =
            Enum.flat_map(rewritten_acc, fn
              {:split, a, b} -> [b, a]
              l -> [l]
            end)

          last_clause =
            if body_line, do: clause_indent <> String.trim_leading(body), else: nil

          new_ls = if last_clause, do: [do_line, last_clause], else: [do_line]
          {new_ls, flat_acc}
        else
          new_ls =
            if body_line do
              [do_line, body_line]
            else
              [do_line]
            end

          {new_ls, acc}
        end

      do_extract_do(rest, wrap_with, [], new_lines ++ new_acc)
    else
      do_extract_do(rest, wrap_with, [], [line | acc])
    end
  end

  # Returns true if the line whose trailing " do" we're inspecting is a
  # continuation line (not the keyword-head itself).
  defp is_continuation_do_line?(trimmed, acc, wrap_with) do
    stripped = String.trim_leading(trimmed)

    cond do
      # Pipe continuation — always split
      String.match?(stripped, ~r/^\|>/) ->
        true

      # Last clause of a `with` block: contains ` <- ` and a `with` ancestor exists
      wrap_with in [true, :backslash] and String.contains?(trimmed, " <- ") ->
        is_with_clause_line?(trimmed, acc)

      true ->
        false
    end
  end

  defp is_with_clause_line?(trimmed, acc) do
    ind = get_indent(trimmed)

    Enum.any?(acc, fn l ->
      get_indent(l) < ind and String.match?(String.trim_leading(l), ~r/^with\b/)
    end)
  end

  # Scan backward through already-emitted lines (acc is newest-first) looking
  # for an enclosing block keyword at an indent level <= the continuation indent.
  defp find_keyword_indent(acc, cont_indent) do
    acc
    |> Enum.find(fn line ->
      ind = get_indent(line)
      stripped = String.trim_leading(line)
      first_word = case Regex.run(~r/^([a-z_]\w*)/, stripped) do
        [_, w] -> w
        _ -> ""
      end
      ind < cont_indent and first_word in @block_keywords
    end)
    |> case do
      nil -> cont_indent
      line -> get_indent(line)
    end
  end

  # ---------------------------------------------------------------------------
  # Case-block arm alignment
  # ---------------------------------------------------------------------------
  # Recognises a sequence of case/cond arms at the same indentation level and
  # column-aligns:
  #   1. Elements inside tuple patterns  e.g. {nil,   nil}, {comps, nil}
  #   2. Guards after the pattern        e.g. `when is_list(comps)`
  #   3. The `->` operator
  #   4. Bodies: inline when they fit within line_length (majority rule),
  #      otherwise kept on the next indented line.

  defp align_case_blocks(code, line_length) do
    lines = String.split(code, "\n")
    lines |> do_align_case_blocks(line_length, []) |> Enum.join("\n")
  end

  # Walk through lines collecting arms into blocks then emitting them.
  defp do_align_case_blocks([], _ll, acc), do: Enum.reverse(acc)

  defp do_align_case_blocks([line | rest], ll, acc) do
    # An arm head is: <indent>pattern [guard] ->
    # where indent is at least 2 (inside a case/cond block).
    case parse_arm_head(line) do
      {:ok, indent} ->
        # Collect the full block of consecutive arms at this indent level
        {block_lines, after_block} = collect_arm_block([line | rest], indent)

        if length(block_lines) >= 2 do
          aligned = align_arm_block(block_lines, indent, ll)
          do_align_case_blocks(after_block, ll, Enum.reverse(aligned) ++ acc)
        else
          do_align_case_blocks(rest, ll, [line | acc])
        end

      :error ->
        do_align_case_blocks(rest, ll, [line | acc])
    end
  end

  # Returns {:ok, indent_size} if the line looks like a case arm head.
  # An arm head matches: <spaces>pattern [when guard] ->
  # and the pattern must not be a lone bare keyword like `do`, `end`, etc.
  defp parse_arm_head(line) do
    stripped = String.trim_leading(line)
    indent = String.length(line) - String.length(stripped)

    cond do
      # Must be indented (inside a block) and end with ->
      indent < 2 ->
        :error

      # Matches: anything followed by optional guard then " ->"
      Regex.match?(~r/^.+\s+->\s*$/, stripped) ->
        {:ok, indent}

      # Collapsed arm: pattern [guard] -> body
      Regex.match?(~r/^.+\s+->\s+\S/, stripped) ->
        {:ok, indent}

      true ->
        :error
    end
  end

  # Collect an arm block: consecutive arm heads + their bodies at the given
  # indent level. Returns {arm_lines_flat, remaining_lines}.
  # arm_lines_flat is a list of {head_line, [body_lines]} tuples flattened back
  # to line lists; we keep it as a flat list here and re-parse below.
  defp collect_arm_block([], _indent), do: {[], []}

  defp collect_arm_block([line | rest] = all, indent) do
    stripped = String.trim_leading(line)

    cond do
      # Skip blank separator lines between arms
      stripped == "" ->
        {more_block, final_rest} = collect_arm_block(rest, indent)
        # Only include blank if we found more arms
        if more_block != [] do
          {more_block, final_rest}
        else
          {[], all}
        end

      true ->
        case parse_arm_head(line) do
          {:ok, ^indent} ->
            {body, after_body} = consume_body(rest, indent)
            {more_block, final_rest} = collect_arm_block(after_body, indent)
            {[{line, body} | more_block], final_rest}

          _ ->
            {[], all}
        end
    end
  end

  # Consume lines that are body lines: indented more than arm indent.
  # Blank lines between arms are NOT consumed - they're arm separators.
  defp consume_body([], _indent), do: {[], []}

  defp consume_body([line | rest] = all, indent) do
    stripped = String.trim_leading(line)
    line_indent = String.length(line) - String.length(stripped)

    cond do
      # Blank line - stop; blank lines separate arms, not part of the body
      stripped == "" ->
        {[], all}

      # Body line (deeper indent)
      line_indent > indent ->
        {body, tail} = consume_body(rest, indent)
        {[line | body], tail}

      true ->
        {[], all}
    end
  end

  # Take a list of {head_line, [body_lines]} arm tuples and produce aligned output lines.
  defp align_arm_block(arms, indent, ll) do
    prefix = String.duplicate(" ", indent)

    # Parse each head: split on first " -> " or trailing " ->"
    parsed =
      Enum.map(arms, fn {head, body} ->
        stripped = String.trim_leading(head)

        case Regex.run(~r/^(.*?)\s+->\s*(.*)$/, stripped) do
          [_, lhs, rhs] ->
            lhs_trimmed = String.trim_trailing(lhs)
            rhs_trimmed = String.trim(rhs)
            # Split lhs into pattern + optional guard
            {pattern, guard} =
              case Regex.run(~r/^(.*?)\s+(when\s+.+)$/, lhs_trimmed) do
                [_, pat, g] -> {String.trim_trailing(pat), g}
                _ -> {lhs_trimmed, nil}
              end

            {pattern, guard, rhs_trimmed, body}

          _ ->
            nil
        end
      end)

    if Enum.any?(parsed, &is_nil/1) do
      Enum.flat_map(arms, fn {head, body} -> [head | body] end)
    else
      # If any arm has a multi-line body, keep all arms expanded but still
      # align tuple patterns within the heads.
      any_multiline_body = Enum.any?(arms, fn {_head, body} -> length(body) > 1 end)

      if any_multiline_body do
        # Align tuple patterns and guards but do NOT pad -> to a common column
        # and do NOT collapse bodies inline.
        patterns = Enum.map(parsed, &elem(&1, 0))
        aligned_patterns = align_tuple_patterns(patterns)
        max_pat_len = aligned_patterns |> Enum.map(&String.length/1) |> Enum.max()

        Enum.zip(aligned_patterns, parsed)
        |> Enum.flat_map(fn {aligned_pat, {_pat, guard, rhs, body}} ->
          head_lhs =
            case guard do
              nil -> aligned_pat
              g ->
                pad = String.duplicate(" ", max_pat_len - String.length(aligned_pat) + 1)
                "#{aligned_pat}#{pad}#{g}"
            end

          if rhs == "" do
            # Multi-line body arm: head ends with ->
            ["#{prefix}#{head_lhs} ->"] ++ body
          else
            # Already-collapsed single-line arm: keep as expanded (body on next line)
            body_prefix = String.duplicate(" ", indent + 2)
            ["#{prefix}#{head_lhs} ->", "#{body_prefix}#{rhs}"] ++ body
          end
        end)
      else
      patterns = Enum.map(parsed, &elem(&1, 0))
      aligned_patterns = align_tuple_patterns(patterns)

      # max aligned-pattern length
      max_pat_len = aligned_patterns |> Enum.map(&String.length/1) |> Enum.max()

      # Build "pattern [pad] guard" lhs strings
      lhs_strings =
        Enum.zip(aligned_patterns, parsed)
        |> Enum.map(fn {aligned_pat, {_pat, guard, _rhs, _body}} ->
          case guard do
            nil ->
              aligned_pat

            g ->
              pad = String.duplicate(" ", max_pat_len - String.length(aligned_pat) + 1)
              "#{aligned_pat}#{pad}#{g}"
          end
        end)

      max_lhs_len = lhs_strings |> Enum.map(&String.length/1) |> Enum.max()

      # Determine which arms can be collapsed inline
      can_collapse =
        Enum.zip(lhs_strings, parsed)
        |> Enum.map(fn {lhs, {_pat, _guard, rhs, body}} ->
          rhs != "" and body == [] and
            String.length("#{prefix}#{lhs}#{String.duplicate(" ", max_lhs_len - String.length(lhs) + 1)}-> #{rhs}") <= ll
        end)

      # If ANY collapsible arm doesn't fit, expand all
      any_cant_inline =
        Enum.any?(Enum.zip(parsed, can_collapse), fn {{_pat, _guard, rhs, body}, can} ->
          rhs != "" and body == [] and not can
        end)

      Enum.zip([lhs_strings, parsed, can_collapse])
      |> Enum.flat_map(fn {lhs, {_pat, _guard, rhs, body}, can} ->
        pad = String.duplicate(" ", max_lhs_len - String.length(lhs) + 1)

        if rhs == "" do
          # Head was already multi-line (blank rhs) - keep body indented below
          ["#{prefix}#{lhs}#{pad}->"] ++ body
        else
          collapsed = "#{prefix}#{lhs}#{pad}-> #{rhs}"

          if can and not any_cant_inline do
            [collapsed]
          else
            # Keep body on next line (re-indent to indent+2)
            body_prefix = String.duplicate(" ", indent + 2)
            ["#{prefix}#{lhs}#{pad}->", "#{body_prefix}#{rhs}"] ++ body
          end
        end
      end)
      end
    end
  end

  # Align all-tuple patterns of the same arity by padding each field.
  defp align_tuple_patterns(patterns) do
    # Check whether all patterns are simple tuples (no nested structures to parse)
    parsed = Enum.map(patterns, &parse_simple_tuple/1)

    case parsed do
      [first | _] when not is_nil(first) ->
        arity = length(first)

        if Enum.all?(parsed, fn p -> not is_nil(p) and length(p) == arity end) do
          # Compute max width per field position
          max_widths =
            Enum.reduce(parsed, List.duplicate(0, arity), fn fields, acc ->
              Enum.zip(fields, acc)
              |> Enum.map(fn {f, m} -> max(String.length(String.trim(f)), m) end)
            end)

          Enum.map(parsed, fn fields ->
            last_idx = length(fields) - 1

            # Build segments: each non-last field contributes "field, " padded so
            # the next field starts at a fixed column.  The last field has no trailing pad.
            segments =
              fields
              |> Enum.with_index()
              |> Enum.map(fn {f, idx} ->
                trimmed = String.trim(f)
                w = Enum.at(max_widths, idx)

                if idx == last_idx do
                  trimmed
                else
                  # Comma sits right after the value; pad after the comma+space so
                  # the following field starts at column (w + 2): "field,  next"
                  pad = String.duplicate(" ", w - String.length(trimmed))
                  "#{trimmed},#{pad} "
                end
              end)

            "{#{Enum.join(segments, "")}}"
          end)
        else
          patterns
        end

      _ ->
        patterns
    end
  end

  # Parse "{a, b, c}" into ["a", "b", "c"], handling nested parens/brackets.
  # Returns nil if the pattern is not a simple tuple literal.
  defp parse_simple_tuple(str) do
    s = String.trim(str)

    if String.starts_with?(s, "{") and String.ends_with?(s, "}") do
      inner = s |> String.slice(1..-2//1) |> String.trim()
      split_tuple_fields(inner)
    else
      nil
    end
  end

  defp split_tuple_fields(inner) do
    # Split on "," but only at nesting depth 0
    {fields, current, depth} =
      inner
      |> String.graphemes()
      |> Enum.reduce({[], "", 0}, fn ch, {fields, cur, depth} ->
        case ch do
          c when c in ["(", "[", "{"] -> {fields, cur <> c, depth + 1}
          c when c in [")", "]", "}"] -> {fields, cur <> c, depth - 1}
          "," when depth == 0 -> {fields ++ [cur], "", depth}
          _ -> {fields, cur <> ch, depth}
        end
      end)

    if depth == 0 do
      all_fields = fields ++ [current]
      if Enum.any?(all_fields, &(&1 == "")), do: nil, else: all_fields
    else
      nil
    end
  end

  # ---------------------------------------------------------------------------
  # Top-level pipeline
  # ---------------------------------------------------------------------------

  defp align_columns(code) do
    code
    |> String.split("\n")
    |> lines_to_groups()
    |> Enum.flat_map(&align_group/1)
    |> Enum.join("\n")
  end

  # Group consecutive lines that share the same alignment type *and* indentation.
  # Blank lines and comment lines at the same indentation are treated as
  # transparent: they are absorbed into the current group rather than breaking
  # it, provided the next non-blank/comment line continues the same pattern.
  # Groups are accumulated in newest-first order, then reversed at the end.
  defp lines_to_groups(lines) do
    lines
    |> Enum.reduce([], fn line, groups ->
      case groups do
        [] ->
          [[line]]

        [current | rest] ->
          group_type = effective_group_type(current)
          group_indent = effective_group_indent(current)

          cond do
            # Pure blank line inside an active keyword/arrow/attribute group: absorb.
            String.trim(line) == "" and group_type != :other ->
              [current ++ [line] | rest]

            # Comment at same indent as an active keyword group: absorb.
            other_line?(line) and group_type != :other and
                get_indent(line) == group_indent ->
              [current ++ [line] | rest]

            # Same type and indent as current group: absorb.
            same_group?(List.last(current), line) ->
              [current ++ [line] | rest]

            # Current group ends in blanks/comments; the new line may still
            # belong to the same group if it matches the group's effective type.
            group_type != :other and line_type(line) == group_type and
                get_indent(line) == group_indent ->
              [current ++ [line] | rest]

            true ->
              [[line] | groups]
          end
      end
    end)
    |> Enum.reverse()
  end

  # Type of the last non-:other line in the group (or :other if none).
  defp effective_group_type(lines) do
    lines
    |> Enum.reverse()
    |> Enum.find_value(:other, fn l ->
      t = line_type(l)
      if t != :other, do: t
    end)
  end

  # Indent of the first non-:other line in the group (or 0 if none).
  defp effective_group_indent(lines) do
    case Enum.find(lines, fn l -> line_type(l) != :other end) do
      nil  -> 0
      line -> get_indent(line)
    end
  end

  defp other_line?(line) do
    line_type(line) == :other
  end

  defp same_group?(line_a, line_b) do
    type_a = line_type(line_a)
    type_b = line_type(line_b)
    type_a != :other and type_a == type_b and get_indent(line_a) == get_indent(line_b)
  end

  # ---------------------------------------------------------------------------
  # Line classification
  # ---------------------------------------------------------------------------

  # Returns the alignment "type" for a line:
  #   :attribute   ->  @attr value
  #   :keyword     ->  key: value  (keyword list / struct field)
  #   :arrow       ->  key => value
  #   :case_arm    ->  pattern -> body  (case/cond/fn arm, one-liner)
  #   :assignment  ->  var = value
  #   :tuple_entry ->  {:atom, value, ...},?
  #   :other       ->  everything else (blank, comment, unrecognised)
  defp line_type(line) do
    stripped = String.trim_leading(line)

    cond do
      stripped == "" or String.starts_with?(stripped, "#") ->
        :other

      # Module attribute with a value (not a call like @spec, which uses parens)
      Regex.match?(~r/^@\w+\s+(?!\()/, stripped) ->
        :attribute

      # Keyword list / struct literal entry:  some_key: value
      Regex.match?(~r/^[a-z_]\w*[?!]?:\s+\S/, stripped) ->
        :keyword

      # Map arrow entry:  key => value  (key may be any expression)
      Regex.match?(~r/^\S.*?\s+=>\s+\S/, stripped) ->
        :arrow
      # Case/cond/fn arm with body on same line:  pattern -> body
      not elixir_keyword?(stripped) and
          Regex.match?(~r/^.+\s+->\s+\S/, stripped) ->
        :case_arm
      # Macro call with atom first arg:  macro :atom, rest  (e.g. field :name, opts)
      not elixir_keyword?(stripped) and
          Regex.match?(~r/^[a-z_]\w*\s+:\w+,\s+\S/, stripped) ->
        case Regex.run(~r/^([a-z_]\w*)/, stripped) do
          [_, macro_name] -> {:macro_arg, macro_name}
          _ -> :other
        end

      # Tuple entry starting with an atom:  {:atom, ...},?
      Regex.match?(~r/^\{:\w+,\s+.+\}\s*,?\s*$/, stripped) ->
        :tuple_entry

      # Simple variable assignment:  var = value  (not ==, !=, <=, >=, =>)
      Regex.match?(~r/^[a-z_]\w*\s+=(?![>=])\s+\S/, stripped) and
          not elixir_keyword?(stripped) ->
        :assignment

      true ->
        :other
    end
  end

  defp elixir_keyword?(stripped) do
    case Regex.run(~r/^([a-z_]\w*)/, stripped) do
      [_, word] -> word in @elixir_keywords
      _ -> false
    end
  end

  defp get_indent(line) do
    String.length(line) - String.length(String.trim_leading(line))
  end

  # ---------------------------------------------------------------------------
  # Group alignment
  # ---------------------------------------------------------------------------

  defp align_group([]), do: []
  defp align_group([line]), do: [line]

  defp align_group(lines) do
    type = effective_group_type(lines)
    # Separate :other lines (blanks/comments), align only the typed lines,
    # then re-insert the :other lines at their original positions.
    {typed_lines, other_positions} =
      lines
      |> Enum.with_index()
      |> Enum.split_with(fn {line, _idx} -> line_type(line) != :other end)

    aligned_typed = do_align(Enum.map(typed_lines, &elem(&1, 0)), type)

    # Reconstruct full list in original order
    typed_with_idx = Enum.zip(aligned_typed, Enum.map(typed_lines, &elem(&1, 1)))
    other_with_idx = Enum.map(other_positions, fn {line, idx} -> {line, idx} end)

    (typed_with_idx ++ other_with_idx)
    |> Enum.sort_by(&elem(&1, 1))
    |> Enum.map(&elem(&1, 0))
  end

  # Keyword list: align the space after the colon
  #   before:  name: "Alice",
  #            age: 30,
  #            occupation: "dev"
  #
  #   after:   name:       "Alice",
  #            age:        30,
  #            occupation: "dev"
  defp do_align(lines, :keyword) do
    parsed =
      Enum.map(lines, fn line ->
        case Regex.run(~r/^(\s*)([a-z_]\w*[?!]?:)\s+(.*)$/, line) do
          [_, indent, key, value] -> {indent, key, value}
          _ -> nil
        end
      end)

    if Enum.all?(parsed, & &1) do
      max_len = parsed |> Enum.map(fn {_, key, _} -> String.length(key) end) |> Enum.max()

      Enum.map(parsed, fn {indent, key, value} ->
        pad = String.duplicate(" ", max_len - String.length(key) + 1)
        "#{indent}#{key}#{pad}#{value}"
      end)
    else
      lines
    end
  end

  # Variable assignment: align the = sign

  defp do_align(lines, :tuple_entry) do
    parsed =
      Enum.map(lines, fn line ->
        case Regex.run(~r/^(\s*)\{(.+)\}(,?)\s*$/, line) do
          [_, indent, contents, trailing] ->
            {:ok, indent, split_tuple_elements(contents), trailing}
          _ ->
            :error
        end
      end)

    if Enum.all?(parsed, &match?({:ok, _, _, _}, &1)) do
      all_elements = Enum.map(parsed, fn {:ok, _, elems, _} -> elems end)
      max_cols = all_elements |> Enum.map(&length/1) |> Enum.max()

      # Max width per column position across all rows
      col_widths =
        Enum.map(0..(max_cols - 2), fn col ->
          all_elements
          |> Enum.flat_map(fn elems ->
            case Enum.at(elems, col) do
              nil  -> []
              elem -> [String.length(elem)]
            end
          end)
          |> Enum.max()
        end)

      Enum.map(parsed, fn {:ok, indent, elems, trailing} ->
        parts =
          elems
          |> Enum.with_index()
          |> Enum.map(fn {elem, idx} ->
            if idx < length(elems) - 1 do
              max_w = Enum.at(col_widths, idx, String.length(elem))
              pad   = String.duplicate(" ", max_w - String.length(elem))
              "#{elem},#{pad}"
            else
              elem
            end
          end)

        "#{indent}{#{Enum.join(parts, " ")}}#{trailing}"
      end)
    else
      lines
    end
  end

  defp do_align(lines, :assignment) do
    parsed =
      Enum.map(lines, fn line ->
        case Regex.run(~r/^(\s*)([a-z_]\w*)\s*=(?![>=])\s*(.*)$/, line) do
          [_, indent, var, value] -> {indent, var, value}
          _ -> nil
        end
      end)

    if Enum.all?(parsed, & &1) do
      max_len = parsed |> Enum.map(fn {_, var, _} -> String.length(var) end) |> Enum.max()

      aligned =
        Enum.map(parsed, fn {indent, var, value} ->
          pad = String.duplicate(" ", max_len - String.length(var) + 1)
          {indent, "#{indent}#{var}#{pad}= #{value}", value}
        end)

      # Second-level: if all RHS are `SamePrefix:atom, value)`, align atom and value columns
      rhs_parsed =
        Enum.map(aligned, fn {_indent, _line, value} ->
          case Regex.run(~r/^(.*,\s*)(:\w+),\s*(.+)\)$/, value) do
            [_, prefix, atom, val] -> {prefix, atom, val}
            _ -> nil
          end
        end)

      final_lines =
        if Enum.all?(rhs_parsed, & &1) do
          prefixes = rhs_parsed |> Enum.map(&elem(&1, 0))

          if length(Enum.uniq(prefixes)) == 1 do
            max_atom_len = rhs_parsed |> Enum.map(fn {_, a, _} -> String.length(a) end) |> Enum.max()

            Enum.zip(aligned, rhs_parsed)
            |> Enum.map(fn {{_indent, line, value}, {prefix, atom, val}} ->
              base = String.slice(line, 0, String.length(line) - String.length(value))
              atom_pad = String.duplicate(" ", max_atom_len - String.length(atom) + 1)
              "#{base}#{prefix}#{atom},#{atom_pad}#{val})"
            end)
          else
            Enum.map(aligned, &elem(&1, 1))
          end
        else
          Enum.map(aligned, &elem(&1, 1))
        end

      final_lines
    else
      lines
    end
  end

  # Module attribute: align the value
  #   before:  @moduledoc "…"
  #            @name "Alice"
  #            @default_timeout 5000
  #
  #   after:   @moduledoc       "…"
  #            @name            "Alice"
  #            @default_timeout 5000
  defp do_align(lines, :attribute) do
    parsed =
      Enum.map(lines, fn line ->
        case Regex.run(~r/^(\s*)(@\w+)\s+(.*)$/, line) do
          [_, indent, attr, value] -> {indent, attr, value}
          _ -> nil
        end
      end)

    if Enum.all?(parsed, & &1) do
      max_len = parsed |> Enum.map(fn {_, attr, _} -> String.length(attr) end) |> Enum.max()

      Enum.map(parsed, fn {indent, attr, value} ->
        pad = String.duplicate(" ", max_len - String.length(attr) + 1)
        "#{indent}#{attr}#{pad}#{value}"
      end)
    else
      lines
    end
  end

  # Map arrow: align the => operator
  #   before:  "name" => "Alice",
  #            "age" => 30,
  #            "occupation" => "dev"
  #
  #   after:   "name"       => "Alice",
  #            "age"        => 30,
  #            "occupation" => "dev"
  defp do_align(lines, :arrow) do
    parsed =
      Enum.map(lines, fn line ->
        case Regex.run(~r/^(\s*)(.*?)\s*=>\s*(.*)$/, line) do
          [_, indent, key, value] -> {indent, String.trim_trailing(key), value}
          _ -> nil
        end
      end)

    if Enum.all?(parsed, & &1) do
      max_len = parsed |> Enum.map(fn {_, key, _} -> String.length(key) end) |> Enum.max()

      Enum.map(parsed, fn {indent, key, value} ->
        pad = String.duplicate(" ", max_len - String.length(key) + 1)
        "#{indent}#{key}#{pad}=> #{value}"
      end)
    else
      lines
    end
  end

  # Macro call with atom first arg: align the rest after the comma
  #   before:  field :guest_name, function: &foo/1
  #            field :reservation_code, function: &bar/1
  #
  #   after:   field :guest_name,       function: &foo/1
  #            field :reservation_code, function: &bar/1
  defp do_align(lines, {:macro_arg, _}) do
    parsed =
      Enum.map(lines, fn line ->
        case Regex.run(~r/^(\s*)([a-z_]\w*)\s+(:\w+),\s+(.*)$/, line) do
          [_, indent, macro, atom, rest] -> {indent, macro, atom, rest}
          _ -> nil
        end
      end)

    if Enum.all?(parsed, & &1) do
      max_prefix_len =
        parsed
        |> Enum.map(fn {_, macro, atom, _} -> String.length(macro) + 1 + String.length(atom) end)
        |> Enum.max()

      # Level-1 aligned lines (macro + first atom)
      level1 =
        Enum.map(parsed, fn {indent, macro, atom, rest} ->
          prefix_len = String.length(macro) + 1 + String.length(atom)
          pad = String.duplicate(" ", max_prefix_len - prefix_len + 1)
          {indent, macro, atom, pad, rest}
        end)

      # Try level-2 alignment: rest matches `(:type_atom), (kw_key:) (kw_value)`
      rest_parsed =
        Enum.map(level1, fn {_, _, _, _, rest} ->
          case Regex.run(~r/^(:\w+),\s+(\w+:)\s+(.+)$/, rest) do
            [_, type_atom, kw_key, kw_val] -> {type_atom, kw_key, kw_val}
            _ -> nil
          end
        end)

      level1_lines =
        if Enum.all?(rest_parsed, & &1) do
          max_type_len =
            rest_parsed
            |> Enum.map(fn {type_atom, _, _} -> String.length(type_atom) end)
            |> Enum.max()

          max_kw_key_len =
            rest_parsed
            |> Enum.map(fn {_, kw_key, _} -> String.length(kw_key) end)
            |> Enum.max()

          Enum.zip(level1, rest_parsed)
          |> Enum.map(fn {{indent, macro, atom, pad, _}, {type_atom, kw_key, kw_val}} ->
            type_pad = String.duplicate(" ", max_type_len - String.length(type_atom) + 1)
            kw_pad = String.duplicate(" ", max_kw_key_len - String.length(kw_key) + 1)
            "#{indent}#{macro} #{atom},#{pad}#{type_atom},#{type_pad}#{kw_key}#{kw_pad}#{kw_val}"
          end)
        else
          Enum.map(level1, fn {indent, macro, atom, pad, rest} ->
            "#{indent}#{macro} #{atom},#{pad}#{rest}"
          end)
        end

      level1_lines
    else
      lines
    end
  end

  # Case/cond/fn arm: align the -> operator
  #   before:  [value] -> t.(value)
  #            _ -> nil
  #
  #   after:   [value] -> t.(value)
  #            _       -> nil
  defp do_align(lines, :case_arm) do
    parsed =
      Enum.map(lines, fn line ->
        case Regex.run(~r/^(\s*)(.*?)\s+->\s+(.+)$/, line) do
          [_, indent, pattern, body] -> {indent, String.trim_trailing(pattern), body}
          _ -> nil
        end
      end)

    if Enum.all?(parsed, & &1) do
      max_len = parsed |> Enum.map(fn {_, pattern, _} -> String.length(pattern) end) |> Enum.max()

      Enum.map(parsed, fn {indent, pattern, body} ->
        pad = String.duplicate(" ", max_len - String.length(pattern) + 1)
        "#{indent}#{pattern}#{pad}-> #{body}"
      end)
    else
      lines
    end
  end

  defp do_align(lines, _), do: lines

  # Split a tuple's content string by ", " at bracket depth 0.
  defp split_tuple_elements(str) do
    {elems, current, _depth} =
      str
      |> String.graphemes()
      |> Enum.reduce({[], "", 0}, fn
        ch, {elems, curr, depth} when ch in ["[", "{", "("] ->
          {elems, curr <> ch, depth + 1}

        ch, {elems, curr, depth} when ch in ["]", "}", ")"] ->
          {elems, curr <> ch, depth - 1}

        ",", {elems, curr, 0} ->
          {elems ++ [curr], "", 0}

        " ", {elems, "", 0} ->
          # skip leading space after a split
          {elems, "", 0}

        ch, {elems, curr, depth} ->
          {elems, curr <> ch, depth}
      end)

    elems ++ [current]
  end
end
