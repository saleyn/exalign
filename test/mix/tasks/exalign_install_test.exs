defmodule Mix.Tasks.Exalign.InstallTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  @formatter_file ".formatter.exs"

  setup do
    # Save and restore .formatter.exs around each test
    original = if File.exists?(@formatter_file), do: File.read!(@formatter_file), else: nil

    on_exit(fn ->
      if original do
        File.write!(@formatter_file, original)
      else
        File.rm(@formatter_file)
      end
    end)

    :ok
  end

  test "creates .formatter.exs when it does not exist" do
    File.rm(@formatter_file)

    output = capture_io(fn -> Mix.Tasks.Exalign.Install.run([]) end)

    assert File.exists?(@formatter_file)
    assert File.read!(@formatter_file) =~ "ExAlign"
    assert output =~ "Created"
  end

  test "does nothing when ExAlign is already configured" do
    File.write!(@formatter_file, "[plugins: [ExAlign], inputs: []]\n")

    output = capture_io(fn -> Mix.Tasks.Exalign.Install.run([]) end)

    assert output =~ "nothing to do"
  end

  test "prints manual instructions when file exists without ExAlign" do
    File.write!(@formatter_file, "[inputs: [\"lib/**/*.ex\"]]\n")

    output = capture_io(fn -> Mix.Tasks.Exalign.Install.run([]) end)

    assert output =~ "ExAlign"
    # File must not be modified
    assert File.read!(@formatter_file) == "[inputs: [\"lib/**/*.ex\"]]\n"
  end
end
