defmodule Tinkex.CLITest do
  use Supertester.ExUnitFoundation, isolation: :full_isolation

  import ExUnit.CaptureIO

  alias Tinkex.CLI

  describe "help output" do
    test "shows global help with --help" do
      output =
        capture_io(fn ->
          assert {:ok, :help} = CLI.run(["--help"])
        end)

      assert output =~ "Usage:"
      assert output =~ "checkpoint"
      assert output =~ "version"
    end

    test "shows subcommand help" do
      output =
        capture_io(fn ->
          assert {:ok, :help} = CLI.run(["checkpoint", "--help"])
        end)

      assert output =~ "tinkex checkpoint"
      assert output =~ "--base-model"
    end
  end

  describe "routing and parsing" do
    test "routes --version alias to version command" do
      output =
        capture_io(fn ->
          assert {:ok, %{command: :version, version: version}} = CLI.run(["--version"])
          assert is_binary(version)
          assert version != ""
        end)

      assert output =~ "tinkex "
    end

    test "supports JSON version output" do
      output =
        capture_io(fn ->
          assert {:ok, %{command: :version, options: %{json: true}}} =
                   CLI.run(["version", "--json"])
        end)

      assert String.trim(output) |> String.starts_with?("{\"version\"")
    end

    test "errors on unknown command" do
      output =
        capture_io(:stderr, fn ->
          assert {:error, :invalid_args} = CLI.run(["unknown"])
        end)

      assert output =~ "Unknown command"
      assert output =~ "checkpoint"
    end
  end
end
