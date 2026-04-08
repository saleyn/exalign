defmodule Mix.Tasks.Exalign.Install do
  @shortdoc "Create or update .formatter.exs to use ExAlign"
  @moduledoc """
  Creates or updates `.formatter.exs` in the current project to register
  `ExAlign` as a formatter plugin.

  ## Usage

      mix exalign.install

  ## Behaviour

  - If `.formatter.exs` does **not** exist, a new one is created with sensible
    defaults.
  - If `.formatter.exs` already exists and `ExAlign` is already listed under
    `plugins:`, the file is left unchanged.
  - If `.formatter.exs` already exists but `ExAlign` is not yet listed, the task
    prints instructions for adding it manually — it will **not** overwrite a
    custom formatter config automatically.
  """

  use Mix.Task

  @formatter_file ".formatter.exs"

  @default_content """
  [
    plugins: [ExAlign],
    inputs:  ["{mix,.formatter}.exs", "{config,lib,test}/**/*.{ex,exs}"]
  ]
  """

  @impl Mix.Task
  def run(_args) do
    if File.exists?(@formatter_file) do
      content = File.read!(@formatter_file)

      if content =~ ~r/ExAlign/ do
        Mix.shell().info("#{@formatter_file} already contains ExAlign — nothing to do.")
      else
        Mix.shell().info("""
        #{@formatter_file} already exists but does not include ExAlign.
        Add ExAlign to the plugins list manually:

            # #{@formatter_file}
            [
              plugins: [ExAlign],
              inputs:  ["{mix,.formatter}.exs", "{config,lib,test}/**/*.{ex,exs}"]
            ]
        """)
      end
    else
      File.write!(@formatter_file, @default_content)
      Mix.shell().info("Created #{@formatter_file} with ExAlign plugin.")
    end
  end
end
