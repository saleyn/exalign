defmodule Mix.Tasks.Fmt.RegenerateTests do
  @shortdoc "Regenerate fixtures/expected/ from fixtures/input/"
  @moduledoc """
  Runs `ExAlign.format/2` on every `.ex` file in `fixtures/input/`
  and writes the result to the matching file in `fixtures/expected/`.

  ## Usage

      mix fmt.regenerate_tests

  Run `mix test` afterwards to confirm the updated expected files match the
  current formatter output.
  """

  use Mix.Task

  @impl Mix.Task
  def run(_args) do
    input_dir = Path.join([File.cwd!(), "dev", "test", "fixtures", "input"])
    expected_dir = Path.join([File.cwd!(), "dev", "test", "fixtures", "expected"])

    File.mkdir_p!(expected_dir)

    Path.wildcard(Path.join(input_dir, "*.ex"))
    |> Enum.each(fn input_path ->
      out = ExAlign.format(File.read!(input_path), [])
      expected_path = Path.join(expected_dir, Path.basename(input_path))
      File.write!(expected_path, out)
      Mix.shell().info("  updated #{Path.relative_to_cwd(expected_path)}")
    end)
  end
end
