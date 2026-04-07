# ExAlign

A Mix formatter plugin that column-aligns Elixir code, inspired by how Go's
`gofmt` aligns struct fields and variable declarations, which are more readable
than the output of the default Elixir code formatter.

## What it does

`ExAlign` runs as a pass on top of the standard Elixir formatter. It
scans consecutive lines that share the same indentation and pattern type, then
pads them so their operators and values line up vertically. It also collapses
short `->` arms back to one line when they fit within the line-length limit.

### Keyword list / struct fields

```elixir
# before
%User{name: "Alice", age: 30, occupation: "developer"}

# after (multi-line, as produced by Code.format_string!)
%User{
  name:       "Alice",
  age:        30,
  occupation: "developer"
}
```

### Variable assignments

```elixir
# before
x = 1
foo = "bar"
something_long = 42

# after
x              = 1
foo            = "bar"
something_long = 42
```

### Module attributes

```elixir
# before
@name "Alice"
@version "1.0.0"
@default_timeout 5_000

# after
@name            "Alice"
@version         "1.0.0"
@default_timeout 5_000
```

### Map fat-arrow entries

```elixir
# before
%{"name" => "Alice", "age" => 30, "occupation" => "developer"}

# after (multi-line)
%{
  "name"       => "Alice",
  "age"        => 30,
  "occupation" => "developer"
}
```

### Macro calls with an atom first argument

Consecutive calls of the same macro that follow the pattern `macro :atom, rest`
are kept paren-free and aligned at the second argument:

```elixir
# before
field :reservation_code, function: &extract_reservation_code/1
field :guest_name, function: &extract_guest_name/1
field :check_in_date, function: &extract_check_in_date/1
field :nights, pattern: ~r/(\d+)\s+nights/, capture: :first, transform: &String.to_integer/1

# after
field :reservation_code, function: &extract_reservation_code/1
field :guest_name,       function: &extract_guest_name/1
field :check_in_date,    function: &extract_check_in_date/1
field :nights,           pattern: ~r/(\d+)\s+nights/, capture: :first, transform: &String.to_integer/1
```

Macro names are **auto-detected** from the source: any bare macro name that
appears two or more times with this shape is automatically added to
`locals_without_parens` so the standard formatter does not add parentheses.
Only lines with the **same macro name** and **same indentation** form a group.

### Arrow-clause collapsing

Short `->` arms (pattern + single-line body) that the standard formatter expands
are collapsed back to one line when the result fits within `line_length`:

```elixir
# standard formatter output
case result do
  {:ok, value} ->
    value

  {:error, _} = err ->
    err
end

# ExAlign output
case result do
  {:ok, value}      -> value
  {:error, _} = err -> err
end
```

Arms whose body would exceed `line_length`, or arms with multi-line bodies, are
left expanded.

## Installation

### As a path dependency (local development)

```elixir
# mix.exs
defp deps do
  [{:ex_align, path: "/path/to/formatter"}]
end
```

### From Hex (once published)

```elixir
defp deps do
  [{:ex_align, "~> 0.1"}]
end
```

Then fetch dependencies:

```bash
mix deps.get
```

## Usage

Register the plugin in your project's `.formatter.exs`:

```elixir
[
  plugins: [ExAlign],
  inputs:  ["{mix,.formatter}.exs", "{config,lib,test}/**/*.{ex,exs}"]
]
```

Run the formatter as usual:

```bash
mix format
```

`ExAlign` runs **after** `Code.format_string!`, so the standard Elixir
style is preserved and column alignment is layered on top.

## Standalone `exalign` executable

