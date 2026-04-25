defmodule ExAlign.CLI do
  @moduledoc """
  Command-line interface for ExAlign.

  ## Usage

      exalign [options] <file|dir> [<file|dir> ...]

  ## Options

      --line-length N       Maximum line length (default: 98)
      --wrap-short-lines    Re-wrap lines that are shorter than line-length
      --wrap-with backslash|do  How to wrap `do` expressions (default: backslash)
      --eol-at-eof add|remove  End-of-file newline handling
      --trim-eol-ws         Trim trailing whitespace from each line (default: true)
      --no-trim-eol-ws      Do not trim trailing whitespace
      --check               Check formatting without writing files; exit 1 if any
                            file would be changed
      --dry-run             Print would-be changes without writing files
      --no-summary          Suppress summary output in --check and --dry-run modes
      -s, --silent          Suppress all stdout output
      -h, --help            Print this help

  ## Global configuration

  Default values for `--line-length`, `--wrap-short-lines`, `--wrap-with`,
  `--eol-at-eof`, and `--trim-eol-ws` can be set in
  `~/.config/exalign/.formatter.exs`. CLI flags always take precedence over
  that file. See `ExAlign` module docs for the file format.

  ## Examples

      exalign lib/
      exalign --line-length 120 lib/ test/
      exalign --check lib/
  """

  @switches [
    line_length:      :integer,
    wrap_short_lines: :boolean,
    wrap_with:        :string,
    eol_at_eof:       :string,
    trim_eol_ws:      :boolean,
    check:            :boolean,
    dry_run:          :boolean,
    silent:           :boolean,
    no_summary:       :boolean,
    help:             :boolean
  ]

  @aliases [h: :help, s: :silent]

  def main(argv) do
    case run(argv) do
      :ok            -> :ok
      {:error, code} -> System.halt(code)
    end
  end

  @doc """
  Parses `argv` and runs the formatter. Returns `:ok` on success or
  `{:error, exit_code}` on failure. Does **not** call `System.halt/1`, making
  it safe to call from tests.
  """
  def run(argv) do
    {opts, paths, invalid} = OptionParser.parse(argv, strict: @switches, aliases: @aliases)

    cond do
      invalid != [] ->
        for {flag, _} <- invalid, do: warn("Unknown option: #{flag}")
        {:error, 1}
      opts[:help] ->
        IO.puts(@moduledoc)
        :ok
      paths == [] ->
        IO.puts(@moduledoc)
        {:error, 1}
      true ->
        format_opts = build_format_opts(opts)
        silent      = opts[:silent] || false
        no_summary  = opts[:no_summary] || false

        mode =
          cond do
            opts[:check]   -> :check
            opts[:dry_run] -> :dry_run
            true           -> :write
          end

        paths
        |> Enum.flat_map(&collect_files/1)
        |> Enum.reduce({:ok, 0}, fn file, {status, count} ->
          case process_file(file, format_opts, mode, silent) do
            :ok      -> {status, count}
            :changed -> {:changed, count + 1}
            :error   -> {:error, count}
          end
        end)
        |> case do
          {:ok,      _} ->
            :ok
          {:changed, n} ->
            silent || no_summary || IO.puts(:stderr, "#{n} file(s) would be reformatted")
            {:error, 1}
          {:error,   _} ->
            {:error, 1}
        end
    end
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  defp build_format_opts(opts) do
    # Start from global config defaults; CLI flags override them.
    format_opts = ExAlign.load_global_config()

    format_opts =
      if opts[:line_length],
        do:   Keyword.put(format_opts, :line_length, opts[:line_length]),
        else: format_opts

    format_opts =
      if opts[:wrap_short_lines],
        do:   Keyword.put(format_opts, :wrap_short_lines, true),
        else: format_opts

    format_opts =
      if opts[:wrap_with],
        do:   Keyword.put(format_opts, :wrap_with, String.to_atom(opts[:wrap_with])),
        else: format_opts

    format_opts =
      if opts[:eol_at_eof],
        do:   Keyword.put(format_opts, :eol_at_eof, String.to_atom(opts[:eol_at_eof])),
        else: format_opts

    format_opts =
      if opts[:trim_eol_ws] != nil,
        do:   Keyword.put(format_opts, :trim_eol_ws, opts[:trim_eol_ws]),
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

  defp process_file(path, format_opts, mode, silent) do
    original  = File.read!(path)
    formatted = ExAlign.format(original, format_opts)

    cond do
      formatted == original ->
        :ok
      mode == :check ->
        silent || IO.puts(:stderr, "would reformat: #{path}")
        :changed
      mode == :dry_run ->
        silent || IO.puts("--- #{path}")
        silent || IO.puts(formatted)
        :changed
      true ->
        File.write!(path, formatted)
        silent || IO.puts("reformatted: #{path}")
        :ok
    end
  rescue
    e ->
      warn("Error processing #{path}: #{Exception.message(e)}")
      :error
  end

  defp warn(msg), do: IO.puts(:stderr, "exalign: #{msg}")
end
