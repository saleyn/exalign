# ExAlign

[![build](https://github.com/saleyn/exalign/actions/workflows/ci.yml/badge.svg)](https://github.com/saleyn/exalign/actions/workflows/ci.yml)
[![Hex.pm](https://img.shields.io/hexpm/v/exalign.svg)](https://hex.pm/packages/exalign)
[![Hex.pm](https://img.shields.io/hexpm/dt/exalign.svg)](https://hex.pm/packages/exalign)

A column-aligning code formatter for Elixir—inspired by how Go's `gofmt` aligns struct fields and variable declarations, which are more readable than standard formatter output.

> **Looking for Erlang formatting?** Check out **[ErlAlign](https://github.com/saleyn/erlalign)**, a separate rebar3-based project for Erlang code.

## What it does

`ExAlign` runs as a pass on top of the standard Elixir formatter. It
scans consecutive lines that share the same indentation and pattern type, then
pads them so their operators and values line up vertically. It also:

- Collapses short `->` arms back to one line when they fit within the line-length limit
- Aligns `->` operators vertically in case and cond blocks 
- Aligns complex case patterns, guards, and arrows across arms
- Extracts `do` keywords to their own line for complex block headers
- Auto-detects and registers paren-free macros from aligned groups

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

### Case arm alignment

Aligns the `->` operator vertically across consecutive case arms:

```elixir
# before
case Regex.run(pattern, text) do
  [value] -> transform.(value)
  _       -> nil
end

# after
case Regex.run(pattern, text) do
  [value] -> transform.(value)
  _       -> nil
end
```

### Cond arm alignment

Aligns the `->` operator vertically across consecutive cond arms:

```elixir
# before
cond do
  x > 100 -> :large
  x > 10  -> :medium
  true    -> :small
end

# after
cond do
  x > 100 -> :large
  x > 10  -> :medium
  true    -> :small
end
```

### Case block alignment (complex patterns with guards)

Aligns tuple patterns, guards, and the `->` operator across case arms **only
when all clauses are single-line** (pattern plus body fit on one line). If any
clause has a multi-line body, the entire block is left unaligned:

```elixir
# all one-liners — aligned
case {a, b} do
  {nil,   nil}                    -> :both_nil
  {x,     nil} when is_integer(x) -> {:left, x}
  {nil,   y}                      -> {:right, y}
  {x,     y}                      -> {x, y}
end

# mixed: last clause has multi-line body — NOT aligned
case {Keyword.get(opts, :components), Keyword.get(opts, :structs)} do
  {nil, nil} ->
    raise ArgumentError, "must pass either :components or :structs"
  {comps, nil} when is_list(comps) ->
    {comps, false}
  {_, structs} when is_list(structs) ->
    {structs, true}
end
```

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

### Do extraction for complex headers

For `case`, `cond`, `with`, and other block expressions with complex (multi-line)
headers, the `do` keyword is automatically moved to its own line for readability:

```elixir
# before (multi-line header)
case list
     |> Enum.filter(&is_integer/1)
     |> Enum.sort() do
  [] -> :empty
  _ -> :ok
end

# after
case list
     |> Enum.filter(&is_integer/1)
     |> Enum.sort()
do
  [] -> :empty
  _ -> :ok
end
```

Single-line headers are left unchanged.

### With block formatting

ExAlign handles multi-line `with` blocks with flexible formatting options controlled
by the `wrap_with` configuration. When a `with` block spans multiple lines, you can
choose how to format it:

#### Standard formatter output (wrap_with: false)
```elixir
with {:ok, a} <- foo(),
     {:ok, b} <- bar(a) do
  {:ok, {a, b}}
end
```

#### Do on separate line (wrap_with: true)
```elixir
with {:ok, a} <- foo(),
     {:ok, b} <- bar(a)
do
  {:ok, {a, b}}
end
```

#### Backslash wrapping (wrap_with: :backslash, default)
Combines `do` extraction with a backslash after `with` and re-indents the clauses:

```elixir
with \
  {:ok, a} <- foo(),
  {:ok, b} <- bar(a)
do
  {:ok, {a, b}}
end
```

The backslash style (`wrap_with: :backslash`) is the default as it provides visual
clarity that the `with` clauses are a continuation rather than the clause structure
of normal pattern matching.

## Installation

### As a library dependency

Add to your `mix.exs`:

```elixir
defp deps do
  [{:exalign, "~> 0.1", only: :dev}]
end
```

Then fetch dependencies:

```bash
mix deps.get
```

## Usage

Run the installer task to automatically create `.formatter.exs` in your project:

```bash
mix exalign.install
```

This creates `.formatter.exs` if it does not exist yet, or tells you how to
update it manually if a custom one is already present.

Alternatively, register the plugin in your project's `.formatter.exs` manually:

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

## Programmatic usage

You can also use ExAlign directly as a library:

```elixir
# Format a single code string
code = """
x = 1
foo = "bar"
something_long = 42
"""

formatted = ExAlign.format(code, line_length: 120)
# => x              = 1\nfoo            = "bar"\nsomething_long = 42
```

Or in batch operations:

```elixir
"lib/**/*.ex"
|> Path.wildcard()
|> Enum.each(fn file ->
  code = File.read!(file)
  formatted = ExAlign.format(code, line_length: 120)
  File.write!(file, formatted)
end)
```

## Configuration

When using ExAlign as a formatter plugin, you can pass options in `.formatter.exs`:

```elixir
[
  plugins: [ExAlign],
  inputs:  ["{mix,.formatter}.exs", "{config,lib,test}/**/*.{ex,exs}"],
  
  # ExAlign-specific options
  line_length:  120,
  wrap_with:    :backslash,
  eol_at_eof:   :add,
  trim_eol_ws:  true
]
```

Global configuration is also supported via `~/.config/exalign/.formatter.exs`:

```elixir
[
  line_length: 120,
  wrap_with:   :backslash,
  eol_at_eof:  :add,
  trim_eol_ws: true
]
```

Project-local options always take precedence over global configuration.

### Supported options

- `:line_length` (integer, default `98`)  
  Maximum line length. Used for both ExAlign alignment decisions and collapsing short `->` arms.

- `:wrap_with` (`:do`, `:backslash`, or `false`, default `:backslash`)  
  How to format multi-line `with` blocks. With `:backslash`, a backslash continuation is inserted after `with`, and clauses are re-indented. With `:do`, the `do` keyword is extracted to its own line. With `false`, the standard Elixir formatter output is used unchanged.

- `:collapse_arrow_arms` (boolean, default `true`)  
  When `true`, short `->` arms are collapsed to one line if they fit within `line_length`.

- `:extract_do` (boolean, default `true`)  
  When `true`, the `do` keyword is extracted to its own line for complex block headers.

- `:eol_at_eof` (`:add`, `:remove`, or `nil`, default `nil`)  
  Controls the end-of-file newline handling. With `:add`, a trailing newline is added if not present. With `:remove`, any trailing newline is removed. With `nil` (default), the end-of-file newline is left unchanged.

- `:trim_eol_ws` (boolean, default `true`)  
  When `true`, trailing whitespace is trimmed from each line. When `false`, trailing whitespace is left untouched.

## Standalone `exalign` executable

`exalign` is a self-contained escript that formats Elixir files without
requiring a Mix project. Download the latest binary from the
[GitHub releases page](https://github.com/saleyn/exalign/releases/latest) and place it somewhere on your `$PATH`.

### Usage

```
exalign [options] <file|dir> [<file|dir> ...]
```

Files are formatted in-place. Directories are walked recursively for `*.ex` and `*.exs` files.

### Program Options

| Flag | Default | Description |
|---|---|---|
| `--line-length N` | `98` | Maximum line length |
| `--wrap-short-lines` | off | Keep `->` arms expanded instead of collapsing them |
| `--wrap-with backslash\|do` | `backslash` | How to format multi-line `with` blocks |
| `--eol-at-eof add\|remove` | unset | End-of-file newline handling (unset means leave unchanged) |
| `--trim-eol-ws` / `--no-trim-eol-ws` | on | Trim or don't trim trailing whitespace from each line |
| `--check` | off | Exit 1 if any file would be changed; write nothing |
| `--dry-run` | off | Print reformatted content to stdout; write nothing |
| `-s`, `--silent` | off | Suppress stdout output (stderr warnings still shown) |
| `-h`, `--help` | | Print usage |

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
git clone https://github.com/saleyn/exalign.git
cd exalign
make escript        # produces ./exalign
```

## License

MIT License - see LICENSE file