`exalign` is a self-contained escript that formats Elixir files without
requiring a Mix project. Download the latest binary from the
[GitHub releases page](https://github.com/saleyn/exalign/releases/latest) and place it somewhere on your
`$PATH`.

### Usage

```
exalign [options] <file|dir> [<file|dir> ...]
```

Files are formatted in-place. Directories are walked recursively for
`*.ex` and `*.exs` files.

### Options

| Flag | Default | Description |
|---|---|---|
| `--line-length N` | `98` | Maximum line length |
| `--wrap-short-lines` | off | Keep `->` arms expanded instead of collapsing them |
| `--wrap-with backslash\|do` | `backslash` | How to format multi-line `with` blocks |
| `--check` | off | Exit 1 if any file would be changed; write nothing |
| `--dry-run` | off | Print reformatted content to stdout; write nothing || `-s`, `--silent` | off | Suppress stdout output (stderr warnings still shown) || `-h`, `--help` | | Print usage |

### Examples

```bash
# Format all Elixir files under lib/ and test/
exalign lib/ test/

# Use a longer line limit
exalign --line-length 120 lib/

# CI check — fail if anything is out of alignment
exalign --check lib/ test/

# Preview changes without writing
exalign --dry-run lib/my_module.ex
```

### Building from source

```bash
git clone https://github.com/your-org/ex_align.git
cd ex_align
make escript        # produces ./exalign
```

## Options

Options are passed through `.formatter.exs` alongside the standard formatter
options. Here is a full example with all options set explicitly:

```elixir
# .formatter.exs
[
  plugins:               [ExAlign],
  inputs:                ["{mix,.formatter}.exs", "{config,lib,test}/**/*.{ex,exs}"],
  line_length:           98,
  wrap_short_lines:      false,
  wrap_with:             :backslash,
  locals_without_parens: [field: :*, validate: 2]
]
```

Only include options you need to override — unset options use their defaults.

### `line_length` (integer, default `98`)

Maximum line length forwarded to `Code.format_string!` and used as the threshold
for arrow-clause collapsing. When aligned macro-call lines are longer than this
value, the limit is automatically raised to the longest such line so the
formatter does not break them.

Arms whose collapsed form would exceed `line_length` are left expanded:

```elixir
# line_length: 60
case result do
  {:ok,    value}  -> transform_and_process(value)
  {:error, reason} -> {:error, reason}
end

# line_length: 40  — first arm no longer fits inline
case result do
  {:ok,    value}  ->
    transform_and_process(value)
  {:error, reason} -> {:error, reason}
end
```

```elixir
# .formatter.exs
[
  plugins:     [ExAlign],
  line_length: 120,
  inputs:      ["{mix,.formatter}.exs", "{config,lib,test}/**/*.{ex,exs}"]
]
```

### `wrap_short_lines` (boolean, default `false`)

When `true`, disables the arrow-clause collapsing pass. The standard
formatter's expanded form for `->` arms is preserved as-is.

```elixir
# wrap_short_lines: false (default) — arms collapsed and aligned
case result do
  {:ok, value}     -> value
  {:error, reason} -> {:error, reason}
  _                -> nil
end

# wrap_short_lines: true — arms stay expanded
case result do
  {:ok, value}     ->
    value
  {:error, reason} ->
    {:error, reason}
  _                ->
    nil
end
```

```elixir
# .formatter.exs
[
  plugins:          [ExAlign],
  wrap_short_lines: true,
  inputs:           ["{mix,.formatter}.exs", "{config,lib,test}/**/*.{ex,exs}"]
]
```

### `locals_without_parens` (keyword list)

Merged with the macro names that `ExAlign` auto-detects. Use this to
explicitly list macros that should remain paren-free, exactly as you would for
the standard formatter.

```elixir
# without locals_without_parens — formatter adds parens
preprocess(:name, &String.trim/1)
preprocess(:email, &String.downcase/1)

# with locals_without_parens: [preprocess: 2]
preprocess :name,  &String.trim/1
preprocess :email, &String.downcase/1
```

```elixir
# .formatter.exs
[
  plugins:               [ExAlign],
  locals_without_parens: [field: :*, preprocess: 2],
  inputs:                ["{mix,.formatter}.exs", "{config,lib,test}/**/*.{ex,exs}"]
]
```

Auto-detected names and explicitly listed names are merged; duplicates are
removed automatically.

### `wrap_with` (boolean or atom, default `:backslash`)

Controls how `with` blocks whose clauses span multiple lines are formatted:

| Value | Behaviour |
|---|---|
| `false` | Leave `do` at the end of the last clause (standard formatter output). |
| `true` | Extract `do` onto its own line at the `with` keyword's indentation level. |
| `:backslash` | Like `true`, **and** replace `with` with `with \` and re-indent all clauses two spaces in. |

```elixir
# wrap_with: false  (standard output)
with {:ok, a} <- foo(),
     {:ok, b} <- bar(a) do
  {:ok, {a, b}}
end

# wrap_with: true
with {:ok, a} <- foo(),
     {:ok, b} <- bar(a)
do
  {:ok, {a, b}}
end

# wrap_with: :backslash  (default)
with \
  {:ok, a} <- foo(),
  {:ok, b} <- bar(a)
do
  {:ok, {a, b}}
end
```

```elixir
# .formatter.exs
[
  plugins:   [ExAlign],
  wrap_with: true,
  inputs:    ["{mix,.formatter}.exs", "{config,lib,test}/**/*.{ex,exs}"]
]
```

## Alignment rules

| Pattern | Aligned element | Example trigger |
|---|---|---|
| `:keyword` | space after atom key | `name: value` |
| `:assignment` | `=` sign | `var = value` |
| `:attribute` | value after `@attr` | `@attr value` |
| `:arrow` | `=>` operator | `"key" => value` |
| `{:macro_arg, name}` | second argument after `,` | `field :name, opts` |

**Grouping:** only consecutive lines with the **same indentation** and **same
pattern** (including the same macro name for `:macro_arg`) are aligned together.
A blank line, a `#` comment, or a change in pattern or indent level always
breaks the group. A group of one line is never modified.

## Running tests

```bash
mix test
```

## Contributing

All change requests must be accompanied by:

1. **An input fixture** — a minimal `.ex` file placed in `test/fixtures/input/`
   that reproduces the formatting behaviour being added or changed.
2. **An expected output fixture** — the corresponding file in
   `test/fixtures/expected/` showing exactly what `ExAlign` should
   produce.

Once both files are in place, regenerate the expected file and confirm the test
suite passes:

```bash
mix fmt.regenerate_tests
mix test
```

Pull requests that change formatting behaviour without a corresponding fixture
pair will not be accepted.

## Requirements

- Elixir `~> 1.13`
- No external dependencies

## Disclaimer

`ExAlign` **rewrites your source files in place**. While it is designed
to be idempotent and purely cosmetic, any tool that modifies code carries a risk
of introducing unexpected changes.

**Use version control.** Always run the formatter on a clean working tree so
that you can review the diff and revert if needed.

The authors provide this software **as-is**, without warranty of any kind.
They shall not be liable for any loss or corruption of source code, data, or
other assets arising from the use of this tool. See the full disclaimer in
the [MIT License](https://github.com/saleyn/exalign/blob/main/LICENSE).

## License

MIT License. Copyright (c) 2026 Serge Aleynikov. See [LICENSE](https://github.com/saleyn/exalign/blob/main/LICENSE).
