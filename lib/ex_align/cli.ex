defmodule ExAlign.CLI do
  @moduledoc """
  Command-line interface for ExAlign.

  ## Usage

      exalign [options] <file|dir> [<file|dir> ...]

  ## Options

      --line-length N       Maximum line length (default: 98)
      --wrap-short-lines    Re-wrap lines that are shorter than line-length
      --wrap-with backslash|do  How to wrap `do` expressions (default: backslash)
      --check               Check formatting without writing files; exit 1 if any
                            file would be changed
      --dry-run             Print would-be changes without writing files
      -h, --help            Print this help

  ## Examples

      exalign lib/
      exalign --line-length 120 lib/ test/
      exalign --check lib/
  """

  @switches [
    line_length: :integer,
    wrap_short_lines: :boolean,
    wrap_with: :string,
    check: :boolean,
    dry_run: :boolean,
    help: :boolean
  ]

  @aliases [h: :help]

  def main(argv) do
    {opts, paths, invalid} = OptionParser.parse(argv, strict: @switches, aliases: @aliases)

    if invalid != [] do
      for {flag, _} <- invalid, do: warn("Unknown option: #{flag}")
      halt(1)
    end

    if opts[:help] || paths == [] do
      IO.puts(@moduledoc)
      if paths == [], do: halt(1)
      halt(0)
    end

    format_opts = build_format_opts(opts)
    mode = cond do
      opts[:check]   -> :check
      opts[:dry_run] -> :dry_run
      true           -> :write
    end

    paths
    |> Enum.flat_map(&collect_files/1)
    |> Enum.reduce({:ok, 0}, fn file, {status, count} ->
      case process_file(file, format_opts, mode) do
        :ok      -> {status, count}
        :changed -> {:changed, count + 1}
        :error   -> {:error, count}
      end
    end)
    |> case do
      {:ok, _}      -> :ok
      {:changed, n} ->
        IO.puts(:stderr, "#{n} file(s) would be reformatted")
        halt(1)
      {:error, _}   ->
        halt(1)
    end
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  defp build_format_opts(opts) do
    format_opts = []

    format_opts =
      if opts[:line_length],
        do: Keyword.put(format_opts, :line_length, opts[:line_length]),
        else: format_opts

    format_opts =
      if opts[:wrap_short_lines],
        do: Keyword.put(format_opts, :wrap_short_lines, true),
        else: format_opts

    format_opts =
      if opts[:wrap_with],
        do: Keyword.put(format_opts, :wrap_with, String.to_existing_atom(opts[:wrap_with])),
        else: format_opts

    format_opts
  end

  defp collect_files(path) do
    cond do
      File.dir?(path) ->
        Path.wildcard(Path.join(path, "**/*.{ex,exs}"))

      File.regular?(path) ->
        if String.ends_with?(path, [".ex", ".exs"]), do: [path], else: []

      true ->
        warn("Path not found: #{path}")
        []
    end
  end

  defp process_file(path, format_opts, mode) do
    original = File.read!(path)
    formatted = ExAlign.format(original, format_opts)

    cond do
      formatted == original ->
        :ok

      mode == :check ->
        IO.puts(:stderr, "would reformat: #{path}")
        :changed

      mode == :dry_run ->
        IO.puts("--- #{path}")
        IO.puts(formatted)
        :changed

      true ->
        File.write!(path, formatted)
        IO.puts("reformatted: #{path}")
        :ok
    end
  rescue
    e ->
      warn("Error processing #{path}: #{Exception.message(e)}")
      :error
  end

  defp warn(msg), do: IO.puts(:stderr, "exalign: #{msg}")

  defp halt(code), do: System.halt(code)
end
