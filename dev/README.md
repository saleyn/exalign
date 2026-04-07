# dev/

This directory contains Mix tasks that are **only available in this project**
and are never published to or compiled by downstream dependents.

`mix.exs` includes `dev/` in `elixirc_paths` exclusively for the `:dev`
environment:

```elixir
defp elixirc_paths(:dev), do: ["lib", "dev"]
defp elixirc_paths(_),    do: ["lib"]
```

When another project adds `:ex_align` as a dependency, Mix compiles
only `lib/`, so none of the modules in `dev/` are ever compiled or made
available there.

## Test Fixtures

The fixture files live in `dev/test/fixtures/` rather than under `test/`
because Mix scans everything beneath `test/` when loading tests and emits a
warning for any `.ex` file that does not match the configured
`test_load_filters` pattern (default: `*_test.exs`). Fixture source files are
plain `.ex` files, not test files, so placing them under `test/` triggers that
warning. Keeping them here, co-located with the dev-only regeneration task, is
the cleanest way to silence the warning without patching `mix.exs`.

## Tasks

### `mix fmt.regenerate_tests`

Runs `ExAlign.format/2` on every `.ex` file in
`dev/test/fixtures/input/` and writes the result to the matching file in
`dev/test/fixtures/expected/`. Used to update expected fixture outputs after
a formatter change.

```bash
mix fmt.regenerate_tests
mix test
```
