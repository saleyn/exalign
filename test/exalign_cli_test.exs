defmodule ExAlign.CLITest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp run(args), do: ExAlign.CLI.run(args)
  defp run_silent(args), do: ExAlign.CLI.run(args ++ ["--silent"])
  defp run_no_summary(args), do: ExAlign.CLI.run(args ++ ["--no-summary"])

  defp with_tmp_file(content, ext \\ ".ex", fun) do
    path =
      Path.join(System.tmp_dir!(), "exalign_test_#{:erlang.unique_integer([:positive])}#{ext}")

    File.write!(path, content)

    try do
      fun.(path)
    after
      File.rm(path)
    end
  end

  defp with_tmp_dir(fun) do
    dir = Path.join(System.tmp_dir!(), "exalign_test_dir_#{:erlang.unique_integer([:positive])}")
    File.mkdir_p!(dir)

    try do
      fun.(dir)
    after
      File.rm_rf(dir)
    end
  end

  # Source that ExAlign will change (unaligned assignments)
  @unaligned """
  defmodule M do
    def f do
      x              = 1
      foo            = "bar"
      something_long = 42
    end
  end
  """

  # Source that ExAlign leaves unchanged (already aligned, no trailing newline)
  @already_aligned "defmodule M do\nend"

  # ---------------------------------------------------------------------------
  # --help / no args
  # ---------------------------------------------------------------------------

  test "prints usage and returns ok with --help" do
    output =
      capture_io(fn -> assert run_silent(["--help"]) == :ok end)

    assert output =~ "exalign"
  end

  test "prints usage and returns error with no args" do
    output =
      capture_io(fn -> assert run_silent([]) == {:error, 1} end)

    assert output =~ "exalign"
  end

  # ---------------------------------------------------------------------------
  # Unknown flag
  # ---------------------------------------------------------------------------

  test "returns error for unknown flag" do
    capture_io(:stderr, fn ->
      capture_io(fn -> assert run_silent(["--bogus-flag", "somefile.ex"]) == {:error, 1} end)
    end)
  end

  # ---------------------------------------------------------------------------
  # Non-existent / non-Elixir paths
  # ---------------------------------------------------------------------------

  test "ignores non-.ex files" do
    with_tmp_file("hello", ".txt", fn path -> assert run_silent([path]) == :ok end)
  end

  test "warns and returns ok for missing path" do
    capture_io(:stderr, fn -> assert run_silent(["/nonexistent/path/that/does/not/exist"]) == :ok end)
  end

  # ---------------------------------------------------------------------------
  # Write mode (default)
  # ---------------------------------------------------------------------------

  test "formats file in-place in write mode" do
    with_tmp_file(@unaligned, fn path ->
      original = File.read!(path)
      capture_io(fn -> assert run_silent([path]) == :ok end)
      formatted = File.read!(path)
      assert formatted != original
    end)
  end

  test "returns ok when file is already formatted" do
    with_tmp_file(@already_aligned, fn path -> assert run_silent([path]) == :ok end)
  end

  # ---------------------------------------------------------------------------
  # --check mode
  # ---------------------------------------------------------------------------

  test "--check returns ok when file needs no changes" do
    with_tmp_file(@already_aligned, fn path -> assert run_silent(["--check", path]) == :ok end)
  end

  test "--check returns error when file would change" do
    with_tmp_file(@unaligned, fn path ->
      output =
        capture_io(:stderr, fn -> assert run_no_summary(["--check", path]) == {:error, 1} end)

      assert output =~ "would reformat" or output =~ "file(s) would be reformatted"
      # file must not be modified
      assert File.read!(path) == @unaligned
    end)
  end

  # ---------------------------------------------------------------------------
  # --dry-run mode
  # ---------------------------------------------------------------------------

  test "--dry-run returns changed result without writing" do
    with_tmp_file(@unaligned, fn path ->
      output =
        capture_io(fn ->
          capture_io(:stderr, fn -> assert run_no_summary(["--dry-run", path]) == {:error, 1} end)
        end)

      assert output =~ "---"
      assert File.read!(path) == @unaligned
    end)
  end

  test "--dry-run returns ok when file needs no changes" do
    with_tmp_file(@already_aligned, fn path ->
      capture_io(fn -> assert run_silent(["--dry-run", path]) == :ok end)
    end)
  end

  # ---------------------------------------------------------------------------
  # Directory traversal
  # ---------------------------------------------------------------------------

  test "collects .ex files from a directory" do
    with_tmp_dir(fn dir ->
      path = Path.join(dir, "sample.ex")
      File.write!(path, @already_aligned)
      capture_io(fn -> assert run_silent([dir]) == :ok end)
    end)
  end

  test "ignores non-.ex files in directory" do
    with_tmp_dir(fn dir ->
      File.write!(Path.join(dir, "notes.txt"), "hello")
      assert run_silent([dir]) == :ok
    end)
  end

  # ---------------------------------------------------------------------------
  # --line-length option
  # ---------------------------------------------------------------------------

  test "accepts --line-length option" do
    with_tmp_file(@already_aligned, fn path ->
      assert run_silent(["--line-length", "120", path]) == :ok
    end)
  end

  # ---------------------------------------------------------------------------
  # --wrap-short-lines option
  # ---------------------------------------------------------------------------

  test "accepts --wrap-short-lines flag" do
    with_tmp_file(@already_aligned, fn path ->
      assert run_silent(["--wrap-short-lines", path]) == :ok
    end)
  end

  # ---------------------------------------------------------------------------
  # --wrap-with option
  # ---------------------------------------------------------------------------

  test "accepts --wrap-with backslash option" do
    with_tmp_file(@already_aligned, fn path ->
      assert run_silent(["--wrap-with", "backslash", path]) == :ok
    end)
  end

  test "accepts --wrap-with do option" do
    with_tmp_file(@already_aligned, fn path -> assert run_silent(["--wrap-with", "do", path]) == :ok end)
  end

  # ---------------------------------------------------------------------------
  # Error handling in process_file
  # ---------------------------------------------------------------------------

  test "handles unreadable file gracefully" do
    path = "/root/no_permission.ex"

    capture_io(:stderr, fn ->
      result = run_silent([path])
      # Either warns about missing path or returns error — must not crash
      assert result == :ok or result == {:error, 1}
    end)
  end

  # ---------------------------------------------------------------------------
  # --silent option
  # ---------------------------------------------------------------------------

  test "--silent suppresses reformatted output in write mode" do
    with_tmp_file(@unaligned, fn path ->
      output =
        capture_io(fn -> assert run(["--silent", path]) == :ok end)

      assert output == ""
    end)
  end

  test "-s alias suppresses output" do
    with_tmp_file(@unaligned, fn path ->
      output =
        capture_io(fn -> assert run(["-s", path]) == :ok end)

      assert output == ""
    end)
  end

  test "--silent suppresses dry-run stdout" do
    with_tmp_file(@unaligned, fn path ->
      output =
        capture_io(fn -> assert run(["--silent", "--dry-run", path]) == {:error, 1} end)

      assert output == ""
      # file must not be written
      assert File.read!(path) == @unaligned
    end)
  end

  test "--silent does not suppress stderr summary in check mode" do
    with_tmp_file(@unaligned, fn path ->
      # The summary "N file(s) would be reformatted" goes to stderr from run/1
      # regardless of --silent; capture both devices to confirm no stdout leak.
      stdout =
        capture_io(fn ->
          capture_io(:stderr, fn -> assert run(["--silent", "--check", path]) == {:error, 1} end)
        end)

      assert stdout == ""
    end)
  end

  # ---------------------------------------------------------------------------
  # process_file rescue branch
  # ---------------------------------------------------------------------------

  test "returns error tuple when a file raises during formatting" do
    # Create a file, then remove it between collection and processing by
    # mocking: use a path that passes File.regular? but fails File.read!.
    # Simplest approach: write a valid .ex file then delete it after we know
    # collect_files has seen it, but before process_file reads it.
    # We achieve this by writing a temp file, then chmod 000.
    with_tmp_file("defmodule Bad do\nend\n", fn path -> File.chmod!(path, 0o000)

      stderr =
        capture_io(:stderr, fn ->
          result = run_silent([path])
          assert result == {:error, 1}
        end)

      assert stderr =~ "exalign:"
      File.chmod!(path, 0o644)
    end)
  end

  # ---------------------------------------------------------------------------
  # --eol-at-eof option
  # ---------------------------------------------------------------------------

  test "accepts --eol-at-eof add option" do
    with_tmp_file("x = 1", fn path ->
      assert run_silent(["--eol-at-eof", "add", path]) == :ok
      content = File.read!(path)
      assert String.ends_with?(content, "\n"), "should add newline with --eol-at-eof add"
    end)
  end

  test "accepts --eol-at-eof remove option" do
    with_tmp_file("x = 1\n", fn path ->
      assert run_silent(["--eol-at-eof", "remove", path]) == :ok
      content = File.read!(path)
      refute String.ends_with?(content, "\n"), "should remove newline with --eol-at-eof remove"
    end)
  end

  test "--eol-at-eof add works with --dry-run" do
    with_tmp_file("x = 1", fn path ->
      original = File.read!(path)
      output =
        capture_io(fn ->
          # File would be changed, so returns error in dry-run mode
          result = run_no_summary(["--eol-at-eof", "add", "--dry-run", path])
          assert result == {:error, 1}
        end)

      # File should not be modified
      assert File.read!(path) == original
      # But output should show the would-be change
      assert String.contains?(output, original)
    end)
  end

  test "--eol-at-eof remove works with --check" do
    with_tmp_file("x = 1\n", fn path ->
      assert run_silent(["--eol-at-eof", "remove", "--check", path]) == {:error, 1}
    end)
  end

  test "--eol-at-eof add with already aligned file" do
    with_tmp_file(@already_aligned, fn path ->
      assert run_silent(["--eol-at-eof", "add", path]) == :ok
      content = File.read!(path)
      assert String.ends_with?(content, "\n")
    end)
  end

  # ---------------------------------------------------------------------------
  # Combined CLI options
  # ---------------------------------------------------------------------------

  test "combines --line-length and --wrap-with options" do
    with_tmp_file(@already_aligned, fn path ->
      assert run(["--line-length", "80", "--wrap-with", "do", path]) == :ok
    end)
  end

  test "combines --eol-at-eof and --line-length options" do
    with_tmp_file("x = 1", fn path ->
      assert run_silent(["--eol-at-eof", "add", "--line-length", "100", path]) == :ok
      content = File.read!(path)
      assert String.ends_with?(content, "\n")
    end)
  end

  test "combines --wrap-short-lines and --eol-at-eof options" do
    with_tmp_file("x = 1\n", fn path ->
      assert run_silent(["--wrap-short-lines", "--eol-at-eof", "remove", path]) == :ok
      content = File.read!(path)
      refute String.ends_with?(content, "\n")
    end)
  end

  test "formats multiple files with --eol-at-eof" do
    with_tmp_dir(fn dir ->
      file1 = Path.join(dir, "file1.ex")
      file2 = Path.join(dir, "file2.ex")
      File.write!(file1, "x = 1")
      File.write!(file2, "y = 2")

      assert run_silent(["--eol-at-eof", "add", dir]) == :ok

      content1 = File.read!(file1)
      content2 = File.read!(file2)

      assert String.ends_with?(content1, "\n")
      assert String.ends_with?(content2, "\n")
    end)
  end

  test "formats directory with mixed file types" do
    with_tmp_dir(fn dir ->
      _ex_file = Path.join(dir, "code.ex")
      _exs_file = Path.join(dir, "test.exs")
      _txt_file = Path.join(dir, "readme.txt")

      File.write!(Path.join(dir, "code.ex"), "x = 1")
      File.write!(Path.join(dir, "test.exs"), "y = 2")
      File.write!(Path.join(dir, "readme.txt"), "Not elixir code")

      capture_io(fn -> assert run_silent([dir]) == :ok end)
    end)
  end

  test "--wrap-short-lines with --line-length" do
    input = """
    case x do
      1 -> :one
      2 -> :two
      3 -> :three
    end
    """

    with_tmp_file(input, fn path ->
      assert run_silent(["--wrap-short-lines", "--line-length", "50", path]) == :ok
      content = File.read!(path)
      assert content =~ "case x do"
      assert content =~ ":one"
    end)
  end

  test "--line-length with alignment" do
    input = """
    x = 1
    foo = "bar"
    something_long = 42
    """

    with_tmp_file(input, fn path ->
      assert run_silent(["--line-length", "40", path]) == :ok
      content = File.read!(path)
      assert content =~ "x"
      assert content =~ "foo"
      assert content =~ "something_long"
    end)
  end
end
